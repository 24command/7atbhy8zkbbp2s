#import "PMSongInterruption.h"
#import "PMChapterArt.h"
#import "PMCoverImage.h"
#import "PMDiagnostics.h"
#include "PMSongInterruptionWindow.hpp"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include "PMSongInterruptionState.hpp"
#include <dlfcn.h>
#include <fcntl.h>
#include <mach/mach_time.h>
#include <sys/stat.h>
#include <unistd.h>
#include <cerrno>
#include <climits>
#include <memory>

static NSError *PMInterruptionError(NSString *message) {
    return [NSError errorWithDomain:@"PhiMod.SongInterruption" code:1
                          userInfo:@{NSLocalizedDescriptionKey:message}];
}
static BOOL PMInterruptionText(id value, BOOL empty = NO) {
    if (![value isKindOfClass:NSString.class] || (!empty && ![value length])) return NO;
    NSString *text = value;
    if ([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 16384) return NO;
    for (NSUInteger i = 0; i < text.length; ++i) if ([text characterAtIndex:i] == 0) return NO;
    return [text canBeConvertedToEncoding:NSUTF8StringEncoding];
}
static BOOL PMInterruptionNumber(id value) {
    return [value isKindOfClass:NSNumber.class] &&
           CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() &&
           std::isfinite([value doubleValue]);
}
namespace {
struct PMInterruptionFD {
    int value;
    explicit PMInterruptionFD(int fd):value(fd) {}
    ~PMInterruptionFD() { if (value >= 0) close(value); }
    PMInterruptionFD(const PMInterruptionFD&) = delete;
    PMInterruptionFD& operator=(const PMInterruptionFD&) = delete;
};
}
static NSData *PMReadInterruptionImage(NSString *chapter, NSString *src, NSError **error) {
    // Keep the shared whitelist; descriptor-relative opens also close its symlink
    // check/open race for chapter, os-media and the final file. No arbitrary URL.
    if (!PMOSLocalMediaPath(chapter, src, @[@"png", @"jpg", @"jpeg", @"webp"])) {
        if (error) *error = PMInterruptionError(@"Invalid interruption image basename");
        return nil;
    }
    PMInterruptionFD root(open(chapter.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
    PMInterruptionFD media(root.value < 0 ? -1 : openat(root.value, "os-media", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
    PMInterruptionFD file(media.value < 0 ? -1 : openat(media.value, src.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC));
    struct stat before = {}, after = {};
    constexpr off_t limit = 32 * 1024 * 1024;
    if (file.value < 0 || fstat(file.value, &before) || !S_ISREG(before.st_mode) ||
        before.st_size <= 0 || before.st_size > limit) {
        if (error) *error = PMInterruptionError(@"Interruption image must be a regular file of 1 byte to 32 MiB");
        return nil;
    }
    NSMutableData *bytes = [NSMutableData dataWithLength:(NSUInteger)before.st_size];
    size_t offset = 0;
    while (offset < bytes.length) {
        ssize_t count = read(file.value, (char *)bytes.mutableBytes + offset, bytes.length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        offset += (size_t)count;
    }
    char extra;
    ssize_t tail;
    do { tail = read(file.value, &extra, 1); } while (tail < 0 && errno == EINTR);
    if (offset != bytes.length || tail != 0 || fstat(file.value, &after) ||
        before.st_size != after.st_size || before.st_mtime != after.st_mtime) {
        if (error) *error = PMInterruptionError(@"Interruption image changed or could not be read");
        return nil;
    }
    return bytes;
}

@interface PMPreparedSongInterruption ()
@property(nonatomic, strong) UIImage *image;
- (instancetype)initWithConfig:(NSDictionary *)config image:(UIImage *)image;
@end
@implementation PMPreparedSongInterruption
- (instancetype)initWithConfig:(NSDictionary *)config image:(UIImage *)image {
    if ((self = [super init])) {
        _at = [config[@"at"] doubleValue];
        _delay = config[@"delay"] ? [config[@"delay"] doubleValue] : 2;
        _song = [config[@"song"] integerValue];
        _difficulty = [config[@"difficulty"] copy] ?: @"";
        _src = [config[@"src"] copy];
        _title = [config[@"title"] copy];
        _message = [config[@"message"] copy];
        _button = [config[@"button"] copy];
        _image = image;
    }
    return self;
}
@end

PMPreparedSongInterruption *PMPrepareSongInterruption(NSDictionary *config, NSString *chapterDir, NSError **error) {
    if (error) *error = nil;
    if (NSThread.isMainThread) {
        if (error) *error = PMInterruptionError(@"Prepare song interruption on the Program worker, not main");
        return nil;
    }
    @autoreleasepool { @try {
        if (![config isKindOfClass:NSDictionary.class] || !PMInterruptionText(chapterDir)) {
            if (error) *error = PMInterruptionError(@"Invalid interruption configuration or chapter directory");
            return nil;
        }
        // Copy strings/numbers before the prepared object crosses queues. Caller
        // must not mutate the input dictionary concurrently with this call.
        config = [[NSDictionary alloc] initWithDictionary:config copyItems:YES];
        double delay = config[@"delay"] ? [config[@"delay"] doubleValue] : 2;
        if (!PMInterruptionNumber(config[@"at"]) || [config[@"at"] doubleValue] < 0 ||
            (config[@"delay"] && !PMInterruptionNumber(config[@"delay"])) || delay < 0 || delay > 600 ||
            !PMInterruptionNumber(config[@"song"]) || [config[@"song"] doubleValue] < 1 ||
            [config[@"song"] doubleValue] > INT_MAX ||
            std::floor([config[@"song"] doubleValue]) != [config[@"song"] doubleValue] ||
            (config[@"difficulty"] && !PMInterruptionText(config[@"difficulty"], YES)) ||
            (config[@"action"] && ![config[@"action"] isEqual:@"quit"])) {
            if (error) *error = PMInterruptionError(@"Invalid interruption timing, song, difficulty or action");
            return nil;
        }
        for (NSString *key in @[@"src", @"title", @"message", @"button"]) {
            if (!PMInterruptionText(config[key])) {
                if (error) *error = PMInterruptionError([@"Invalid interruption text: " stringByAppendingString:key]);
                return nil;
            }
        }
        NSData *data = PMReadInterruptionImage(chapterDir, config[@"src"], error);
        if (!data) return nil;
        UIImage *image = PMDecodeCoverData(data, error);
        return image ? [[PMPreparedSongInterruption alloc] initWithConfig:config image:image] : nil;
    } @catch (NSException *exception) {
        if (error) *error = PMInterruptionError(exception.reason ?: @"Interruption preparation failed");
        return nil;
    }}
}

namespace {
struct PMInterruptionPayload {
    PMPreparedSongInterruption *prepared = nil;
    UIImage *cover = nil;
    CGFloat aspect = 0;
    BOOL (^guard)(void) = nil;
    void (^invalidated)(void) = nil;
};
using PMInterruptionState = pmsonginterruption::Owner<std::shared_ptr<PMInterruptionPayload>>;
using PMInterruptionTicket = PMInterruptionState::Ticket;
struct PMInterruptionHost {
    UIViewController *controller = nil;
    UIView *view = nil;
    UIWindow *window = nil;
};
static BOOL (^configuredGuard)(void);
static void (^configuredInvalidation)(void);

static UIView *unityViewIn(UIView *view) {
    // Only a verified Unity host is eligible, never an arbitrary key/modal window.
    if ([NSStringFromClass(view.class) hasPrefix:@"Unity"]) return view;
    for (UIView *child in view.subviews) if (UIView *found = unityViewIn(child)) return found;
    return nil;
}
static PMInterruptionHost gameHost() {
    using GetController = UIViewController *(*)(void);
    using GetView = UIView *(*)(void);
    static auto getController = reinterpret_cast<GetController>(dlsym(RTLD_DEFAULT, "UnityGetGLViewController"));
    static auto getView = reinterpret_cast<GetView>(dlsym(RTLD_DEFAULT, "UnityGetGLView"));
    UIViewController *controller = getController ? getController() : nil;
    UIView *view = getView ? getView() : controller.viewIfLoaded;
    if (view.window && controller.viewIfLoaded.window == view.window)
        return {controller, view, view.window};
    PMInterruptionHost result;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState == UISceneActivationStateUnattached) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || window.windowLevel != UIWindowLevelNormal) continue;
            UIView *unity = unityViewIn(window.rootViewController.viewIfLoaded);
            if (!unity) continue;
            if (result.window) return {}; // Ambiguous game scene: fail closed.
            result = {window.rootViewController, unity, window};
        }
    }
    if(!result.window){
        // Legacy UnityAppController has no UIScene/connectedScenes entry.
        for(UIWindow *window in UIApplication.sharedApplication.windows){
            if(window.windowScene || window.hidden || window.windowLevel!=UIWindowLevelNormal)continue;
            UIView *unity=unityViewIn(window.rootViewController.viewIfLoaded);
            if(!unity)continue;
            if(result.window)return {};
            result={window.rootViewController,unity,window};
        }
    }
    return result;
}
static double continuousSeconds() {
    static mach_timebase_info_data_t scale;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ mach_timebase_info(&scale); });
    // Unlike frame delta / active time, this includes device sleep and suspension.
    return (double)mach_continuous_time() * ((double)scale.numer / scale.denom) * 1e-9;
}
static BOOL activeWindow(UIWindow *window) {
    return pmsonginterruption::windowActive(window!=nil,window.hidden,
        UIApplication.sharedApplication.applicationState==UIApplicationStateActive,window.windowScene!=nil,
        window.windowScene.activationState==UISceneActivationStateForegroundActive);
}
static CGFloat windowAspect(UIWindow *window) {
    CGSize size = window.bounds.size;
    return size.width > 0 && size.height > 0 ? size.width / size.height : 0;
}
static UIImage *completeCover(const std::shared_ptr<PMInterruptionPayload>& payload, CGFloat aspect) {
    if (!payload || !std::isfinite(aspect) || aspect <= 0) return nil;
    if (!payload->cover || std::fabs(payload->aspect - aspect) > aspect * .00001) {
        NSError *error = nil;
        UIImage *image = PMCompleteCover(payload->prepared.image, aspect, &error);
        if (!image) return nil; // Never substitute a stock image or warp the source.
        payload->cover = image;
        payload->aspect = aspect;
    }
    return payload->cover;
}
}

@interface PMSongInterruptionController : UIViewController
@property(nonatomic, strong) UIImageView *imageView;
@property(nonatomic, weak) UIViewController *gameController;
@property(nonatomic, copy) void (^layoutChanged)(CGSize);
@end
@implementation PMSongInterruptionController
- (void)loadView {
    self.view = [[UIView alloc] initWithFrame:CGRectZero];
    self.imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    // PMCompleteCover has already composed the foreground without distortion.
    // Aspect-fill removes subpixel rounding slivers in its bounded bitmap only.
    self.imageView.contentMode = UIViewContentModeScaleAspectFill;
    self.imageView.clipsToBounds = YES;
    [self.view addSubview:self.imageView];
    self.view.accessibilityViewIsModal = YES;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.imageView.frame = self.view.bounds; // Full bounds, NOT safeAreaLayoutGuide.
    if (self.layoutChanged) self.layoutChanged(self.view.bounds.size);
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return self.gameController ? self.gameController.supportedInterfaceOrientations : UIInterfaceOrientationMaskAll;
}
- (BOOL)shouldAutorotate { return self.gameController ? self.gameController.shouldAutorotate : YES; }
@end

@interface PMSongInterruptionOwner : NSObject {
@public
    PMInterruptionState state;
}
@property(nonatomic, weak) UIWindow *gameWindow;
@property(nonatomic, weak) UIWindowScene *gameScene;
@property(nonatomic, weak) UIViewController *gameController;
@property(nonatomic, weak) UIViewController *gameRoot;
@property(nonatomic, weak) UIView *gameView;
@property(nonatomic, strong) UIWindow *imageWindow;
@property(nonatomic, strong) PMSongInterruptionController *imageController;
@property(nonatomic, strong) UIAlertController *alert;
@property(nonatomic, strong) CADisplayLink *clock;
@property(nonatomic, strong) NSMutableArray *observers;
@property(nonatomic, copy) void (^quit)(void);
- (void)clearUI;
- (void)invalidate:(PMInterruptionTicket)ticket;
- (BOOL)validHost:(PMInterruptionTicket)ticket;
- (void)observe:(PMInterruptionTicket)ticket;
- (void)step:(CADisplayLink *)clock;
- (void)close:(PMInterruptionTicket)ticket;
@end

static PMSongInterruptionOwner *interruptionOwner() {
    static PMSongInterruptionOwner *owner;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ owner = [PMSongInterruptionOwner new]; });
    return owner;
}
static void notifyInvalidation(const std::shared_ptr<PMInterruptionPayload>& payload) {
    if (!payload) return;
    void (^callback)(void) = payload->invalidated;
    payload->invalidated = nil; // Consume before invoking possibly reentrant code.
    if (callback) { @try { try { callback(); } catch (...) {} } @catch (NSException *exception) { (void)exception; } }
}
@implementation PMSongInterruptionOwner
- (void)clearUI {
    // Detach owner fields before UIKit can emit notifications/reenter. Cleanup of
    // an old window must never tear down a replacement installed by a callback.
    CADisplayLink *clock = self.clock;
    NSArray *observers = self.observers;
    UIWindow *window = self.imageWindow, *gameWindow = self.gameWindow;
    UIWindowScene *scene = self.gameScene;
    UIAlertController *alert = self.alert;
    self.imageController.layoutChanged = nil;
    self.clock = nil; self.observers = nil; self.quit = nil; self.alert = nil;
    self.imageWindow = nil; self.imageController = nil;
    self.gameWindow = nil; self.gameScene = nil; self.gameController = nil;
    self.gameRoot = nil; self.gameView = nil;
    [clock invalidate];
    for (id observer in observers) [NSNotificationCenter.defaultCenter removeObserver:observer];
    BOOL restoreKey = window.isKeyWindow;
    [alert dismissViewControllerAnimated:NO completion:nil];
    window.hidden = YES;
    window.rootViewController = nil;
    if (restoreKey && !self.imageWindow && gameWindow && !gameWindow.hidden && gameWindow.windowScene == scene)
        [gameWindow makeKeyWindow];
}
- (void)invalidate:(PMInterruptionTicket)ticket {
    if (!state.owns(ticket)) return;
    auto payload = state.payload();
    state.retirePlaying(); // Leave any independently armed NEXT launch alone.
    [self clearUI];
    notifyInvalidation(payload);
}
- (BOOL)validHost:(PMInterruptionTicket)ticket {
    if (!state.owns(ticket)) return NO;
    auto payload = state.payload();
    BOOL valid = YES;
    @try { try { if (payload->guard) valid = payload->guard(); } catch (...) { valid = NO; } }
    @catch (NSException *exception) { (void)exception; valid = NO; }
    if (!state.owns(ticket)) return NO; // Guard may synchronously End/Begin.
    if (self.gameWindow) {
        valid = valid && self.gameView && self.gameController && self.gameRoot &&
            self.gameView.window == self.gameWindow && !self.gameWindow.hidden &&
            self.gameController.viewIfLoaded.window == self.gameWindow &&
            self.gameWindow.rootViewController == self.gameRoot &&
            self.gameWindow.windowScene == self.gameScene &&
            self.gameScene.activationState != UISceneActivationStateUnattached;
    } else if (state.blocking()) valid = NO;
    if (!valid) [self invalidate:ticket];
    return valid && state.owns(ticket);
}
- (void)observe:(PMInterruptionTicket)ticket {
    self.observers = [NSMutableArray array];
    __weak PMSongInterruptionOwner *weak = self;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSString *name in @[UIApplicationWillResignActiveNotification, UIApplicationDidEnterBackgroundNotification,
                             UIApplicationDidBecomeActiveNotification, UISceneWillDeactivateNotification,
                             UISceneDidActivateNotification, UISceneDidDisconnectNotification,
                             UIWindowDidBecomeHiddenNotification]) {
        id observer = [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            PMSongInterruptionOwner *owner = weak;
            if (!owner || !owner->state.owns(ticket)) return;
            if (([note.name isEqual:UISceneDidDisconnectNotification] && note.object == owner.gameScene) ||
                ([note.name isEqual:UIWindowDidBecomeHiddenNotification] && note.object == owner.gameWindow)) {
                [owner invalidate:ticket]; return;
            }
            if (![owner validHost:ticket]) return;
            owner.clock.paused = !activeWindow(owner.gameWindow);
            // Activation never presents synchronously: wait for the next displayed
            // image frame. The continuous deadline itself is NOT paused or reset.
        }];
        [self.observers addObject:observer];
    }
}
- (void)step:(CADisplayLink *)clock {
    if (clock != self.clock) return;
    auto ticket = state.ticket();
    if (![self validHost:ticket]) return;
    BOOL active = activeWindow(self.gameWindow);
    if (!active) { self.clock.paused = YES; return; }
    if (!self.imageWindow || self.imageWindow.hidden ||
        self.imageController.imageView.window != self.imageWindow || !self.imageController.imageView.image) {
        [self invalidate:ticket]; return;
    }
    [self.imageWindow layoutIfNeeded];
    if (!state.owns(ticket)) return;
    const double now = continuousSeconds();
    if (state.firstDisplay(ticket, now, true, true)) { PMDiagnosticsWrite("Song interruption: blue image displayed; realtime delay started"); return; } // Even delay=0 gets an image frame.
    if (!state.claimAlert(ticket, now, true)) return;
    auto payload = state.payload();
    if (self.imageController.presentedViewController) { [self invalidate:ticket]; return; }
    PMDiagnosticsWrite("Song interruption: presenting single-button quit alert");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:payload->prepared.title
        message:payload->prepared.message preferredStyle:UIAlertControllerStyleAlert];
    __weak PMSongInterruptionOwner *weak = self;
    [alert addAction:[UIAlertAction actionWithTitle:payload->prepared.button style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) { (void)action; [weak close:ticket]; }]];
    alert.modalInPresentation = YES;
    self.alert = alert;
    @try {
        [self.imageController presentViewController:alert animated:NO completion:^{
            PMSongInterruptionOwner *owner = weak;
            if (!owner || !owner->state.owns(ticket)) return;
            if (owner.alert != alert || alert.presentingViewController != owner.imageController)
                [owner invalidate:ticket];
        }];
    } @catch (NSException *exception) { (void)exception; [self invalidate:ticket]; }
}
- (void)close:(PMInterruptionTicket)ticket {
    // Only this UIAlertAction handler can enter here. A delivered user action
    // must not be lost if the app deactivates immediately after the tap.
    if (![self validHost:ticket] || !state.claimQuit(ticket)) return;
    void (^callback)(void) = self.quit;
    self.quit = nil;
    // No native calls, fallback exit, saves, navigation or second dialog here.
    if (callback) { PMDiagnosticsWrite("Song interruption: user pressed close application"); callback(); }
}
@end

void PMSetSongInterruptionHostGuard(BOOL (^guard)(void), void (^invalidated)(void)) {
    if (!NSThread.isMainThread) return;
    configuredGuard = [guard copy];
    configuredInvalidation = [invalidated copy];
}
BOOL PMArmSongInterruption(PMPreparedSongInterruption *prepared, NSString *chartID, int slot) {
    if (!NSThread.isMainThread) return NO;
    PMSongInterruptionOwner *owner = interruptionOwner();
    if (!prepared) { owner->state.cancelLaunch(); return YES; }
    if (![prepared isKindOfClass:PMPreparedSongInterruption.class] || !PMInterruptionText(chartID) || slot < 0) {
        owner->state.cancelLaunch(); return NO;
    }
    auto payload = std::make_shared<PMInterruptionPayload>();
    payload->prepared = prepared;
    auto host = gameHost();
    if (host.window && !completeCover(payload, windowAspect(host.window))) {
        owner->state.cancelLaunch(); return NO;
    }
    BOOL armed=owner->state.arm(std::move(payload), chartID.UTF8String, slot, prepared.at, prepared.delay);
    PMDiagnosticsWrite([[NSString stringWithFormat:@"Song interruption arm chart=%@ slot=%d at=%.3f accepted=%d",chartID,slot,prepared.at,armed] UTF8String]);
    return armed;
}
BOOL PMSongInterruptionPending(void) {
    return NSThread.isMainThread && interruptionOwner()->state.pending();
}
BOOL PMBeginSongInterruption(NSString *chartID, int slot) {
    if (!NSThread.isMainThread) return NO;
    PMSongInterruptionOwner *owner = interruptionOwner();
    auto previous = owner->state.payload();
    BOOL accepted = owner->state.begin(PMInterruptionText(chartID) ? chartID.UTF8String : "", slot);
    auto ticket = owner->state.ticket();
    if (accepted) {
        auto playing = owner->state.payload();
        playing->guard = [configuredGuard copy];
        playing->invalidated = [configuredInvalidation copy];
    }
    [owner clearUI];
    notifyInvalidation(previous);
    PMDiagnosticsWrite([[NSString stringWithFormat:@"Song interruption begin chart=%@ slot=%d accepted=%d",chartID,slot,accepted] UTF8String]);
    return accepted && owner->state.owns(ticket); // Invalidation may reenter.
}
void PMCancelSongInterruptionLaunch(void) {
    if (NSThread.isMainThread) interruptionOwner()->state.cancelLaunch();
}
void PMEndSongInterruption(void) {
    if (!NSThread.isMainThread) return;
    PMSongInterruptionOwner *owner = interruptionOwner();
    auto previous = owner->state.payload();
    owner->state.end();
    [owner clearUI];
    notifyInvalidation(previous);
}
BOOL PMSongInterruptionDue(double songTime) {
    if (!NSThread.isMainThread) return NO;
    PMSongInterruptionOwner *owner = interruptionOwner();
    return [owner validHost:owner->state.ticket()] && owner->state.due(songTime);
}
BOOL PMTriggerSongInterruption(BOOL (^freeze)(void), void (^quit)(void)) {
    if (!NSThread.isMainThread || !freeze || !quit) return NO;
    PMSongInterruptionOwner *owner = interruptionOwner();
    auto ticket = owner->state.ticket();
    if (![owner validHost:ticket] || owner->state.phase() != PMInterruptionState::Phase::Playing) return NO;
    auto host = gameHost();
    if (!activeWindow(host.window) || host.window.hidden || !host.controller ||
        host.window.rootViewController.presentedViewController) return NO;
    auto payload = owner->state.payload();
    owner.gameWindow = host.window; owner.gameScene = host.window.windowScene;
    owner.gameController = host.controller; owner.gameRoot = host.window.rootViewController;
    owner.gameView = host.view;
    ticket = owner->state.requestTrigger();
    if (!ticket) return NO;
    BOOL frozen = NO;
    @try { try { frozen = freeze(); } catch (...) {} } @catch (NSException *exception) { (void)exception; }
    if (!owner->state.owns(ticket)) return NO;
    if (!frozen) {
        owner->state.frozen(ticket, false); // Tested failure path; never entered blocking.
        [owner clearUI];
        notifyInvalidation(payload);
        return NO;
    }
    if (![owner validHost:ticket] || !activeWindow(host.window)) { [owner invalidate:ticket]; return NO; }
    if (!owner->state.frozen(ticket, true)) return NO;
    // Freeze at the due call before any orientation-correction raster work. Arm
    // normally warmed this exact aspect; only a changed orientation recomposes.
    UIImage *cover = completeCover(payload, windowAspect(host.window));
    if (!cover) { [owner invalidate:ticket]; return NO; }
    @try {
        PMSongInterruptionController *controller = [PMSongInterruptionController new];
        controller.gameController = host.controller;
        [controller loadViewIfNeeded];
        controller.imageView.image = cover;
        UIWindow *window = host.window.windowScene ? [[UIWindow alloc] initWithWindowScene:host.window.windowScene]
                                                   : [[UIWindow alloc] initWithFrame:host.window.frame];
        // Match the validated game's coordinate space, including legacy rotation.
        window.frame = host.window.windowScene ? host.window.windowScene.coordinateSpace.bounds : host.window.frame;
        window.windowLevel = host.window.windowLevel + 1;
        window.rootViewController = controller;
        owner.imageController = controller; owner.imageWindow = window;
        owner.quit = [quit copy];
        __weak PMSongInterruptionOwner *weak = owner;
        controller.layoutChanged = ^(CGSize size) {
            PMSongInterruptionOwner *current = weak;
            if (!current || !current->state.owns(ticket) || size.width <= 0 || size.height <= 0) return;
            UIImage *image = completeCover(current->state.payload(), size.width / size.height);
            if (!image) { [current invalidate:ticket]; return; }
            current.imageController.imageView.image = image;
        };
        [window makeKeyAndVisible];
        [window layoutIfNeeded];
        if (!owner->state.owns(ticket) || ![owner validHost:ticket]) return NO;
        [owner observe:ticket];
        owner.clock = [CADisplayLink displayLinkWithTarget:owner selector:@selector(step:)];
        [owner.clock addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        return YES;
    } @catch (NSException *exception) { (void)exception; [owner invalidate:ticket]; return NO; }
}
BOOL PMSongInterruptionBlocking(void) {
    if (!NSThread.isMainThread) return NO;
    PMSongInterruptionOwner *owner = interruptionOwner();
    return owner->state.blocking() && [owner validHost:owner->state.ticket()];
}
