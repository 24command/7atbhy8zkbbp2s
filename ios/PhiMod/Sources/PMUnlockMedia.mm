#import "PMUnlockMedia.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#include <cmath>

@interface PMUnlockMediaView : UIView
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
static PMUnlockMediaView *activeMedia;
@implementation PMUnlockMediaView
- (void)layoutSubviews{[super layoutSubviews];self.image.frame=self.bounds;self.video.frame=self.bounds;self.message.frame=CGRectInset(self.bounds,40,80);UIView*skip=[self viewWithTag:101];skip.frame=CGRectMake(MAX(12,self.bounds.size.width-132),MAX(12,self.safeAreaInsets.top+8),112,44);}
- (void)showFallback{
 self.fallback=YES;self.began=CACurrentMediaTime();[self.player pause];[self.video removeFromSuperlayer];self.video=nil;
 self.image.image=[UIImage imageWithContentsOfFile:self.cover];self.image.hidden=NO;
 self.message.text=@"Unlocked — tap Skip to continue";self.message.hidden=NO;
}
- (void)skip{[self finish:YES];}
- (void)step:(CADisplayLink*)clock{
 if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){[self finish:NO];return;}
 if(self.fallback){if(clock.timestamp-self.began>.75)[self finish:YES];return;}
 if(self.gif){
  double elapsed=clock.timestamp-self.began;if(elapsed>=[self.ends.lastObject doubleValue]){[self finish:YES];return;}
  NSUInteger i=0;while(i+1<self.ends.count&&elapsed>=[self.ends[i] doubleValue])++i;
  if(i!=self.lastFrame){CGImageRef frame=CGImageSourceCreateImageAtIndex(self.gif,i,NULL);if(!frame){[self showFallback];return;}self.image.image=[UIImage imageWithCGImage:frame];CGImageRelease(frame);self.lastFrame=i;}
 }else if(self.player){
  if(self.player.status==AVPlayerStatusFailed||self.player.currentItem.status==AVPlayerItemStatusFailed){[self showFallback];return;}
  if(self.player.currentItem.status==AVPlayerItemStatusReadyToPlay&&!self.began){self.began=clock.timestamp;[self.player play];}
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
void PMCancelUnlockMedia(void){[activeMedia finish:NO];}
BOOL PMPresentUnlockMedia(NSString*path,NSString*cover,NSString*title,void(^completion)(BOOL)){
 if(!NSThread.isMainThread||activeMedia||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return NO;
 UIWindow*window=nil;for(UIScene*scene in UIApplication.sharedApplication.connectedScenes)if(scene.activationState==UISceneActivationStateForegroundActive&&[scene isKindOfClass:UIWindowScene.class])for(UIWindow*w in ((UIWindowScene*)scene).windows)if(w.isKeyWindow)window=w;
 if(!window||window.rootViewController.presentedViewController)return NO;
 PMUnlockMediaView*v=[[PMUnlockMediaView alloc]initWithFrame:window.bounds];v.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;v.backgroundColor=UIColor.blackColor;v.accessibilityViewIsModal=YES;v.completion=completion;v.cover=cover;v.created=CACurrentMediaTime();v.lastFrame=NSNotFound;
 v.image=[UIImageView new];v.image.contentMode=UIViewContentModeScaleAspectFit;[v addSubview:v.image];
 v.message=[UILabel new];v.message.text=title;v.message.textAlignment=NSTextAlignmentCenter;v.message.textColor=UIColor.whiteColor;v.message.numberOfLines=0;v.message.hidden=YES;[v addSubview:v.message];
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
