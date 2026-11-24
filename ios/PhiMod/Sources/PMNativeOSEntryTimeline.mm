// Portable geometry/sampling is intentionally outside __OBJC__: the focused C++
// tests include this implementation without linking UIKit or the native OS map.
#include "PMNativeOSMap.hpp"
#include <cstddef>
#include <memory>
#include <vector>

namespace pmentrytimeline {
constexpr size_t decodedBudget = 32u * 1024u * 1024u;
constexpr size_t sourceFileBudget = 32u * 1024u * 1024u;
constexpr size_t sourcePixelBudget = 16u * 1024u * 1024u;
struct Rect { double x, y, w, h; };
inline Rect fit(double width, double height, double aspect) {
    if (width <= 0 || height <= 0) return {0, 0, 0, 0};
    if (aspect <= 0) return {0, 0, width, height};
    double w = std::min(width, height * aspect), h = w / aspect;
    return {(width - w) / 2, (height - h) / 2, w, h};
}
inline Rect rect(const PMOSNode &n, double parentWidth, double parentHeight) {
    // UIKit is top-left based; do not apply Unity's Y-axis inversion here.
    return {n.x * parentWidth, n.y * parentHeight, n.w * parentWidth, n.h * parentHeight};
}
inline double clock(double seconds, double duration) {
    if (std::isnan(seconds) || seconds <= 0) return 0;
    // opacity() uses half-open intervals. Keep duration-ending nodes present at
    // the host's exact end tick, while preserving intentional authored fades.
    return std::min(seconds, std::nextafter(duration, 0.));
}
struct State {
    bool active = false;
    float local = 0, inherited = 0;
    double shownSince = 0;
    pmnativeosmap::layout::Pose pose;
};
inline State sample(const PMOSNode &n, double t, const State *parent) {
    namespace layout = pmnativeosmap::layout;
    auto visibility = layout::sample(layout::opacity(t, n.start, n.duration, n.fade),
        true, !n.hidden && !n.songSuppressed, !parent || parent->active,
        parent ? parent->inherited : 1.f);
    State result;
    result.active = visibility.active;
    result.local = visibility.local;
    result.inherited = visibility.inherited;
    result.shownSince = std::max(n.start, parent ? parent->shownSince : 0.);
    if (result.active) result.pose = layout::motion(n.motion, t - result.shownSince, 0);
    return result;
}
inline unsigned decodeEdge(double screenPixels, size_t uniquePaths) {
    if (!uniquePaths || uniquePaths > PMOSMaxNodes) return 0;
    double edge = std::min(2048., std::floor(std::sqrt(double(decodedBudget / uniquePaths) / 4.)));
    if (std::isfinite(screenPixels) && screenPixels > 0) edge = std::min(edge, std::max(16., screenPixels));
    // 16-pixel multiples account for our 64-byte bitmap row alignment.
    return unsigned(edge) / 16 * 16;
}
inline bool imageBytes(size_t width, size_t height, size_t remaining, size_t &row, size_t &bytes) {
    if (!width || !height || width > 2048 || height > 2048) return false;
    row = (width * 4 + 63) & ~size_t(63);
    bytes = row * height;
    return bytes <= remaining;
}
inline bool validNode(const PMOSNode &n, int index, const std::vector<PMOSNode> &nodes, int screen) {
    if (n.parent < -1 || n.parent >= index ||
        (n.parent >= 0 && nodes[n.parent].screen != screen)) return false;
    if ((n.kind != PMOSFrame && n.kind != PMOSImage) || n.handler || n.open || n.dest >= 0 ||
        n.challenge || n.dropTarget[0] || n.alphaHit || n.loop || n.to[0] || n.tapFace[0] ||
        n.motion.tapTime != 0 || n.motion.tapFlash != 0) return false;
    for (double v : {n.x, n.y, n.w, n.h, n.start, n.duration, n.fade, n.motion.enter,
                     n.motion.bob, n.motion.bobPeriod, n.motion.tapScale})
        if (!std::isfinite(v)) return false;
    return n.w > 0 && n.h > 0 && n.start >= 0 && n.duration >= 0 && n.fade >= 0 &&
        std::isfinite(n.start + n.duration) && n.motion.enter >= 0 && n.motion.bob >= 0 &&
        n.motion.bobPeriod >= 0;
}
}

#ifdef __OBJC__
#import "PMNativeOSEntryTimeline.h"
#import "PMNativeOSProgram.h"
#import <ImageIO/ImageIO.h>
#import <dispatch/dispatch.h>

namespace {
NSError *entryError(NSString *message) {
    return [NSError errorWithDomain:@"PMNativeOSEntryTimeline" code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}
dispatch_queue_t decodeQueue() {
    // One source decoder at a time, even if two transitions prepare concurrently.
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.phimod.entry-timeline.decode", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}
struct Plan {
    std::vector<PMOSNode> nodes; // Original indices, never a compacted screen list.
    int screen;
    double duration, aspect;
    unsigned edge;
    NSDictionary<NSNumber *, NSString *> *paths;
};
}

// Own a fully materialized CG bitmap, not an ImageIO source/provider whose first
// UIKit draw could trigger file decoding on the main thread.
@interface PMEntryTimelineBitmap : NSObject
@property(nonatomic, readonly) CGImageRef image;
- (instancetype)initWithImage:(CGImageRef)image;
@end
@implementation PMEntryTimelineBitmap
- (instancetype)initWithImage:(CGImageRef)image {
    if ((self = [super init])) _image = CGImageRetain(image);
    return self;
}
- (void)dealloc { CGImageRelease(_image); }
@end

namespace {
PMEntryTimelineBitmap *decodeStill(NSString *path, unsigned edge, size_t &remaining, NSError **error) {
    NSCAssert(!NSThread.isMainThread, @"Entry artwork must decode off the main thread");
    auto fail = [&](NSString *reason) -> PMEntryTimelineBitmap * {
        if (error) *error = entryError([NSString stringWithFormat:@"Entry image %@: %@", path.lastPathComponent, reason]);
        return nil;
    };
    if (![@[@"png", @"jpg", @"jpeg", @"webp"] containsObject:path.pathExtension.lowercaseString])
        return fail(@"only PNG/JPG/WebP still images are supported");
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    unsigned long long fileBytes = [attributes[NSFileSize] unsignedLongLongValue];
    if (![attributes[NSFileType] isEqual:NSFileTypeRegular] || !fileBytes ||
        fileBytes > pmentrytimeline::sourceFileBudget) return fail(@"missing file or source exceeds 32 MiB");
    NSDictionary *options = @{(__bridge NSString *)kCGImageSourceShouldCache: @NO};
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],
                                                       (__bridge CFDictionaryRef)options);
    if (!source) return fail(@"unreadable image");
    NSString *type = (__bridge NSString *)CGImageSourceGetType(source);
    if (![@[@"public.png", @"public.jpeg", @"org.webmproject.webp"] containsObject:type ?: @""] ||
        CGImageSourceGetCount(source) != 1) {
        CFRelease(source);
        return fail(@"animated or unsupported image content");
    }
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, nullptr));
    double width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue];
    double height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue];
    if (!std::isfinite(width) || !std::isfinite(height) || width < 1 || height < 1 ||
        width > 16384 || height > 16384 || width * height > pmentrytimeline::sourcePixelBudget) {
        CFRelease(source);
        return fail(@"source exceeds the 16-megapixel decode limit");
    }
    NSDictionary *thumbnailOptions = @{
        (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES,
        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(edge)
    };
    CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)thumbnailOptions);
    CFRelease(source);
    if (!thumbnail) return fail(@"thumbnail decode failed");
    size_t row = 0, bytes = 0, w = CGImageGetWidth(thumbnail), h = CGImageGetHeight(thumbnail);
    if (!pmentrytimeline::imageBytes(w, h, remaining, row, bytes)) {
        CGImageRelease(thumbnail);
        return fail(@"decoded artwork exceeds the 32 MiB budget");
    }
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    if (!color) { CGImageRelease(thumbnail); return fail(@"color-space allocation failed"); }
    CGContextRef bitmap = CGBitmapContextCreate(nullptr, w, h, 8, row, color,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(color);
    if (!bitmap) { CGImageRelease(thumbnail); return fail(@"bitmap allocation failed"); }
    CGContextSetBlendMode(bitmap, kCGBlendModeCopy);
    CGContextDrawImage(bitmap, CGRectMake(0, 0, w, h), thumbnail);
    CGImageRelease(thumbnail);
    CGImageRef decoded = CGBitmapContextCreateImage(bitmap);
    CGContextRelease(bitmap);
    if (!decoded) return fail(@"bitmap materialization failed");
    PMEntryTimelineBitmap *result = [[PMEntryTimelineBitmap alloc] initWithImage:decoded];
    CGImageRelease(decoded);
    if (!result) return fail(@"bitmap ownership allocation failed");
    remaining -= bytes;
    return result;
}
}

@interface PMEntryTimelineNodeView : UIView
- (instancetype)initWithNode:(const PMOSNode &)node image:(UIImage *)image;
@end
@implementation PMEntryTimelineNodeView {
    UIImageView *_picture;
    UILabel *_label;
}
- (instancetype)initWithNode:(const PMOSNode &)node image:(UIImage *)image {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.userInteractionEnabled = NO;
        self.isAccessibilityElement = NO;
        self.opaque = NO;
        self.clipsToBounds = YES;
        self.backgroundColor = [UIColor colorWithRed:((node.rgba >> 24) & 255) / 255.
                                              green:((node.rgba >> 16) & 255) / 255.
                                               blue:((node.rgba >> 8) & 255) / 255.
                                              alpha:(node.rgba & 255) / 255.];
        if (image) {
            _picture = [[UIImageView alloc] initWithImage:image];
            _picture.userInteractionEnabled = NO;
            _picture.contentMode = node.fill ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
            [self addSubview:_picture];
        }
        if (node.label[0]) {
            _label = [[UILabel alloc] initWithFrame:CGRectZero];
            _label.userInteractionEnabled = NO;
            _label.text = [NSString stringWithUTF8String:node.label];
            _label.textColor = UIColor.whiteColor;
            _label.backgroundColor = UIColor.clearColor;
            _label.textAlignment = NSTextAlignmentCenter;
            _label.font = [UIFont systemFontOfSize:24];
            _label.numberOfLines = 0;
            _label.adjustsFontSizeToFitWidth = YES;
            _label.minimumScaleFactor = 14. / 24.;
            [self addSubview:_label];
        }
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    // Only the wrapper is transformed; never assign its frame after sampling.
    _picture.frame = self.bounds;
    _label.frame = self.bounds;
}
@end

@interface PMEntryTimelineRootView : UIView
- (instancetype)initWithPlan:(const Plan &)plan images:(NSDictionary<NSString *, UIImage *> *)images;
- (void)sample:(double)seconds;
@end
@implementation PMEntryTimelineRootView {
    UIView *_canvas;
    std::vector<PMOSNode> _nodes;
    std::vector<pmentrytimeline::State> _states;
    NSMutableDictionary<NSNumber *, PMEntryTimelineNodeView *> *_nodeViews;
    int _screen;
    double _duration, _aspect;
}
- (instancetype)initWithPlan:(const Plan &)plan images:(NSDictionary<NSString *, UIImage *> *)images {
    if ((self = [super initWithFrame:CGRectZero])) {
        _nodes = plan.nodes;
        _states.resize(_nodes.size());
        _screen = plan.screen; _duration = plan.duration; _aspect = plan.aspect;
        self.backgroundColor = UIColor.blackColor;
        self.opaque = YES;
        self.clipsToBounds = YES;
        self.userInteractionEnabled = NO;
        self.accessibilityElementsHidden = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _canvas = [[UIView alloc] initWithFrame:CGRectZero];
        _canvas.userInteractionEnabled = NO;
        _canvas.opaque = NO;
        _canvas.backgroundColor = UIColor.clearColor;
        _canvas.clipsToBounds = YES;
        [self addSubview:_canvas];
        _nodeViews = [NSMutableDictionary new];
        for (size_t i = 0; i < _nodes.size(); ++i) {
            const PMOSNode &node = _nodes[i];
            if (node.screen != _screen) continue;
            NSString *path = plan.paths[@(i)];
            PMEntryTimelineNodeView *view = [[PMEntryTimelineNodeView alloc]
                initWithNode:node image:path ? images[path] : nil];
            UIView *parent = node.parent < 0 ? _canvas : _nodeViews[@(node.parent)];
            [parent addSubview:view];
            _nodeViews[@(i)] = view;
        }
        [self sample:0];
    }
    return self;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return nil; }
- (void)applyPose:(size_t)index {
    UIView *view = _nodeViews[@(index)];
    const auto &pose = _states[index].pose;
    // Positive Unity lift is upwards in top-left UIKit coordinates. Translation
    // is measured in unscaled node heights, not multiplied by the enter scale.
    view.transform = CGAffineTransformMake(pose.scale, 0, 0, pose.scale, 0, -pose.lift * view.bounds.size.height);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [UIView performWithoutAnimation:^{
        auto canvas = pmentrytimeline::fit(self.bounds.size.width, self.bounds.size.height, self->_aspect);
        self->_canvas.bounds = CGRectMake(0, 0, canvas.w, canvas.h);
        self->_canvas.center = CGPointMake(self.bounds.origin.x + canvas.x + canvas.w / 2,
                                          self.bounds.origin.y + canvas.y + canvas.h / 2);
        for (size_t i = 0; i < self->_nodes.size(); ++i) {
            const PMOSNode &node = self->_nodes[i];
            if (node.screen != self->_screen) continue;
            UIView *view = self->_nodeViews[@(i)];
            CGRect parent = view.superview.bounds;
            auto r = pmentrytimeline::rect(node, parent.size.width, parent.size.height);
            view.bounds = CGRectMake(0, 0, r.w, r.h);
            view.center = CGPointMake(parent.origin.x + r.x + r.w / 2, parent.origin.y + r.y + r.h / 2);
            [self applyPose:i];
        }
    }];
}
- (void)sample:(double)seconds {
    NSAssert(NSThread.isMainThread, @"Entry timelines must be sampled on the main thread");
    double time = pmentrytimeline::clock(seconds, _duration);
    [UIView performWithoutAnimation:^{
        for (size_t i = 0; i < self->_nodes.size(); ++i) {
            const PMOSNode &node = self->_nodes[i];
            if (node.screen != self->_screen) continue;
            auto state = pmentrytimeline::sample(node, time, node.parent < 0 ? nullptr : &self->_states[node.parent]);
            self->_states[i] = state;
            UIView *view = self->_nodeViews[@(i)];
            view.hidden = !state.active;
            view.alpha = state.local; // UIKit composes parent alpha exactly once.
            [self applyPose:i];
        }
    }];
}
@end

@interface PMNativeOSEntryTimeline ()
- (instancetype)initWithRoot:(PMEntryTimelineRootView *)root;
@end
@implementation PMNativeOSEntryTimeline {
    PMEntryTimelineRootView *_root;
}
- (instancetype)initWithRoot:(PMEntryTimelineRootView *)root {
    if ((self = [super init])) _root = root;
    return self;
}
- (UIView *)view { return _root; }
- (void)sample:(double)seconds { [_root sample:seconds]; }
+ (void)prepareWithProgram:(PMNativeOSProgram *)program completion:(PMNativeOSEntryTimelineCompletion)completion {
    if (!completion) return;
    // Snapshot immutable program data and screen metrics on main; even failure
    // returns asynchronously. No image is read or decoded in this block.
    dispatch_async(dispatch_get_main_queue(), ^{
        const PMOSPage *page = program.page;
        if (program.transitionError.length) { completion(nil, entryError(program.transitionError)); return; }
        if (!page || page->entryTransition.kind != PMOSEntryTransitionTimeline ||
            page->entryTransition.screen < 0 || page->entryTransition.screen >= page->screens ||
            page->nodes < 1 || page->nodes > PMOSMaxNodes ||
            !std::isfinite(page->entryTransition.duration) || page->entryTransition.duration <= 0 ||
            !std::isfinite(page->aspect) || page->aspect < 0 || program.nodes.count != size_t(page->nodes)) {
            completion(nil, entryError(@"Invalid entry timeline declaration")); return;
        }
        auto plan = std::make_shared<Plan>();
        plan->nodes.assign(page->elements, page->elements + page->nodes);
        plan->screen = page->entryTransition.screen;
        plan->duration = page->entryTransition.duration;
        plan->aspect = page->aspect;
        NSMutableDictionary<NSNumber *, NSString *> *paths = [NSMutableDictionary new];
        NSUInteger selected = 0;
        for (int i = 0; i < page->nodes; ++i) {
            const PMOSNode &node = plan->nodes[i];
            if (node.screen != plan->screen) continue;
            ++selected;
            if (!pmentrytimeline::validNode(node, i, plan->nodes, plan->screen)) {
                completion(nil, entryError(@"Entry timeline contains invalid or interactive nodes")); return;
            }
            if (node.songSuppressed) continue;
            id path = program.nodes[i][@"path"];
            if (path && (![path isKindOfClass:NSString.class] || ![path length])) {
                completion(nil, entryError(@"Invalid resolved entry image path")); return;
            }
            if (!path && (node.src[0] || node.cover)) {
                completion(nil, entryError(@"Missing resolved entry image")); return;
            }
            if (path) paths[@(i)] = [path stringByStandardizingPath];
        }
        if (!selected) { completion(nil, entryError(@"Entry timeline screen is empty")); return; }
        plan->paths = [paths copy];
        NSSet<NSString *> *uniquePaths = [NSSet setWithArray:paths.allValues];
        CGSize size = UIScreen.mainScreen.bounds.size;
        plan->edge = pmentrytimeline::decodeEdge(std::max(size.width, size.height) * UIScreen.mainScreen.scale, uniquePaths.count);
        dispatch_async(decodeQueue(), ^{
            @autoreleasepool {
                NSMutableDictionary<NSString *, PMEntryTimelineBitmap *> *bitmaps = [NSMutableDictionary new];
                NSError *error = nil;
                size_t remaining = pmentrytimeline::decodedBudget;
                for (NSString *path in uniquePaths) {
                    @autoreleasepool {
                        PMEntryTimelineBitmap *bitmap = decodeStill(path, plan->edge, remaining, &error);
                        if (!bitmap) {
                            if (!error) error = entryError(@"Entry image preparation failed");
                            break;
                        }
                        bitmaps[path] = bitmap;
                    }
                }
                if (error) {
                    [bitmaps removeAllObjects];
                    dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); });
                    return;
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSMutableDictionary<NSString *, UIImage *> *images = [NSMutableDictionary new];
                    for (NSString *path in bitmaps) {
                        UIImage *image = [UIImage imageWithCGImage:bitmaps[path].image scale:1 orientation:UIImageOrientationUp];
                        if (!image) { completion(nil, entryError(@"Entry image wrapping failed")); return; }
                        images[path] = image;
                    }
                    PMEntryTimelineRootView *root = [[PMEntryTimelineRootView alloc] initWithPlan:*plan images:images];
                    completion([[PMNativeOSEntryTimeline alloc] initWithRoot:root], nil);
                });
            }
        });
    });
}
@end
#endif // __OBJC__
