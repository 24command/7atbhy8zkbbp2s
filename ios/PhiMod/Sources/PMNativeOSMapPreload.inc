// Entry-target resources are private to this Map visit. Workers only produce
// bytes; they hold neither Map nor Unity handles, and completion is weak-owned.
dispatch_queue_t stillDecodeQueue() {
    static dispatch_queue_t queue = dispatch_queue_create("PhiMod.map.still", DISPATCH_QUEUE_SERIAL);
    return queue;
}
void cancelPreload(Map &m, int keepMediaScreen = -1) {
    m.preload.pending.reset();
    for (auto &item : m.items)
        if (item.media && item.media->preloaded && item.screen != keepMediaScreen)
            stopMedia(m,*item.media);
    for (auto i=m.preload.assets.rbegin(); i!=m.preload.assets.rend(); ++i) releaseAsset(m,*i);
    m.preload = {};
}
void beginPreload(Map &m, int screen) {
    cancelPreload(m);
    auto &plan = m.preload.plan;
    plan.source = m.page; plan.target = screen;
    std::vector<bool> active(m.items.size(),false);
    for (size_t i=0; i<m.items.size(); ++i) {
        const Item &item = m.items[i];
        active[i] = preload::eligible(item.object != 0,item.screen,screen,item.manual,
            item.parent < 0 || active.at(item.parent),layout::opacity(0,item.start,item.duration,item.fade));
        if (active[i] && (item.artPath || item.media)) plan.nodes.push_back(int(i));
    }
}
void requestStill(Map &m, int node) {
    const Item &item = m.items.at(node);
    auto &stage = m.preload;
    stage.pendingNode = node;
    stage.pending = std::make_shared<StillDelivery>();
    std::weak_ptr<StillDelivery> ticket = stage.pending;
    NSString *path = item.artPath;
    int pixels = m.pagePixels.at(stage.plan.target);
    bool mask = item.artMask;
    dispatch_async(stillDecodeQueue(), ^{ @autoreleasepool {
        if (ticket.expired()) return;
        NSData *imageBytes = nil, *maskBytes = nil;
        float aspect = 1;
        bool ok = checked([&]{
            CGImageRef image = createThumbnail(path,pixels), silhouette = nullptr;
            @try {
                aspect = float(CGImageGetWidth(image))/float(CGImageGetHeight(image));
                imageBytes = encodeImage(image);
                if (mask) {
                    silhouette = createFlashSilhouette(image);
                    if (!silhouette) throw std::runtime_error("Map flash silhouette creation failed");
                    maskBytes = encodeImage(silhouette);
                }
            } @finally {
                if (silhouette) CGImageRelease(silhouette);
                CGImageRelease(image);
            }
        });
        auto delivery = ticket.lock();
        if (!delivery) return;
        if (ok) { delivery->image = imageBytes; delivery->silhouette = maskBytes; delivery->aspect = aspect; }
        // Main reads payload only after complete is published on its own queue.
        dispatch_async(dispatch_get_main_queue(), ^{
            if (auto owner = ticket.lock()) owner->complete = true;
        });
    }});
}
void uploadStill(Map &m) {
    auto &stage = m.preload;
    const Item &item = m.items.at(stage.pendingNode);
    auto payload = std::move(stage.pending);
    stage.pendingNode = -1;
    std::string key = item.artPath.UTF8String;
    const size_t first = m.assets.size();
    Art art;
    bool ok = payload->image && checked([&]{
        art.aspect = payload->aspect;
        art.sprite = uploadSprite(m,payload->image,item.artReadable);
        if (payload->silhouette) art.silhouette = uploadSprite(m,payload->silhouette,false);
    });
    if (ok) {
        stage.assets.insert(stage.assets.end(),m.assets.begin()+first,m.assets.end());
        stage.art.emplace(key,art);
    } else {
        // Optional work cannot poison the visible entrance or leak a partial
        // texture/sprite. Normal page acquisition remains the cold fallback.
        while (m.assets.size()>first) releaseAsset(m,m.assets.back());
        stage.failed.insert(key);
    }
}
void stepPreload(Map &m, int screen) {
    if (!m.preload.plan.matches(m.page,screen)) beginPreload(m,screen);
    auto &stage = m.preload;
    if (stage.pending && stage.pending->complete) { uploadStill(m); return; }
    // At most one still resource (including mask) / media step per tick. A slow
    // resource cannot starve the others. A single Unity call is not preemptible.
    for (size_t remaining=stage.plan.nodes.size(); remaining; --remaining) {
        int index = stage.plan.next();
        auto &item = m.items.at(index);
        if (item.media) {
            auto &media = *item.media;
            if (media.failed || media.first.held()) continue;
            media.preloaded = true;
            warmMedia(m,media,false);
            return;
        }
        if (stage.pending || stage.art.count(item.artPath.UTF8String) || stage.failed.count(item.artPath.UTF8String)) continue;
        requestStill(m,index);
        return;
    }
}
