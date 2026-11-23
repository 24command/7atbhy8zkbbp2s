// The scene owns playback and the completion stamp. Source lookup and AV metadata
// run off-main. UIKit and Unity-facing callbacks are fenced to the original visit.
- (BOOL)playUnlockAtIndex:(NSUInteger)index completion:(void (^)(BOOL))completion {
    PMNativeOSProgram *program = _program;
    if (![self ready] || index >= (NSUInteger)program.page->unlockAnimationCount || !gameWindow()) return NO;
    const PMOSUnlockAnimation spec = program.page->unlockAnimations[index];
    NSString *songID = program.order[spec.song-1];
    NSDictionary *fields = [program unlockFieldsForSong:spec.song];
    NSInteger chapter = spec.style == PMOSUnlockMod ? 0 : 5 + spec.style-PMOSUnlockC5;
    NSString *reference = @(spec.src);
    if (!reference.length) reference = chapter >= 8 ? pmc89unlock::stockMovieReference((int)chapter) :
        [PMStockUnlockInfoView stockMovieReferenceForChapter:chapter];
    if (!reference.length) return NO;
    _intro = YES;
    __weak PMNativeOSActions *weak = self;
    void (^ended)(BOOL) = ^(BOOL ok){
        PMNativeOSActions *owner=weak;
        if (![owner isCurrent] || !owner->_intro) return;
        owner->_ownsMedia=NO;
        if (!ok || !spec.once) { owner->_intro=NO; completion(ok); return; }
        [program markUnlockSeen:index completion:^(BOOL saved){
            PMNativeOSActions *active=weak;
            if (![active isCurrent] || !active->_intro) return;
            active->_intro=NO; completion(saved);
        }];
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{@autoreleasepool {
        NSString *path = [reference hasPrefix:@"@stock/"] ? PMResolveStockIntro(reference) :
            PMOSArtPath([PMContentStore.shared asset:program.chapter],reference);
        NSURL *url=path ? [NSURL fileURLWithPath:path] : nil;
        AVURLAsset *asset=url ? [AVURLAsset URLAssetWithURL:url options:nil] : nil;
        double seconds=asset ? CMTimeGetSeconds(asset.duration) : 0;
        BOOL usable=std::isfinite(seconds) && seconds>0 && [asset tracksWithMediaType:AVMediaTypeVideo].count;
        double end=spec.duration>0 ? std::min(seconds,spec.duration) : seconds;
        dispatch_async(dispatch_get_main_queue(), ^{
            PMNativeOSActions *owner=weak;
            if (![owner isCurrent] || !owner->_intro) return;
            if (!usable || (spec.hasInfoAt && spec.infoAt>=end) || (spec.hasInfoUntil && spec.infoUntil>end+.001)) { ended(NO); return; }
            void (^play)(PMStockUnlockInfoView *)=^(PMStockUnlockInfoView *stock){
                PMNativeOSActions *active=weak;
                if (![active isCurrent] || !active->_intro) return;
                if ((chapter && !stock) || !gameWindow()) { ended(NO); return; }
                active->_ownsMedia=pmunlock::playChapterStoryMedia(path,nil,fields[@"title"],ended,true);
                if (!active->_ownsMedia) { ended(NO); return; }
                UIView *overlay=stock;
                if (!stock) {
                    overlay=[UIView new];
                    UILabel *label=[UILabel new]; label.translatesAutoresizingMaskIntoConstraints=NO;
                    label.numberOfLines=0; label.textAlignment=NSTextAlignmentCenter;
                    label.textColor=UIColor.whiteColor; label.backgroundColor=[UIColor colorWithWhite:0 alpha:.65];
                    label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
                    label.text=[@[fields[@"title"],fields[@"artist"]] componentsJoinedByString:@"\n"];
                    [overlay addSubview:label];
                    [NSLayoutConstraint activateConstraints:@[[label.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
                        [label.bottomAnchor constraintEqualToAnchor:overlay.safeAreaLayoutGuide.bottomAnchor constant:-32],
                        [label.widthAnchor constraintEqualToAnchor:overlay.widthAnchor multiplier:.75]]];
                }
                PMConfigureUnlockTimeline(overlay,end,^(double t){
                    if(stock)[stock setPresentationSeconds:t];
                    else overlay.hidden=t<std::max(0.,spec.infoAt) || (spec.hasInfoUntil && t>=spec.infoUntil);
                });
            };
            if (!chapter) { play(nil); return; }
            if (chapter>=8) { pmc89unlock::prepareInfo((int)chapter,reference,end,songID,fields,spec.infoAt,spec.infoUntil,play);return; }
            const auto *layout=pmstock::layout(chapter);
            double until=spec.hasInfoUntil ? spec.infoUntil : std::min(end,layout->end);
            if(spec.hasInfoAt && until<=spec.infoAt)until=end;
            double from=spec.hasInfoAt ? spec.infoAt : (layout->firstAlpha<until ? layout->firstAlpha : 0);
            [PMStockUnlockInfoView prepareChapter:chapter songID:songID fields:fields infoShowSeconds:from infoHideSeconds:until completion:play];
        });
    }});
    return YES;
}
