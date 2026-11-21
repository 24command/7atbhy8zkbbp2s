#import "PMStoryCueRun.h"
#import "PMChapterArt.h"
#import "../Core/PMChapterVM.h"
#import <ImageIO/ImageIO.h>
#import <UIKit/UIKit.h>

namespace {
// Recheck the media path on open: files can change between parse and playback.
CGImageSourceRef openStill(NSString *chapterDir, NSString *name) {
    if (![name isEqual:name.lastPathComponent]) return nullptr;
    NSString *path = PMOSArtPath(chapterDir, name);
    if (!path || [path.pathExtension.lowercaseString isEqual:@"mp4"]) return nullptr;
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if (![attrs[NSFileType] isEqual:NSFileTypeRegular]) return nullptr;
    return CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],
        (__bridge CFDictionaryRef)@{(NSString *)kCGImageSourceShouldCache:@NO});
}

bool preflightStill(NSString *chapterDir, NSString *name) {
    CGImageSourceRef source = openStill(chapterDir, name);
    if (!source) return false;
    NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, nullptr));
    CFRelease(source);
    return [props[(NSString *)kCGImagePropertyPixelWidth] integerValue] > 0 &&
           [props[(NSString *)kCGImagePropertyPixelHeight] integerValue] > 0;
}

UIImage *loadStill(NSString *chapterDir, NSString *name) {
    CGImageSourceRef source = openStill(chapterDir, name);
    if (!source) return nil;
    NSDictionary *options = @{(NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
                              (NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,
                              (NSString *)kCGImageSourceShouldCacheImmediately:@YES,
                              (NSString *)kCGImageSourceThumbnailMaxPixelSize:@768};
    CGImageRef bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!bitmap) return nil;
    UIImage *image = [UIImage imageWithCGImage:bitmap];
    CGImageRelease(bitmap);
    return image;
}

}

@interface PMPreparedStoryCues : NSObject
@property(nonatomic, readonly, copy) NSArray<NSDictionary *> *rows;
@property(nonatomic, readonly, copy) NSString *chapterDir;
- (instancetype)initWithCues:(NSArray<NSDictionary *> *)cues directory:(NSString *)directory;
- (pmstory::Frame)frameAt:(double)t;
@end

@implementation PMPreparedStoryCues {
    pmstory::Timeline _timeline;
}
- (instancetype)initWithCues:(NSArray<NSDictionary *> *)cues directory:(NSString *)directory {
    if (!(self = [super init])) return nil;
    _chapterDir = [directory copy];
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:cues.count];
    // Map each filename to its first payload index (-1 for a failed preflight).
    NSMutableDictionary<NSString *, NSNumber *> *images = [NSMutableDictionary dictionary];
    for (NSDictionary *row in cues) { @autoreleasepool {
        if (![row isKindOfClass:NSDictionary.class]) continue;
        NSNumber *at = row[@"at"], *duration = row[@"duration"], *gate = row[@"blockPause"];
        if (![at isKindOfClass:NSNumber.class] || ![duration isKindOfClass:NSNumber.class]) continue;
        double start = at.doubleValue, length = duration.doubleValue;
        double end = start + length;
        if (!(start >= 0 && end > start && std::isfinite(end))) continue;
        NSString *text = row[@"text"], *src = row[@"src"];
        NSMutableDictionary *payload = [NSMutableDictionary dictionary];
        if ([text isKindOfClass:NSString.class] && text.length) payload[@"text"] = [text copy];
        int image = -1;
        if ([src isKindOfClass:NSString.class] && src.length && _chapterDir.length) {
            NSNumber *index = images[src];
            if (!index) {
                if (preflightStill(_chapterDir, src)) {
                    image = (int)rows.count;
                    payload[@"src"] = [src copy];
                }
                images[src] = @(image);
            } else image = index.intValue;
        }
        bool block = [gate isKindOfClass:NSNumber.class] && gate.boolValue;
        bool hasText = payload[@"text"] != nil;
        if ((hasText || image >= 0 || block) && _timeline.add(start, length, hasText, image >= 0, block, image))
            [rows addObject:[payload copy]];
    }}
    if (!rows.count) return nil;
    _timeline.prepareLookahead();
    _rows = [rows copy];
    return self;
}
- (pmstory::Frame)frameAt:(double)t { return _timeline.sample(t); }
@end

PMPreparedStoryCues *PMStoryCuePrepare(NSArray<NSDictionary *> *cues, NSString *chapterDir) {
    if (![cues isKindOfClass:NSArray.class] || !cues.count || cues.count > PMOSMaxChallengeCues) return nil;
    return [[PMPreparedStoryCues alloc] initWithCues:cues directory:chapterDir];
}

namespace {
PMPreparedStoryCues *staged, *launch, *playing;
UIView *overlay;
UIImageView *picture;
UILabel *caption;
pmstory::Frame shown;

// Main-thread state. Across seeks and relaunches there is at most one outstanding
// decode (including its delivery block), and only two wanted cache entries.
NSUInteger armVersion, trackVersion;
bool decoding;
int current = -1, upcoming = -1;
NSMutableDictionary<NSNumber *, UIImage *> *cache;
NSMutableIndexSet *failed;

void requestStill() {
    if (decoding || !playing) return;
    for (int index : {current, upcoming}) {
        if (index < 0 || cache[@(index)] || [failed containsIndex:index]) continue;
        NSString *name = playing.rows[index][@"src"], *directory = playing.chapterDir;
        NSUInteger version = trackVersion;
        decoding = true;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ @autoreleasepool {
            UIImage *image = loadStill(directory, name);
            dispatch_async(dispatch_get_main_queue(), ^{
                decoding = false;
                if (version == trackVersion) {
                    if (!image) [failed addIndex:index];
                    else if (index == current || index == upcoming) cache[@(index)] = image;
                }
                requestStill();
            });
        }});
        return;
    }
}

void stageWindow(pmstory::Frame frame) {
    if (current == frame.image && upcoming == frame.nextImage) return;
    current = frame.image;
    upcoming = frame.nextImage;
    for (NSNumber *key in cache.allKeys) {
        if (key.intValue != current && key.intValue != upcoming) [cache removeObjectForKey:key];
    }
    requestStill();
}

UIView *gameView() {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.hidden && window.windowLevel == UIWindowLevelNormal && window.rootViewController.viewIfLoaded.window == window)
                return window.rootViewController.view;
        }
    }
    return nil;
}

void attach(UIView *host) {
    overlay = [[UIView alloc] initWithFrame:host.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.userInteractionEnabled = NO;
    picture = [UIImageView new];
    picture.contentMode = UIViewContentModeScaleAspectFit;
    caption = [UILabel new];
    caption.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    caption.textColor = UIColor.whiteColor;
    caption.backgroundColor = [UIColor colorWithWhite:0 alpha:.72];
    caption.textAlignment = NSTextAlignmentCenter;
    caption.numberOfLines = 0;
    picture.translatesAutoresizingMaskIntoConstraints = NO;
    caption.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:overlay];
    [overlay addSubview:picture];
    [overlay addSubview:caption];
    UILayoutGuide *safe = overlay.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [picture.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [picture.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [picture.widthAnchor constraintEqualToAnchor:safe.widthAnchor multiplier:.8],
        [picture.heightAnchor constraintEqualToAnchor:safe.heightAnchor multiplier:.65],
        [caption.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [caption.widthAnchor constraintEqualToAnchor:safe.widthAnchor multiplier:.8],
        [caption.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
        [caption.heightAnchor constraintLessThanOrEqualToAnchor:safe.heightAnchor]
    ]];
}
}

void PMStoryCueArm(PMPreparedStoryCues *prepared) {
    NSCParameterAssert(NSThread.isMainThread);
    staged = prepared;
    NSUInteger version = ++armVersion;
    if (prepared) dispatch_async(dispatch_get_main_queue(), ^{ if (armVersion == version) staged = nil; });
}

namespace pmstory {
void captureLaunch() { launch = staged; staged = nil; }
void cancelLaunch() { staged = nil; launch = nil; }
bool beginExactTrack() {
    endTrack();
    playing = launch;
    cancelLaunch();
    if (!playing) return false;
    cache = [NSMutableDictionary dictionaryWithCapacity:2];
    failed = [NSMutableIndexSet indexSet];
    stageWindow([playing frameAt:0]);
    return true;
}
void endTrack() {
    ++trackVersion;
    playing = nil;
    cache = nil;
    failed = nil;
    current = upcoming = -1;
    picture.image = nil;
    [overlay removeFromSuperview];
    overlay = nil; caption = nil; picture = nil; shown = {};
}
bool blocksPause(double t) { return playing && [playing frameAt:t].block; }
void present(double t) {
    if (!playing) return;
    Frame frame = [playing frameAt:t];
    if (std::isfinite(t)) stageWindow(frame);
    UIImage *image = frame.image < 0 ? nil : cache[@(frame.image)];
    if (frame.text == shown.text && image == picture.image) return;
    if (!overlay) {
        UIView *host = gameView();
        if (!host) return;
        attach(host);
    }
    caption.text = frame.text < 0 ? nil : playing.rows[frame.text][@"text"];
    picture.image = image;
    caption.hidden = frame.text < 0;
    overlay.hidden = caption.hidden && !image;
    shown = frame;
}
}
