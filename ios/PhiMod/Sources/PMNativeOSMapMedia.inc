// GIF work stays on one decoder queue. Only tick uploads textures or touches Unity.
struct GifSource {
    CGImageSourceRef source = nullptr;
    size_t count = 0;
    ~GifSource() { if (source) CFRelease(source); }
};
struct GifVisit {
    std::shared_ptr<GifSource> decoder = std::make_shared<GifSource>();
    NSData *ready = nil;
    size_t frame = 0, count = 0;
    float aspect = 1;
    double delay = .1, due = 0;
    bool pending = false, finished = false, failed = false;
};
struct Media {
    NSString *path = nil;
    Handle raw{}, fitter{}, player{}, texture{};
    int pixels{};
    bool loop{}, playing{}, received{}, failed{}, slowStartReported{};
    double started{};
    P lastVideoTexture{}; // borrowed from VideoPlayer and RawImage
    std::shared_ptr<GifVisit> gif;
};
bool isAnimated(NSString *path) {
    NSString *ext = path.pathExtension.lowercaseString;
    return [ext isEqualToString:@"gif"] || [ext isEqualToString:@"mp4"];
}
void requestGif(Media &media) {
    auto &g = *media.gif;
    std::weak_ptr<GifVisit> visit = media.gif;
    auto decoder = g.decoder;
    NSString *path = media.path;
    int pixels = media.pixels;
    size_t frame = g.frame;
    g.pending = true;
    static dispatch_queue_t queue = dispatch_queue_create("PhiMod.map.GIF", DISPATCH_QUEUE_SERIAL);
    dispatch_async(queue, ^{ @autoreleasepool {
        if (visit.expired()) return;
        NSData *png = nil;
        float aspect = 1;
        double delay = .1;
        bool ok = checked([&]{
            if (!decoder->source) {
                NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
                if (![attrs[NSFileType] isEqual:NSFileTypeRegular] || [attrs[NSFileSize] unsignedLongLongValue] > 32ull*1024*1024)
                    throw std::runtime_error("Map GIF exceeds file limit or is missing");
                decoder->source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],
                    (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache:@NO});
                if (!decoder->source || ![(__bridge NSString *)CGImageSourceGetType(decoder->source) isEqualToString:@"com.compuserve.gif"])
                    throw std::runtime_error("Invalid map GIF");
                decoder->count = CGImageSourceGetCount(decoder->source);
            }
            if (frame >= decoder->count || decoder->count > 4096) throw std::runtime_error("Invalid map GIF frame count");
            NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(decoder->source,frame,nullptr));
            int w = [props[(__bridge NSString *)kCGImagePropertyPixelWidth] intValue];
            int h = [props[(__bridge NSString *)kCGImagePropertyPixelHeight] intValue];
            if (w < 1 || h < 1 || w > 4096 || h > 4096) throw std::runtime_error("Invalid map GIF dimensions");
            NSDictionary *times = props[(__bridge NSString *)kCGImagePropertyGIFDictionary];
            delay = playback::frameDelay([times[(__bridge NSString *)kCGImagePropertyGIFUnclampedDelayTime] doubleValue],
                                         [times[(__bridge NSString *)kCGImagePropertyGIFDelayTime] doubleValue]);
            CGImageRef image = CGImageSourceCreateThumbnailAtIndex(decoder->source,frame,(__bridge CFDictionaryRef)@{
                (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
                (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@(pixels)});
            if (!image) throw std::runtime_error("Map GIF frame decode failed");
            @try { aspect = float(CGImageGetWidth(image))/CGImageGetHeight(image); png = encodeImage(image); }
            @finally { CGImageRelease(image); CGImageSourceRemoveCacheAtIndex(decoder->source,frame); }
        });
        size_t count = decoder->count;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (auto owner = visit.lock()) {
                owner->pending = false; owner->failed = !ok; owner->ready = png;
                owner->aspect = aspect; owner->delay = delay; owner->count = count;
            }
        });
    }});
}
std::shared_ptr<Media> buildMedia(Map &m, P tr, NSString *path, bool cover, bool loop, int pixels) {
    auto media = std::make_shared<Media>();
    media->path = [path copy]; media->loop = loop; media->pixels = std::min(1024,pixels);
    Object childObject = child(m,tr,"Map Media");
    P go = m.get(childObject.go);
    stretch(m.r,m.get(childObject.rect));
    P raw = add(m.r,go,"UnityEngine.UI","RawImage");
    media->raw = m.keep(raw);
    flag(m.r,raw,"set_raycastTarget",false);
    flag(m.r,raw,"set_enabled",false);
    media->fitter = m.keep(fit(m.r,go,1,cover));
    if ([path.pathExtension.lowercaseString isEqualToString:@"mp4"]) {
        P player = add(m.r,go,"UnityEngine.Video","VideoPlayer");
        media->player = m.keep(player);
        flag(m.r,player,"set_playOnAwake",false);
        int url = 1, apiOnly = 4, silent = 0;
        m.r.call(player,"set_source",{"UnityEngine.Video.VideoSource"},{&url});
        m.r.call(player,"set_renderMode",{"UnityEngine.Video.VideoRenderMode"},{&apiOnly});
        m.r.call(player,"set_audioOutputMode",{"UnityEngine.Video.VideoAudioOutputMode"},{&silent});
        flag(m.r,player,"set_isLooping",loop);
        m.r.call(player,"set_url",{"System.String"},{m.r.managedString([NSURL fileURLWithPath:path].absoluteString)});
    } else {
        media->texture = newTexture(m);
    }
    return media;
}
void syncMedia(Map &m, Media &media, bool play, double t) {
    if (media.failed) return;
    Runtime &r = m.r;
    P raw = m.get(media.raw), player = m.get(media.player);
    if (play != media.playing) {
        media.playing = play;
        if (!play) {
            media.gif.reset(); media.lastVideoTexture = nullptr; media.received = false;
            flag(r,raw,"set_enabled",false);
            r.call(raw,"set_texture",{"UnityEngine.Texture"},{nullptr});
            if (player) r.call(player,"Stop");
            return;
        }
        media.started = t;
        media.slowStartReported = false;
        if (player) r.call(player,"Play");
        else media.gif = std::make_shared<GifVisit>();
    }
    if (!play) return;
    P texture = nullptr;
    float aspect = 1;
    if (player) {
        texture = r.call(player,"get_texture");
        if (!texture && !media.received && !media.slowStartReported && t-media.started > 15) {
            PMDiagnosticsWrite([[NSString stringWithFormat:@"Map VideoPlayer still waiting for %@",media.path.lastPathComponent] UTF8String]);
            media.slowStartReported = true;
        }
        if (!texture || texture == media.lastVideoTexture) return;
        int w = r.unbox<int>(r.call(texture,"get_width")), h = r.unbox<int>(r.call(texture,"get_height"));
        if (w < 1 || h < 1) return;
        aspect = float(w)/h; media.lastVideoTexture = texture;
    } else {
        auto &g = *media.gif;
        if (g.failed) { media.failed = true; media.gif.reset(); return; }
        if (g.finished || g.pending) return;
        if (!g.ready) { requestGif(media); return; }
        if (t < g.due) return;
        texture = m.get(media.texture); aspect = g.aspect;
        upload(r,texture,g.ready,false);
        g.ready = nil; g.due = t + g.delay;
        g.frame = playback::nextFrame(g.frame,g.count,media.loop);
        g.finished = g.frame == g.count;
        if (!g.finished) requestGif(media);
    }
    r.call(m.get(media.fitter),"set_aspectRatio",{"System.Single"},{&aspect});
    r.call(raw,"set_texture",{"UnityEngine.Texture"},{texture});
    if (!media.received) flag(r,raw,"set_enabled",true);
    media.received = true;
}
