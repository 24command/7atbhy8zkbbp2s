#import "PMUnlockMedia.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#include <cmath>

@protocol PMMediaPresentation <NSObject>
- (void)finish:(BOOL)completed;
@end

@interface PMUnlockMediaView : UIView <PMMediaPresentation>
@property(nonatomic) BOOL strict;
@property(nonatomic,strong) UIView *timelineOverlay;
@property(nonatomic,copy) void (^sample)(double);
@property(nonatomic) double durationLimit;
@property(nonatomic,strong) AVPlayer *player;
@property(nonatomic,strong) AVPlayerLayer *video;
@property(nonatomic,strong) UIImageView *image;
@property(nonatomic,strong) UILabel *message;
@property(nonatomic,strong) CADisplayLink *clock;
@property(nonatomic,strong) id endToken;
@property(nonatomic,copy) void (^completion)(BOOL);
@property(nonatomic,copy) NSString *cover;
@property(nonatomic,assign) CGImageSourceRef gif;
@property(nonatomic,strong) NSArray<NSNumber*> *ends;
@property(nonatomic,assign) NSUInteger lastFrame;
@property(nonatomic,assign) CFTimeInterval created;
@property(nonatomic,assign) CFTimeInterval began;
@property(nonatomic,assign) BOOL fallback;
- (void)finish:(BOOL)completed;
@end
static UIView<PMMediaPresentation> *activeMedia;
@implementation PMUnlockMediaView
- (void)layoutSubviews{[super layoutSubviews];self.image.frame=self.bounds;self.video.frame=self.bounds;self.timelineOverlay.frame=self.bounds;self.message.frame=CGRectInset(self.bounds,40,80);UIView*skip=[self viewWithTag:101];skip.frame=CGRectMake(MAX(12,self.bounds.size.width-132),MAX(12,self.safeAreaInsets.top+8),112,44);}
- (void)showFallback{
 self.timelineOverlay.hidden=YES;self.fallback=YES;self.began=CACurrentMediaTime();[self.player pause];[self.video removeFromSuperlayer];self.video=nil;
 self.image.image=[UIImage imageWithContentsOfFile:self.cover];self.image.hidden=NO;
 self.message.text=@"Unlocked — tap Skip to continue";self.message.hidden=NO;
}
- (void)skip{[self finish:!(self.strict && self.fallback)];}
- (void)step:(CADisplayLink*)clock{
 if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){[self finish:NO];return;}
 if(self.fallback){if(clock.timestamp-self.began>.75)[self finish:!self.strict];return;}
 if(self.gif){
  double elapsed=clock.timestamp-self.began;if(elapsed>=[self.ends.lastObject doubleValue]){[self finish:YES];return;}
  NSUInteger i=0;while(i+1<self.ends.count&&elapsed>=[self.ends[i] doubleValue])++i;
  if(i!=self.lastFrame){CGImageRef frame=CGImageSourceCreateImageAtIndex(self.gif,i,NULL);if(!frame){[self showFallback];return;}self.image.image=[UIImage imageWithCGImage:frame];CGImageRelease(frame);self.lastFrame=i;}
 }else if(self.player){
  if(self.player.status==AVPlayerStatusFailed||self.player.currentItem.status==AVPlayerItemStatusFailed){[self showFallback];return;}
  if(self.player.currentItem.status==AVPlayerItemStatusReadyToPlay&&!self.began){self.began=clock.timestamp;[self.player play];}
  if(self.began && self.sample){
   double seconds=CMTimeGetSeconds(self.player.currentTime);
   if(std::isfinite(seconds) && seconds>=0){
    if(self.durationLimit>0 && seconds>=self.durationLimit){[self finish:YES];return;}
    self.sample(seconds);
   }
  }
  if((!self.began&&clock.timestamp-self.created>20)||(self.began&&clock.timestamp-self.began>610))[self showFallback];
 }
}
- (void)finish:(BOOL)completed{
 if(activeMedia!=self)return;
 [self.clock invalidate];self.clock=nil;[self.player pause];self.player=nil;
 if(self.endToken)[NSNotificationCenter.defaultCenter removeObserver:self.endToken];self.endToken=nil;
 if(self.gif){CFRelease(self.gif);self.gif=NULL;}
 void(^done)(BOOL)=self.completion;self.completion=nil;[self removeFromSuperview];activeMedia=nil;if(done)done(completed);
}
@end
BOOL PMUnlockMediaBusy(void){return activeMedia!=nil;}
void PMConfigureUnlockTimeline(UIView *overlay,double duration,void (^sample)(double)){
 if(![activeMedia isKindOfClass:PMUnlockMediaView.class])return;
 PMUnlockMediaView *view=(PMUnlockMediaView*)activeMedia;
 if(!view || !view.player || !sample)return;
 view.durationLimit=duration;
 view.timelineOverlay=overlay;
 if(overlay){
  overlay.frame=view.bounds;overlay.userInteractionEnabled=NO;
  [view insertSubview:overlay belowSubview:[view viewWithTag:101]];
 }
 view.sample=sample;sample(0);
}
void PMCancelUnlockMedia(void){[activeMedia finish:NO];}
BOOL PMPresentUnlockMedia(NSString*path,NSString*cover,NSString*title,void(^completion)(BOOL)){
 return PMPresentUnlockMediaWithPolicy(path,cover,title,NO,completion);
}
BOOL PMPresentUnlockMediaWithPolicy(NSString*path,NSString*cover,NSString*title,BOOL strict,void(^completion)(BOOL)){
 if(!NSThread.isMainThread||activeMedia||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return NO;
 UIWindow*window=nil;for(UIScene*scene in UIApplication.sharedApplication.connectedScenes)if(scene.activationState==UISceneActivationStateForegroundActive&&[scene isKindOfClass:UIWindowScene.class])for(UIWindow*w in ((UIWindowScene*)scene).windows)if(w.isKeyWindow)window=w;
 if(!window||window.rootViewController.presentedViewController)return NO;
 PMUnlockMediaView*v=[[PMUnlockMediaView alloc]initWithFrame:window.bounds];v.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;v.backgroundColor=UIColor.blackColor;v.accessibilityViewIsModal=YES;v.completion=completion;v.cover=cover;v.created=CACurrentMediaTime();v.lastFrame=NSNotFound;
 v.image=[UIImageView new];v.image.contentMode=UIViewContentModeScaleAspectFit;[v addSubview:v.image];
 v.strict=strict;v.message=[UILabel new];v.message.text=title;v.message.textAlignment=NSTextAlignmentCenter;v.message.textColor=UIColor.whiteColor;v.message.numberOfLines=0;v.message.hidden=YES;[v addSubview:v.message];
 UIButton*skip=[UIButton buttonWithType:UIButtonTypeSystem];skip.tag=101;[skip setTitle:@"Skip / 继续" forState:UIControlStateNormal];skip.tintColor=UIColor.whiteColor;skip.backgroundColor=[UIColor colorWithWhite:.2 alpha:.85];[skip addTarget:v action:@selector(skip) forControlEvents:UIControlEventTouchUpInside];[v addSubview:skip];
 activeMedia=v;[window addSubview:v];
 if([path.pathExtension.lowercaseString isEqualToString:@"gif"]){
  NSDictionary*attrs=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
  if([attrs[NSFileSize] unsignedLongLongValue]<=32ull*1024*1024)v.gif=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],NULL);
  NSMutableArray*ends=[NSMutableArray new];double total=0;size_t count=v.gif?CGImageSourceGetCount(v.gif):0;
  for(size_t i=0;i<count;i++){
   NSDictionary*p=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(v.gif,i,NULL));NSDictionary*g=p[(NSString*)kCGImagePropertyGIFDictionary];
   double delay=[(g[(NSString*)kCGImagePropertyGIFUnclampedDelayTime]?:g[(NSString*)kCGImagePropertyGIFDelayTime]) doubleValue];if(!std::isfinite(delay)||delay<.02)delay=.1;
   if([p[(NSString*)kCGImagePropertyPixelWidth] doubleValue]>4096||[p[(NSString*)kCGImagePropertyPixelHeight] doubleValue]>4096){[ends removeAllObjects];break;}
   total+=delay;if(total>600){[ends removeAllObjects];break;}[ends addObject:@(total)];
  }
  if(!ends.count)[v showFallback];else{v.ends=ends;v.began=CACurrentMediaTime();}
 }else if([path.pathExtension.lowercaseString isEqualToString:@"mp4"]&&[NSFileManager.defaultManager fileExistsAtPath:path]){
  v.player=[AVPlayer playerWithURL:[NSURL fileURLWithPath:path]];v.video=[AVPlayerLayer playerLayerWithPlayer:v.player];v.video.videoGravity=AVLayerVideoGravityResizeAspect;[v.layer insertSublayer:v.video atIndex:0];v.image.hidden=YES;
  __weak PMUnlockMediaView*weak=v;v.endToken=[NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:v.player.currentItem queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*n){[weak finish:YES];}];
 }else [v showFallback];
 v.clock=[CADisplayLink displayLinkWithTarget:v selector:@selector(step:)];[v.clock addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];[v setNeedsLayout];return YES;
}


// BEGIN PM_HELD_TRANSITION_CORE
// Kept in this translation unit; portable tests compile this exact decision core.
namespace PMHeldTransition {
enum class Phase { Preparing, Playing, Holding, Finished };
enum class Event { None, Load, Complete };
static constexpr double DecodeTimeout=20, LoadTimeout=60, StallTimeout=20, PlayTimeout=610;
struct Timeline {
 bool video=false, suspended=false, failed=false, loadRequested=false;
 bool resumeReceived=false, resumeOK=false, atEnd=false, succeeded=false;
 Phase phase=Phase::Preparing;
 double duration=0, loadAt=-1, time=0, end=0, waiting=0, stalled=0, playing=0;
 Timeline(bool hasVideo=false,double seconds=0,double gate=-1)
 :video(hasVideo),duration(seconds),loadAt(gate),end(hasVideo&&seconds==0?-1:seconds){}
 static bool valid(double duration,double loadAt){
  return std::isfinite(duration)&&duration>=0&&std::isfinite(loadAt);
 }
 void naturalEnd(double seconds){
  if(video&&std::isfinite(seconds)&&seconds>0)
   end=duration>0&&duration<seconds?duration:seconds;
 }
 double stop() const {
  if(!loadRequested&&loadAt>=0&&(end<0||loadAt<end))return loadAt;
  return end;
 }
 Event finish(bool ok){
  if(phase==Phase::Finished)return Event::None;
  succeeded=ok;phase=Phase::Finished;return Event::Complete;
 }
 Event hold(){
  loadRequested=true;phase=Phase::Holding;waiting=0;return Event::Load;
 }
 Event fail(){
  if(phase==Phase::Finished)return Event::None;
  failed=true;atEnd=true;
  if(!loadRequested)return hold();
  if(resumeReceived)return finish(false);
  // A decode error during a pending load cannot request load again or extend it.
  return Event::None;
 }
 Event consumeResume(){
  if(suspended||phase!=Phase::Holding||!resumeReceived)return Event::None;
  if(!resumeOK||failed||atEnd)return finish(resumeOK&&!failed);
  phase=Phase::Playing;waiting=0;stalled=0;return Event::None;
 }
 Event resume(bool ok){
  if(phase!=Phase::Holding||resumeReceived)return Event::None;
  resumeReceived=true;resumeOK=ok;return consumeResume();
 }
 Event advance(double delta,bool ready,double position,bool ended=false){
  if(suspended||phase==Phase::Finished)return Event::None;
  if(!std::isfinite(delta)||delta<0)delta=0;
  if(phase==Phase::Holding){
   if(resumeReceived)return consumeResume();
   waiting+=delta;
   return waiting>=LoadTimeout?finish(false):Event::None;
  }
  if(phase==Phase::Preparing){
   waiting+=delta;
   if(!ready)return waiting>=DecodeTimeout?fail():Event::None;
   phase=Phase::Playing;waiting=0;delta=0;
  }
  const double previous=time;
  if(video){if(std::isfinite(position)&&position>time)time=position;}
  else time+=delta;
  playing+=delta;
  if(ended&&end<0)end=time;
  if(ended&&end>=0)time=end;
  if(end>=0&&time>end)time=end;
  const double gate=stop();
  if(!loadRequested&&gate>=0&&time>=gate){
   time=gate;atEnd=end>=0&&time>=end;return hold();
  }
  if((end>=0&&time>=end)||ended){
   atEnd=true;
   return loadRequested?finish(true):hold();
  }
  if(video)stalled=time>previous+0.000001?0:stalled+delta;
  if(stalled>=StallTimeout||playing>=PlayTimeout)return fail();
  return Event::None;
 }
};
} // namespace PMHeldTransition
// END PM_HELD_TRANSITION_CORE

@interface PMTransitionMediaView : UIView <PMMediaPresentation> {
 PMHeldTransition::Timeline _timeline;
 CFTimeInterval _lastTick;
 BOOL _finished, _decodeFailed, _configured, _loadScheduled, _loadInvoked;
 BOOL _stopIsLoad, _stopObserved, _overlayWasHidden, _overlayWasInteractive, _loadFrameArmed;
 double _playbackEnd;
 NSUInteger _playbackEpoch, _displayTick, _loadAfterTick;
}
@property(nonatomic,strong) UIView *overlay;
@property(nonatomic,strong) AVPlayer *player;
@property(nonatomic,strong) AVPlayerLayer *video;
@property(nonatomic,strong) CADisplayLink *clock;
@property(nonatomic,strong) NSMutableArray *observers;
@property(nonatomic,strong) id endObserver;
@property(nonatomic,copy) void (^sample)(double);
@property(nonatomic,copy) void (^load)(void (^resume)(BOOL));
@property(nonatomic,copy) void (^completion)(BOOL);
- (instancetype)initWithFrame:(CGRect)frame path:(NSString*)path overlay:(UIView*)overlay
                    duration:(double)duration loadAt:(double)loadAt;
- (void)start;
- (void)pump:(double)delta;
- (void)acceptResume:(BOOL)ok;
- (void)finish:(BOOL)completed;
@end

@implementation PMTransitionMediaView
- (instancetype)initWithFrame:(CGRect)frame path:(NSString*)path overlay:(UIView*)overlay
                    duration:(double)duration loadAt:(double)loadAt {
 if(!(self=[super initWithFrame:frame]))return nil;
 _timeline=PMHeldTransition::Timeline(path!=nil,duration,loadAt);
 self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
 self.backgroundColor=path?UIColor.blackColor:UIColor.clearColor;self.opaque=path!=nil;
 self.userInteractionEnabled=YES;self.accessibilityViewIsModal=YES;
 self.observers=[NSMutableArray new];self.overlay=overlay;
 if(overlay){
  _overlayWasHidden=overlay.hidden;_overlayWasInteractive=overlay.userInteractionEnabled;
  overlay.userInteractionEnabled=NO;overlay.frame=self.bounds;[self addSubview:overlay];
 }
 if(path){
  BOOL directory=NO;
  if(!path.length||![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&directory]||directory)_decodeFailed=YES;
  else {
   self.player=[AVPlayer playerWithURL:[NSURL fileURLWithPath:path]];
   self.player.actionAtItemEnd=AVPlayerActionAtItemEndPause;
   self.video=[AVPlayerLayer playerLayerWithPlayer:self.player];
   self.video.videoGravity=AVLayerVideoGravityResizeAspect;self.video.frame=self.bounds;
   [self.layer insertSublayer:self.video atIndex:0];
  }
 }
 return self;
}
- (void)layoutSubviews {
 [super layoutSubviews];self.overlay.frame=self.bounds;self.video.frame=self.bounds;
}
- (BOOL)owned {return !_finished&&activeMedia==self;}
- (BOOL)foreground {
 UIScene *scene=self.window.windowScene;
 return UIApplication.sharedApplication.applicationState==UIApplicationStateActive&&
        (!scene||scene.activationState==UISceneActivationStateForegroundActive);
}
- (void)suspend {
 if(![self owned])return;
 _timeline.suspended=true;_lastTick=0;self.clock.paused=YES;[self.player pause];
 _loadFrameArmed=NO; // A resumed window must present a fresh held frame first.
}
- (void)activate {
 if(![self owned]||![self foreground])return;
 _timeline.suspended=false;_lastTick=CACurrentMediaTime();self.clock.paused=NO;
 [self pump:0];
 if([self owned]&&!_timeline.failed&&(_timeline.phase==PMHeldTransition::Phase::Playing||
    (_timeline.phase==PMHeldTransition::Phase::Preparing&&_configured&&(!_stopIsLoad||_playbackEnd>0))))
  [self.player play];
}
- (void)configurePlayback {
 if(!self.player)return;
 _timeline.naturalEnd(CMTimeGetSeconds(self.player.currentItem.duration));
 _playbackEnd=_timeline.stop();
 _stopIsLoad=!_timeline.loadRequested&&_timeline.loadAt>=0&&
             (_timeline.end<0||_timeline.loadAt<_timeline.end);
 _stopObserved=NO;
 // A real item end boundary prevents polling cadence from playing past loadAt.
 // At zero, remain paused until the first frame is ready; never play past zero.
 self.player.currentItem.forwardPlaybackEndTime=_playbackEnd>0?
    CMTimeMakeWithSeconds(_playbackEnd,600000):kCMTimeInvalid;
 _configured=YES;
 // Rebind for each playback leg, so even an end notification already queued on
 // main for the previous leg cannot finish the remainder (unknown duration too).
 NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
 if(self.endObserver)[center removeObserver:self.endObserver];
 const NSUInteger epoch=++_playbackEpoch;
 __weak PMTransitionMediaView *weak=self;
 self.endObserver=[center addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
    object:self.player.currentItem queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*n){
     PMTransitionMediaView *view=weak;
     if(view&&view->_playbackEpoch==epoch)[view reachedEnd];
    }];
}
- (void)reachedEnd {
 if(![self owned])return;
 const double position=CMTimeGetSeconds(self.player.currentTime);
 // A queued notification from the old hold boundary is stale after resume.
 if(_playbackEnd>=0&&(!std::isfinite(position)||position+0.002<_playbackEnd))return;
 _stopObserved=YES;[self pump:0];
}
- (void)start {
 if(![self owned])return;
 __weak PMTransitionMediaView *weak=self;
 NSNotificationCenter *center=NSNotificationCenter.defaultCenter;
 if(self.player)[self.observers addObject:[center addObserverForName:AVPlayerItemFailedToPlayToEndTimeNotification
    object:self.player.currentItem queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*n){
     PMTransitionMediaView *view=weak;
     if(view&&[view owned]){view->_decodeFailed=YES;[view pump:0];}
    }]];
 for(NSString *name in @[UIApplicationWillResignActiveNotification,UIApplicationDidEnterBackgroundNotification])
  [self.observers addObject:[center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
     usingBlock:^(NSNotification*n){[weak suspend];}]];
 [self.observers addObject:[center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
    queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*n){[weak activate];}]];
 if(self.window.windowScene){
  [self.observers addObject:[center addObserverForName:UISceneWillDeactivateNotification object:self.window.windowScene
     queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*n){[weak suspend];}]];
  [self.observers addObject:[center addObserverForName:UISceneDidActivateNotification object:self.window.windowScene
     queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*n){[weak activate];}]];
 }
 self.clock=[CADisplayLink displayLinkWithTarget:self selector:@selector(step:)];
 [self.clock addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
 _lastTick=CACurrentMediaTime();[self setNeedsLayout];[self pump:0];
}
- (void)step:(CADisplayLink*)clock {
 ++_displayTick;
 const CFTimeInterval now=CACurrentMediaTime();
 const double delta=_lastTick?MAX(0,now-_lastTick):0;_lastTick=now;
 [self pump:delta];
}
- (void)blackout {
 [self.player pause];self.video.hidden=YES;self.overlay.hidden=YES;
 // Do not reuse the unlock fallback: no cover, unlock message, or Skip control.
 self.backgroundColor=UIColor.blackColor;self.opaque=YES;
 [self layoutIfNeeded];[CATransaction flush];
}
- (void)requestLoad {
 if(_loadInvoked||![self owned]||_timeline.suspended)return;
 if(!_loadFrameArmed){
  // A dispatch_async alone may drain before Core Animation presents this turn.
  // Two subsequent display-link ticks bracket a complete render opportunity even
  // when the hold originated in an end notification, not in a display-link tick.
  _loadFrameArmed=YES;_loadAfterTick=_displayTick+2;
  [self layoutIfNeeded];[CATransaction flush];return;
 }
 if(_displayTick<_loadAfterTick||_loadScheduled)return;
 _loadScheduled=YES;
 __weak PMTransitionMediaView *weak=self;
 // Only after a held-frame render turn, enqueue the potentially synchronous load
 // on main. The same barrier protects the opaque-black decoder fallback.
 dispatch_async(dispatch_get_main_queue(),^{
  PMTransitionMediaView *view=weak;
  if(!view||![view owned])return;
  view->_loadScheduled=NO;
  if(view->_timeline.suspended||![view foreground]){[view suspend];return;}
  if(!view->_loadFrameArmed||view->_displayTick<view->_loadAfterTick)return;
  if(view->_timeline.phase!=PMHeldTransition::Phase::Holding||view->_loadInvoked)return;
  view->_loadInvoked=YES;
  void (^loader)(void (^resume)(BOOL))=view.load;view.load=nil;
  [view layoutIfNeeded];[CATransaction flush];
  void (^resume)(BOOL)=^(BOOL ok){
   // Always enqueue, including synchronous/recursive loaders. The weak owner and
   // one-shot core reject duplicates, old sessions, and callbacks after cancel.
   dispatch_async(dispatch_get_main_queue(),^{[weak acceptResume:ok];});
  };
  if(loader)loader(resume);else resume(YES);
 });
}
- (void)acceptResume:(BOOL)ok {
 if(![self owned]||!_loadInvoked)return;
 if(_timeline.phase!=PMHeldTransition::Phase::Holding||_timeline.resumeReceived)return;
 if(![self foreground])[self suspend];
 if(!_timeline.suspended){
  // A synchronous loader can block the display link. Account for that foreground
  // time before accepting its reply, rather than accidentally resetting its limit.
  const CFTimeInterval now=CACurrentMediaTime();
  const double delta=_lastTick?MAX(0,now-_lastTick):0;_lastTick=now;
  [self pump:delta];if(![self owned])return;
 }
 PMHeldTransition::Phase previous=_timeline.phase;
 PMHeldTransition::Event event=_timeline.resume(ok);
 if(event==PMHeldTransition::Event::Complete){[self finish:_timeline.succeeded];return;}
 if(previous==PMHeldTransition::Phase::Holding&&_timeline.phase==PMHeldTransition::Phase::Playing){
  _lastTick=CACurrentMediaTime();[self configurePlayback];[self.player play];
 }
}
- (void)pump:(double)delta {
 if(![self owned])return;
 if(![self foreground]){[self suspend];return;}
 if(_timeline.suspended)return;
 using namespace PMHeldTransition;
 Phase previous=_timeline.phase;
 const bool wasFailed=_timeline.failed;
 Event event=Event::None;
 if(_decodeFailed||self.player.status==AVPlayerStatusFailed||self.player.currentItem.status==AVPlayerItemStatusFailed){
  _decodeFailed=NO;
  if(!_timeline.failed)event=_timeline.fail();
 }
 if(event!=Event::Complete){
  BOOL ready=!_timeline.video;
  double position=0;
  if(self.player&&!_timeline.failed){
   if(self.player.currentItem.status==AVPlayerItemStatusReadyToPlay&&!_configured){
    [self configurePlayback];
    if(!_stopIsLoad||_playbackEnd>0)[self.player play];
   }
   ready=self.player.currentItem.status==AVPlayerItemStatusReadyToPlay&&self.video.readyForDisplay;
   position=CMTimeGetSeconds(self.player.currentTime);
   if(_stopObserved&&_playbackEnd>=0)position=_playbackEnd;
  }
  if(event==Event::None)event=_timeline.advance(delta,ready,position,_stopObserved&&!_stopIsLoad);
 }
 if(_timeline.failed&&!wasFailed)[self blackout];
 if(_timeline.phase==Phase::Holding)[self.player pause];
 if(previous==Phase::Holding&&_timeline.phase==Phase::Playing){
  [self configurePlayback];[self.player play];
 }
 // Sample the clamped boundary BEFORE load, and the final sample BEFORE finish.
 // A sample is arbitrary client code: it may cancel or start a new presentation.
 if(!_timeline.failed&&previous!=Phase::Holding&&_timeline.phase!=Phase::Preparing){
  void (^sample)(double)=self.sample;
  if(sample)sample(_timeline.time);
  if(![self owned])return;
 }
 if(event==Event::Complete){[self finish:_timeline.succeeded];return;}
 if(_timeline.phase==Phase::Holding)[self requestLoad];
}
- (void)finish:(BOOL)completed {
 if(![self owned])return;
 _finished=YES;_timeline.finish(completed);
 [self.clock invalidate];self.clock=nil;[self.player pause];
 for(id token in self.observers)[NSNotificationCenter.defaultCenter removeObserver:token];
 [self.observers removeAllObjects];self.observers=nil;
 if(self.endObserver)[NSNotificationCenter.defaultCenter removeObserver:self.endObserver];
 self.endObserver=nil;++_playbackEpoch;
 [self.player replaceCurrentItemWithPlayerItem:nil];self.video.player=nil;
 self.player=nil;[self.video removeFromSuperlayer];self.video=nil;
 self.sample=nil;self.load=nil;
 void (^done)(BOOL)=self.completion;self.completion=nil;
 [self.overlay removeFromSuperview];self.overlay.hidden=_overlayWasHidden;
 self.overlay.userInteractionEnabled=_overlayWasInteractive;self.overlay=nil;
 [self removeFromSuperview];activeMedia=nil;
 // Ownership/input/observers are released first: done may cancel or present again.
 if(done)done(completed);
}
@end

BOOL PMPresentTransitionMedia(NSString *path,UIView *overlay,double duration,double loadAt,
                              void (^sample)(double),void (^load)(void (^resume)(BOOL)),
                              void (^completion)(BOOL)) {
 if(!NSThread.isMainThread||activeMedia||!PMHeldTransition::Timeline::valid(duration,loadAt)||
    UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return NO;
 UIWindow *window=nil;
 for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)
  if(scene.activationState==UISceneActivationStateForegroundActive&&[scene isKindOfClass:UIWindowScene.class])
   for(UIWindow *candidate in ((UIWindowScene*)scene).windows)if(candidate.isKeyWindow)window=candidate;
 if(!window||window.rootViewController.presentedViewController||overlay==window||
    (overlay&&[window isDescendantOfView:overlay]))return NO;
 PMTransitionMediaView *view=[[PMTransitionMediaView alloc]initWithFrame:window.bounds path:path overlay:overlay
    duration:duration loadAt:loadAt];
 if(!view)return NO;
 view.sample=sample;view.load=load;view.completion=completion;
 activeMedia=view;[window addSubview:view];[view start];return YES;
}
