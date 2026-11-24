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
    readiness::FirstFrame first;
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
            if (!png.length) throw std::runtime_error("Map GIF frame encode failed");
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
// Explicit cancellation is also used by displayPage; a staged player is not
// "playing", so cancellation must not depend on the old playing edge alone.
void stopMedia(Map &m, Media &media) {
    bool live = media.playing || media.first.started() || media.received || bool(media.gif);
    media.playing = false;
    media.gif.reset(); // Invalidates decoder queue completions through their weak owner.
    media.first.reset();
    media.lastVideoTexture = nullptr; media.received = false;
    if (!live) return;
    P raw = m.get(media.raw), player = m.get(media.player);
    flag(m.r,raw,"set_enabled",false);
    m.r.call(raw,"set_texture",{"UnityEngine.Texture"},{nullptr});
    if (player) m.r.call(player,"Stop");
}
void failMedia(Map &m, Media &media, NSString *reason) {
    if (media.failed) return;
    media.failed = true; media.playing = false;
    media.first.phase = readiness::Phase::Failed;
    media.gif.reset();
    PMDiagnosticsWrite([[NSString stringWithFormat:@"Map media fallback (%@): %@", media.path, reason] UTF8String]);
    // Leave an uploaded frame (or authored still/background beneath the RawImage)
    // in place. In particular, do not destroy the map on a bad media URL/codec.
    P player = m.get(media.player);
    if (player) checked([&]{ m.r.call(player,media.received ? "Pause" : "Stop"); });
    if (!media.received) checked([&]{
        flag(m.r,m.get(media.raw),"set_enabled",false);
        m.r.call(m.get(media.raw),"set_texture",{"UnityEngine.Texture"},{nullptr});
    });
}
void attachMedia(Map &m, Media &media, P texture, float aspect) {
    m.r.call(m.get(media.fitter),"set_aspectRatio",{"System.Single"},{&aspect});
    m.r.call(m.get(media.raw),"set_texture",{"UnityEngine.Texture"},{texture});
    if (!media.received) flag(m.r,m.get(media.raw),"set_enabled",true);
    media.received = true;
}
void warmMedia(Map &m, Media &media, bool expired) {
    if (media.failed || media.first.held()) return;
    if (media.first.poll(false,false,expired) == readiness::Action::Fail) {
        failMedia(m,media,@"first-frame deadline (3s)"); return;
    }
    NSString *reason = nil;
    if (!checked([&]{
        Runtime &r = m.r;
        P player = m.get(media.player);
        if (!media.first.started()) {
            auto action = media.first.begin(player != nullptr);
            if (action == readiness::Action::Prepare) {
                NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:media.path error:nil];
                if (![attrs[NSFileType] isEqual:NSFileTypeRegular] || ![attrs[NSFileSize] unsignedLongLongValue])
                    throw std::runtime_error("Map video is missing or empty");
                r.call(player,"Prepare");
            } else media.gif = std::make_shared<GifVisit>();
        }
        if (player) {
            if (media.first.phase == readiness::Phase::Preparing) {
                bool prepared = r.unbox<bool>(r.call(player,"get_isPrepared"));
                if (media.first.poll(prepared,false,false) == readiness::Action::Play) r.call(player,"Play");
                return; // Prepared/allocated texture is not a decoded frame.
            }
            P texture = r.call(player,"get_texture");
            if (!texture || r.unbox<int64_t>(r.call(player,"get_frame")) < 0) return;
            int w = r.unbox<int>(r.call(texture,"get_width")), h = r.unbox<int>(r.call(texture,"get_height"));
            if (w < 1 || h < 1) return;
            attachMedia(m,media,texture,float(w)/h);
            media.lastVideoTexture = texture;
            r.call(player,"Pause"); // Keep the decoder and texture, never Stop at reveal.
        } else {
            auto &g = *media.gif;
            if (g.failed) { failMedia(m,media,@"first GIF frame decode failed"); return; }
            if (g.pending) return;
            if (!g.ready) { requestGif(media); return; }
            P texture = m.get(media.texture);
            upload(r,texture,g.ready,false);
            attachMedia(m,media,texture,g.aspect);
            g.ready = nil; g.due = g.delay; // Authored t=0; never charge hidden wall time.
            g.frame = playback::nextFrame(g.frame,g.count,media.loop);
            g.finished = g.frame == g.count;
            // Do not request/advance a second frame while covered.
        }
        media.first.poll(false,true,false);
    },&reason)) failMedia(m,media,reason);
}
void syncMedia(Map &m, Media &media, bool play, double t) {
    if (!play) { stopMedia(m,media); return; }
    if (media.failed) return;
    NSString *reason = nil;
    if (!checked([&]{
        Runtime &r = m.r;
        P player = m.get(media.player);
        if (media.first.release()) {
            media.playing = true; media.started = t; media.slowStartReported = false;
            if (player) r.call(player,"Play"); // Resume the paused first frame, no Stop/Prepare.
            else {
                auto &g = *media.gif;
                g.due = t + g.delay;
                if (!g.finished) requestGif(media);
            }
            return;
        }
        if (!media.playing) {
            media.playing = true; media.started = t; media.slowStartReported = false;
            if (player) r.call(player,"Play");
            else media.gif = std::make_shared<GifVisit>();
        }
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
            if (g.failed) { failMedia(m,media,@"GIF frame decode failed"); return; }
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
        attachMedia(m,media,texture,aspect);
    },&reason)) failMedia(m,media,reason);
}
