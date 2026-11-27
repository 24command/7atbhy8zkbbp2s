#include "PMNativeOSFrameSequence.hpp"
// GIF/PMA work stays on one decoder queue. Only tick uploads textures or touches Unity.
struct GifSource {
    CGImageSourceRef source = nullptr;
    NSObject *sequence = nil;
    size_t count = 0;
    ~GifSource() { if (source) CFRelease(source); }
};
// Queue/main-queue blocks hold this weakly. Cancelling a visit drops completed
// bytes immediately instead of retaining a page of frames in queued callbacks.
struct GifDelivery { NSData *bytes = nil; };
struct GifVisit {
    std::shared_ptr<GifSource> decoder = std::make_shared<GifSource>();
    std::shared_ptr<GifDelivery> delivery;
    NSData *ready = nil;
    NSUInteger width=0, height=0;
    uint64_t revision=0;
    playback::SequenceClock sequenceClock;
    playback::SequenceSlot readySlot{}, requestSlot{};
    size_t frame = 0, count = 0;
    float aspect = 1;
    double delay = .1, due = 0;
    bool pending = false, finished = false, failed = false;
};
struct Media {
    NSString *path = nil;
    Handle raw{}, fitter{}, player{}, texture{};
    int pixels{}, textureWidth{}, textureHeight{};
    uint64_t uploadedRevision=0;
    bool loop{}, playing{}, received{}, failed{}, deferred{}, slowStartReported{};
    double started{};
    P lastVideoTexture{}; // borrowed from VideoPlayer and RawImage
    std::shared_ptr<GifVisit> gif;
    readiness::FirstFrame first;
};
bool isAnimated(NSString *path) {
    NSString *ext = path.pathExtension.lowercaseString;
    return [ext isEqualToString:@"gif"] || [ext isEqualToString:@"mp4"] || [ext isEqualToString:@"pma"];
}
dispatch_queue_t gifDecodeQueue() {
    static dispatch_queue_t queue = dispatch_queue_create("PhiMod.map.GIF", DISPATCH_QUEUE_SERIAL);
    return queue;
}
void requestGif(Media &media) {
    auto &g = *media.gif;
    std::weak_ptr<GifVisit> visit = media.gif;
    std::weak_ptr<GifSource> queuedDecoder = g.decoder;
    g.delivery = std::make_shared<GifDelivery>();
    std::weak_ptr<GifDelivery> delivery = g.delivery;
    NSString *path = media.path;
    int pixels = media.pixels;
    size_t frame = g.frame;
    const bool sequence=[path.pathExtension.lowercaseString isEqualToString:@"pma"];
    const auto ticket=g.requestSlot;
    g.pending = true;
    dispatch_queue_t queue = gifDecodeQueue();
    dispatch_async(queue, ^{ @autoreleasepool {
        if (visit.expired()) return;
        auto decoder = queuedDecoder.lock();
        if (!decoder) return;
        NSData *png = nil; // GIF PNG or PMA straight RGBA, selected by sequence.
        NSUInteger width=0, height=0;
        uint64_t revision=0;
        float aspect = 1;
        double delay = .1;
        bool ok = checked([&]{
            if ([path.pathExtension.lowercaseString isEqualToString:@"pma"]) {
                NSError *error = nil;
                if (!decoder->sequence) decoder->sequence = PMOSFrameSequenceOpen(path,&error);
                if (!decoder->sequence) throw std::runtime_error((error.localizedDescription ?: @"Invalid map PMA").UTF8String);
                decoder->count = PMOSFrameSequenceCount(decoder->sequence);
                delay = PMOSFrameSequenceDelay(decoder->sequence);
                if (visit.expired()) return;
                png = PMOSFrameSequenceRGBAFrame(decoder->sequence,frame,pixels,&width,&height,&revision,&error);
                if (!png) throw std::runtime_error((error.localizedDescription ?: @"PMA frame decode failed").UTF8String);
                aspect = float(width)/height;
                return;
            }
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
        if (visit.expired()) return;
        auto payload = delivery.lock();
        if (!payload) return;
        payload->bytes = png;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (auto owner = visit.lock()) {
                auto decoder = queuedDecoder.lock();
                auto payload = delivery.lock();
                if (owner->frame != frame || owner->decoder != decoder || !payload) return;
                owner->delivery.reset();
                owner->pending = false;
                if (sequence) {
                    // Late success can advance the displayed frame without changing
                    // the clock. Late failure is ignored once its target is obsolete.
                    if (ok) { owner->delay=delay; owner->count=count; }
                    if (!(ok ? owner->sequenceClock.accepts(ticket) : owner->sequenceClock.acceptsFailure(ticket))) return;
                    owner->readySlot=ticket;
                }
                owner->failed = !ok; owner->ready = payload->bytes;
                owner->width=width; owner->height=height; owner->revision=revision;
                owner->aspect = aspect; owner->delay = delay; owner->count = count;
            }
        });
    }});
}
std::shared_ptr<Media> buildMedia(Map &m, P tr, NSString *path, bool cover, bool loop, int pixels,
                                  blend::Layer *additive = nullptr) {
    auto media = std::make_shared<Media>();
    media->path = [path copy]; media->loop = loop; media->pixels = [path.pathExtension.lowercaseString isEqualToString:@"gif"] ? std::min(1024,pixels) : pixels;
    Object childObject = child(m,tr,"Map Media");
    P go = m.get(childObject.go);
    stretch(m.r,m.get(childObject.rect));
    P raw = add(m.r,go,"UnityEngine.UI","RawImage");
    media->raw = m.keep(raw);
    if (additive) bindAdditive(m,*additive,childObject.go,media->raw);
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
    }
    // Textures are acquired by warm/play, never for an inactive page.
    return media;
}
// Explicit cancellation is also used by displayPage; a staged player is not
// "playing", so cancellation must not depend on the old playing edge alone.
void stopMedia(Map &m, Media &media) {
    bool live = media.playing || media.first.started() || media.received || bool(media.gif);
    media.playing = false; media.deferred = false;
    media.gif.reset(); // Invalidates decoder queue completions through their weak owner.
    media.first.reset();
    media.lastVideoTexture = nullptr; media.received = false;
    if (!live && !media.texture) return;
    P raw = m.get(media.raw), player = m.get(media.player);
    flag(m.r,raw,"set_enabled",false);
    m.r.call(raw,"set_texture",{"UnityEngine.Texture"},{nullptr});
    if (player) m.r.call(player,"Stop");
    releaseAsset(m,media.texture); media.texture=0;
    media.textureWidth=media.textureHeight=0; media.uploadedRevision=0;
}
void failMedia(Map &m, Media &media, NSString *reason) {
    if (media.failed) return;
    media.failed = true; media.deferred = false; media.playing = false;
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
void deferMedia(Media &media, NSString *reason) {
    if(media.failed || media.deferred || media.first.held())return;
    media.deferred=true;
    PMDiagnosticsWrite([[NSString stringWithFormat:@"Map media still preparing (%@): %@; continue behind poster",media.path,reason] UTF8String]);
    // A deadline is NOT a decoder failure. Retain Prepare/GIF work and ownership.
}
// The only PMA upload adapter. The pointer remains owned by g.ready throughout
// the synchronous managed calls. No managed byte array, PNG encode or LoadImage.
P uploadSequence(Map &m, Media &media) {
    auto &g=*media.gif;
    if (!g.ready || !g.width || !g.height || g.width>2048 || g.height>2048 ||
        g.ready.length!=g.width*g.height*4) throw std::runtime_error("Invalid PMA RGBA payload");
    if (media.texture && media.uploadedRevision==g.revision) return m.get(media.texture);
    if (!media.texture) media.texture=newTexture(m,int(g.width),int(g.height));
    else if (media.textureWidth!=int(g.width) || media.textureHeight!=int(g.height)) {
        int w=int(g.width),h=int(g.height),format=4; bool mip=false;
        if (!m.r.unbox<bool>(m.r.call(m.get(media.texture),"Reinitialize",
            {"System.Int32","System.Int32","UnityEngine.TextureFormat","System.Boolean"},{&w,&h,&format,&mip})))
            throw std::runtime_error("PMA texture resize failed");
    }
    media.textureWidth=int(g.width); media.textureHeight=int(g.height);
    P texture=m.get(media.texture);
    const void *bytes=g.ready.bytes; int size=int(g.ready.length); bool no=false;
    m.r.call(texture,"LoadRawTextureData",{"System.IntPtr","System.Int32"},{&bytes,&size});
    m.r.call(texture,"Apply",{"System.Boolean","System.Boolean"},{&no,&no});
    media.uploadedRevision=g.revision;
    return texture;
}
void warmMedia(Map &m, Media &media, bool expired) {
    if (media.failed || media.first.held()) return;
    if (expired) { deferMedia(media,@"first-frame deadline (3s)"); return; }
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
            P texture;
            if ([media.path.pathExtension.lowercaseString isEqualToString:@"pma"]) texture=uploadSequence(m,media);
            else {
                if (!media.texture) media.texture=newTexture(m);
                texture=m.get(media.texture); upload(r,texture,g.ready,false);
            }
            attachMedia(m,media,texture,g.aspect);
            g.ready = nil; g.due = g.delay; // Authored t=0; never charge hidden wall time.
            if (![media.path.pathExtension.lowercaseString isEqualToString:@"pma"]) {
                g.frame = playback::nextFrame(g.frame,g.count,media.loop);
                g.finished = g.frame == g.count;
            }
            // PMA keeps frame zero; its clock starts only at reveal.
            // Do not request/advance a second frame while covered.
        }
        media.first.poll(false,true,false);
    },&reason)) failMedia(m,media,reason);
}
void syncMedia(Map &m, Media &media, bool play, double t) {
    if (!play) { stopMedia(m,media); return; }
    if (media.failed) return;
    if(media.deferred){
        warmMedia(m,media,false);
        if(media.failed || !media.first.held())return;
        media.deferred=false;
    }
    NSString *reason = nil;
    if (!checked([&]{
        Runtime &r = m.r;
        P player = m.get(media.player);
        if (media.first.release()) {
            media.playing = true; media.started = t; media.slowStartReported = false;
            if (player) r.call(player,"Play"); // Resume the paused first frame, no Stop/Prepare.
            else {
                auto &g = *media.gif;
                if ([media.path.pathExtension.lowercaseString isEqualToString:@"pma"]) {
                    g.sequenceClock.start(t,true); // Held frame zero is already visible.
                    g.frame=0; g.finished=false;
                    const auto next=g.sequenceClock.next(g.count,media.loop);
                    if (next!=g.sequenceClock.wanted) {
                        g.requestSlot=next;g.frame=next.frame;requestGif(media);
                    }
                } else {
                    g.due = t + g.delay;
                    if (!g.finished) requestGif(media);
                }
            }
            return;
        }
        if (!media.playing) {
            media.playing = true; media.started = t; media.slowStartReported = false;
            if (player) r.call(player,"Play");
            else {
                media.gif = std::make_shared<GifVisit>();
                media.gif->sequenceClock.start(t,false); // New visit has a fresh zero origin.
            }
        }
        if (!player && ![media.path.pathExtension.lowercaseString isEqualToString:@"pma"] && !media.texture)
            media.texture=newTexture(m);
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
        } else if ([media.path.pathExtension.lowercaseString isEqualToString:@"pma"]) {
            auto &g=*media.gif;
            const auto wanted=g.sequenceClock.sample(t,g.count,g.delay,media.loop);
            // Recheck on upload: the target/lap can advance after completion.
            // Behind wanted is OK for a same-lap success newer than the screen.
            if (g.ready && !g.sequenceClock.accepts(g.readySlot)) g.ready=nil;
            if (g.failed && !g.sequenceClock.acceptsFailure(g.readySlot)) g.failed=false;
            if (g.failed && g.readySlot==wanted) {failMedia(m,media,@"PMA frame decode failed");return;}
            if (g.ready && g.sequenceClock.canDisplay(g.readySlot)) {
                texture=uploadSequence(m,media);aspect=g.aspect;
                g.ready=nil;
                g.sequenceClock.displayed(g.readySlot);
                // Never finish solely because time passed: the last image must upload.
                g.finished=!media.loop && g.count && g.readySlot.frame==g.count-1;
            }
            if (!g.pending && !g.ready && !g.failed) {
                // Keep only one upcoming frame. This allows a 60fps sequence to
                // meet the next display tick without building a frame cache.
                const auto ticket=g.sequenceClock.needsFrame() ? wanted : g.sequenceClock.next(g.count,media.loop);
                if (g.sequenceClock.needsFrame() || ticket!=wanted) {
                    g.requestSlot=ticket;g.frame=ticket.frame;
                    requestGif(media);
                }
            }
            if (!texture) return;
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
