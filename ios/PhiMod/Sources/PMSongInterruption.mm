#import "PMSongInterruption.h"
#import "PMChapterArt.h"
#import "PMCoverImage.h"
#import "PMDiagnostics.h"
#include "PMSongInterruptionWindow.hpp"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
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
static NSData *PMReadInterruptionMedia(NSString *chapter, NSString *src, NSArray<NSString *> *extensions, NSError **error, off_t limit = 32 * 1024 * 1024) {
    // Keep the shared whitelist; descriptor-relative opens also close its symlink
    // check/open race for chapter, os-media and the final file. No arbitrary URL.
    if (!PMOSLocalMediaPath(chapter, src, extensions)) {
        if (error) *error = PMInterruptionError(@"Invalid interruption media basename");
        return nil;
    }
    PMInterruptionFD root(open(chapter.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
    PMInterruptionFD media(root.value < 0 ? -1 : openat(root.value, "os-media", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
    PMInterruptionFD file(media.value < 0 ? -1 : openat(media.value, src.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC));
    struct stat before = {}, after = {};
    if (file.value < 0 || fstat(file.value, &before) || !S_ISREG(before.st_mode) ||
        before.st_size <= 0 || before.st_size > limit) {
        if (error) *error = PMInterruptionError(@"Interruption media must be a nonempty regular file within the remaining byte budget");
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
        if (error) *error = PMInterruptionError(@"Interruption media changed or could not be read");
        return nil;
    }
    return bytes;
}

@interface PMPreparedSongInterruption ()
@property(nonatomic, strong) UIImage *image;
@property(nonatomic, copy) NSDictionary<NSString *, NSData *> *audioData;
- (instancetype)initWithConfig:(NSDictionary *)config image:(UIImage *)image audio:(NSDictionary<NSString *, NSData *> *)audio;
@end
@implementation PMPreparedSongInterruption
- (instancetype)initWithConfig:(NSDictionary *)config image:(UIImage *)image audio:(NSDictionary<NSString *, NSData *> *)audio {
    if ((self = [super init])) {
        _at = [config[@"at"] doubleValue];
        _delay = config[@"delay"] ? [config[@"delay"] doubleValue] : 2;
        _staged = config[@"effectDuration"] || config[@"blackDuration"] || config[@"blueDuration"];
        _effectDuration = [config[@"effectDuration"] doubleValue];
        _blackDuration = [config[@"blackDuration"] doubleValue];
        _blueDuration = config[@"blueDuration"] ? [config[@"blueDuration"] doubleValue] : _delay;
        _effectAudioSrc = [config[@"effectAudioSrc"] copy] ?: @"";
        _blackAudioSrc = [config[@"blackAudioSrc"] copy] ?: @"";
        _blueAudioSrc = [config[@"blueAudioSrc"] copy] ?: @"";
        _audioVolume = config[@"audioVolume"] ? [config[@"audioVolume"] doubleValue] : 1;
        _effectAudioDelay=[config[@"effectAudioDelay"] doubleValue];
        _blackAudioDelay=[config[@"blackAudioDelay"] doubleValue];
        _blueAudioDelay=[config[@"blueAudioDelay"] doubleValue];
        _audioTail=[config[@"audioTail"] boolValue];
        _audioData = [audio copy];
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
        for (NSString *key in @[@"effectDuration", @"blackDuration", @"blueDuration"]) {
            if (config[key] && (!PMInterruptionNumber(config[key]) || [config[key] doubleValue] < 0 || [config[key] doubleValue] > 600)) {
                if (error) *error = PMInterruptionError([@"Invalid interruption duration: " stringByAppendingString:key]);
                return nil;
            }
        }
        BOOL staged = config[@"effectDuration"] || config[@"blackDuration"] || config[@"blueDuration"];
        BOOL hasAudio = config[@"effectAudioSrc"] || config[@"blackAudioSrc"] || config[@"blueAudioSrc"] || config[@"audioVolume"] || config[@"audioTail"] || config[@"effectAudioDelay"] || config[@"blackAudioDelay"] || config[@"blueAudioDelay"];
        if (hasAudio && !staged) {
            if (error) *error = PMInterruptionError(@"Interruption audio requires an explicit staged timeline");
            return nil;
        }
        if (config[@"audioVolume"] && (!PMInterruptionNumber(config[@"audioVolume"]) ||
            [config[@"audioVolume"] doubleValue] < 0 || [config[@"audioVolume"] doubleValue] > 1)) {
            if (error) *error = PMInterruptionError(@"Invalid interruption audio volume");
            return nil;
        }
        if(config[@"audioTail"] && CFGetTypeID((__bridge CFTypeRef)config[@"audioTail"])!=CFBooleanGetTypeID()) {
            if(error)*error=PMInterruptionError(@"audioTail expects boolean");return nil;
        }
        NSMutableDictionary<NSString *, NSData *> *audio = [NSMutableDictionary dictionary];
        off_t remainingAudioBytes = 32 * 1024 * 1024;
        for (NSString *phase in @[@"effect", @"black", @"blue"]) {
            NSString *key = [phase stringByAppendingString:@"AudioSrc"];
            NSString *delayKey=[phase stringByAppendingString:@"AudioDelay"];
            if(config[delayKey] && (!PMInterruptionNumber(config[delayKey]) || [config[delayKey] doubleValue]<0 || [config[delayKey] doubleValue]>600 || !config[key])) {
                if(error)*error=PMInterruptionError(@"Invalid stage audio delay or missing source");return nil;
            }
            if (!config[key]) continue;
            NSString *durationKey = [phase stringByAppendingString:@"Duration"];
            double duration = config[durationKey] ? [config[durationKey] doubleValue] : ([phase isEqual:@"blue"] ? delay : 0);
            if (!PMInterruptionText(config[key]) || duration <= 0 || [config[delayKey] doubleValue]>=duration) {
                if (error) *error = PMInterruptionError([@"Invalid interruption audio or disabled stage: " stringByAppendingString:key]);
                return nil;
            }
            NSData *data = PMReadInterruptionMedia(chapterDir, config[key], @[@"wav", @"mp3", @"m4a", @"aac", @"caf", @"aiff", @"aif"], error, remainingAudioBytes);
            if (!data) return nil;
            remainingAudioBytes -= (off_t)data.length;
            AVAudioPlayer *probe = [[AVAudioPlayer alloc] initWithData:data error:error];
            if (!probe || !std::isfinite(probe.duration) || probe.duration <= 0 || probe.numberOfChannels == 0) {
                if (error && !*error) *error = PMInterruptionError(@"Cannot decode interruption audio");
                return nil;
            }
            audio[phase] = data;
        }
        NSData *data = PMReadInterruptionMedia(chapterDir, config[@"src"], @[@"png", @"jpg", @"jpeg", @"webp"], error);
        if (!data) return nil;
        UIImage *image = PMDecodeCoverData(data, error);
        return image ? [[PMPreparedSongInterruption alloc] initWithConfig:config image:image audio:audio] : nil;
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
    BOOL (^effect)(PMSongInterruptionEffectEvent, UIView *, NSTimeInterval) = nil;
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
static BOOL (^configuredEffect)(PMSongInterruptionEffectEvent, UIView *, NSTimeInterval);
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
    // Continuous clock; explicit timelines subtract inactive intervals in Owner.
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

@interface PMInterruptionMediaSession : NSObject {
    pmsonginterruption::MediaLifecycle lifecycle;
    BOOL resumeAudio;
}
@property(nonatomic, copy) BOOL (^effect)(PMSongInterruptionEffectEvent, UIView *, NSTimeInterval);
@property(nonatomic, strong) UIView *container;
@property(nonatomic) NSTimeInterval duration;
@property(nonatomic, strong) AVAudioPlayer *audio;
- (BOOL)start;
- (BOOL)event:(PMSongInterruptionEffectEvent)event;
- (BOOL)pause;
- (BOOL)resume;
- (void)stop;
@end
@implementation PMInterruptionMediaSession
- (BOOL)event:(PMSongInterruptionEffectEvent)event {
    @try { try { return self.effect ? self.effect(event, self.container, self.duration) : YES; }
        catch (...) { return NO; } } @catch (NSException *exception) { (void)exception; return NO; }
}
- (BOOL)start {
    if (lifecycle.start() == pmsonginterruption::MediaLifecycle::Event::None) return YES;
    if (self.audio) {
        @try { return [self.audio prepareToPlay] && [self.audio play]; }
        @catch (NSException *exception) { (void)exception; return NO; }
    }
    return [self event:PMSongInterruptionEffectStart];
}
- (BOOL)pause {
    if (lifecycle.pause() == pmsonginterruption::MediaLifecycle::Event::None) return YES;
    if (self.audio) {
        @try { resumeAudio = self.audio.playing; [self.audio pause]; return YES; }
        @catch (NSException *exception) { (void)exception; resumeAudio = NO; return NO; }
    }
    return [self event:PMSongInterruptionEffectPause];
}
- (BOOL)resume {
    if (lifecycle.resume() == pmsonginterruption::MediaLifecycle::Event::None) return YES;
    if (self.audio) {
        BOOL play = resumeAudio; resumeAudio = NO;
        @try { return !play || [self.audio play]; }
        @catch (NSException *exception) { (void)exception; return NO; }
    }
    return [self event:PMSongInterruptionEffectResume];
}
- (void)stop {
    if (lifecycle.stop() == pmsonginterruption::MediaLifecycle::Event::None) return;
    @try { [self.audio stop]; } @catch (NSException *exception) { (void)exception; }
    if (self.effect) [self event:PMSongInterruptionEffectStop];
    self.effect = nil; self.container = nil; self.audio = nil;
}
@end

@interface PMSongInterruptionController : UIViewController
@property(nonatomic, strong) UIImageView *imageView;
@property(nonatomic, strong) UIView *effectView;
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
    self.effectView = [[UIView alloc] initWithFrame:CGRectZero];
    self.effectView.backgroundColor = UIColor.clearColor;
    self.effectView.hidden = YES;
    [self.view addSubview:self.effectView];
    self.view.accessibilityViewIsModal = YES;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.effectView.frame = self.view.bounds;
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
@property(nonatomic, strong) PMInterruptionMediaSession *effectSession;
@property(nonatomic, strong) NSMutableDictionary<NSString *,PMInterruptionMediaSession *> *audioSessions;
@property(nonatomic) BOOL mediaSuspended;
@property(nonatomic, strong) NSMutableArray *observers;
@property(nonatomic, copy) void (^quit)(void);
- (void)clearUI;
- (BOOL)renderStage:(PMInterruptionTicket)ticket;
- (BOOL)displayMedia:(PMInterruptionTicket)ticket;
- (void)suspend:(PMInterruptionTicket)ticket;
- (void)muteFailedAudio:(NSString *)phase;
- (void)stopAudio;
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
    PMInterruptionMediaSession *effect = self.effectSession;
    self.effectSession = nil;[self stopAudio];
    self.mediaSuspended = NO;
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
    [effect stop]; // Last: user-supplied handler may synchronously install a new owner.
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
- (BOOL)renderStage:(PMInterruptionTicket)ticket {
    if (!state.owns(ticket)) return NO;
    PMInterruptionMediaSession *effect = self.effectSession;
    self.effectSession = nil;self.mediaSuspended=NO;
    if(!state.payload()->prepared.audioTail)[self stopAudio];
    [effect stop];
    if (!state.owns(ticket)) return NO;
    auto stage = state.stage();
    self.imageController.view.backgroundColor = stage == pmsonginterruption::Stage::Effect ? UIColor.clearColor : UIColor.blackColor;
    self.imageController.imageView.hidden = stage != pmsonginterruption::Stage::Blue;
    self.imageController.effectView.hidden = stage != pmsonginterruption::Stage::Effect;
    if (stage == pmsonginterruption::Stage::Effect) {
        PMInterruptionMediaSession *session = [PMInterruptionMediaSession new];
        session.effect = state.payload()->effect;
        session.container = self.imageController.effectView;
        session.duration = state.payload()->prepared.effectDuration;
        self.effectSession = session;
        if (!session.effect || ![session start]) { [self invalidate:ticket]; return NO; }
    }
    return state.owns(ticket);
}
- (void)stopAudio {
    NSDictionary *sessions=self.audioSessions;self.audioSessions=nil;
    for(PMInterruptionMediaSession *media in sessions.allValues)[media stop];
}
- (void)muteFailedAudio:(NSString *)phase {
    PMInterruptionMediaSession *media=self.audioSessions[phase];[self.audioSessions removeObjectForKey:phase];[media stop];
    PMDiagnosticsWrite("Song interruption: stage audio failed; continuing visual timeline silently");
}
- (BOOL)displayMedia:(PMInterruptionTicket)ticket {
    if(!state.owns(ticket))return NO;
    if(self.mediaSuspended){
        self.mediaSuspended=NO;
        if(self.effectSession && ![self.effectSession resume]){[self invalidate:ticket];return NO;}
        if(!state.owns(ticket))return NO;
        for(NSString *phase in self.audioSessions.allKeys)
            if(![self.audioSessions[phase] resume])[self muteFailedAudio:phase];
    }
    if(!state.owns(ticket))return NO;
    if(self.effectSession && ![self.effectSession event:PMSongInterruptionEffectFrame]){[self invalidate:ticket];return NO;}
    if(!state.owns(ticket))return NO;
    auto payload=state.payload();
    NSString *phase=state.stage()==pmsonginterruption::Stage::Effect?@"effect":state.stage()==pmsonginterruption::Stage::Black?@"black":@"blue";
    double delay=state.stage()==pmsonginterruption::Stage::Effect?payload->prepared.effectAudioDelay:
                 state.stage()==pmsonginterruption::Stage::Black?payload->prepared.blackAudioDelay:payload->prepared.blueAudioDelay;
    if(payload->prepared.audioData[phase] && state.claimAudio(ticket,continuousSeconds(),delay)){
        // The owner consumes before playback, including failed decode/start.
        if(!self.audioSessions)self.audioSessions=[NSMutableDictionary dictionary];
        PMInterruptionMediaSession *media=[PMInterruptionMediaSession new];
        @try {
            NSError *error=nil;media.audio=[[AVAudioPlayer alloc]initWithData:payload->prepared.audioData[phase] error:&error];
            media.audio.volume=(float)payload->prepared.audioVolume;media.audio.numberOfLoops=0;
            self.audioSessions[phase]=media;
            if(!media.audio || ![media start])[self muteFailedAudio:phase];
        } @catch(NSException *exception){(void)exception;[self muteFailedAudio:phase];}
    }
    return state.owns(ticket);
}
- (void)suspend:(PMInterruptionTicket)ticket {
    if(!state.owns(ticket) || self.mediaSuspended)return;
    state.suspend(ticket,continuousSeconds());self.clock.paused=YES;self.mediaSuspended=YES;
    if(self.effectSession && ![self.effectSession pause]){[self invalidate:ticket];return;}
    if(!state.owns(ticket))return;
    for(NSString *phase in self.audioSessions.allKeys)
        if(![self.audioSessions[phase] pause])[self muteFailedAudio:phase];
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
            // Scene notifications from other windows cannot pause this owner.
            BOOL sceneNote = [note.name isEqual:UISceneWillDeactivateNotification] ||
                [note.name isEqual:UISceneDidActivateNotification] || [note.name isEqual:UISceneDidDisconnectNotification];
            if (sceneNote && note.object != owner.gameScene) return;
            BOOL deactivating = [note.name isEqual:UIApplicationWillResignActiveNotification] ||
                [note.name isEqual:UIApplicationDidEnterBackgroundNotification] ||
                [note.name isEqual:UISceneWillDeactivateNotification];
            if (deactivating || !activeWindow(owner.gameWindow)) { [owner suspend:ticket]; return; }
            owner.clock.paused = !activeWindow(owner.gameWindow);
            // Resume only on the next displayed frame, never in a notification.
        }];
        [self.observers addObject:observer];
    }
}
- (void)step:(CADisplayLink *)clock {
    if (clock != self.clock) return;
    auto ticket = state.ticket();
    if (![self validHost:ticket]) return;
    BOOL active = activeWindow(self.gameWindow);
    if (!active) { [self suspend:ticket]; return; }
    if (!self.imageWindow || self.imageWindow.hidden ||
        self.imageController.imageView.window != self.imageWindow || !self.imageController.imageView.image) {
        [self invalidate:ticket]; return;
    }
    [self.imageWindow layoutIfNeeded];
    if (!state.owns(ticket)) return;
    const double now = continuousSeconds();
    if (state.firstDisplay(ticket, now, true, true)) {
        [self displayMedia:ticket];
        return; // Every stage, including zero-length blue, gets a displayed frame.
    }
    if (![self displayMedia:ticket]) return; // Legacy resume also preserves media position.
    if (state.advanceStage(ticket, now, true)) { [self renderStage:ticket]; return; }
    if (!state.claimAlert(ticket, now, true)) return;
    if(!state.payload()->prepared.audioTail)[self stopAudio];
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
        [self.imageController presentViewController:alert animated:YES completion:^{
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

void PMSetSongInterruptionEffectHandler(BOOL (^handler)(PMSongInterruptionEffectEvent, UIView *, NSTimeInterval)) {
    if (NSThread.isMainThread) configuredEffect = [handler copy];
}
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
    BOOL armed=owner->state.arm(std::move(payload), chartID.UTF8String, slot, prepared.at, prepared.delay,
        {bool(prepared.staged), prepared.effectDuration, prepared.blackDuration, prepared.blueDuration});
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
        playing->effect = [configuredEffect copy];
        playing->guard = [configuredGuard copy];
        playing->invalidated = [configuredInvalidation copy];
    }
    [owner clearUI];
    notifyInvalidation(previous);
    if (accepted && owner->state.owns(ticket) && owner->state.payload()->prepared.effectDuration > 0 && !owner->state.payload()->effect) {
        [owner invalidate:ticket]; accepted = NO;
    }
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
        window.backgroundColor = UIColor.clearColor;
        window.opaque = NO;
        controller.view.frame = window.bounds;
        [controller.view layoutIfNeeded];
        if (![owner renderStage:ticket]) return NO;
        [window makeKeyAndVisible];
        [window layoutIfNeeded];
        if (!owner->state.owns(ticket) || ![owner validHost:ticket]) return NO;
        [owner observe:ticket];
        owner.clock = [CADisplayLink displayLinkWithTarget:owner selector:@selector(step:)];
        [owner.clock addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        if (!activeWindow(host.window)) [owner suspend:ticket];
        return owner->state.owns(ticket);
    } @catch (NSException *exception) { (void)exception; [owner invalidate:ticket]; return NO; }
}
BOOL PMSongInterruptionBlocking(void) {
    if (!NSThread.isMainThread) return NO;
    PMSongInterruptionOwner *owner = interruptionOwner();
    return owner->state.blocking() && [owner validHost:owner->state.ticket()];
}
