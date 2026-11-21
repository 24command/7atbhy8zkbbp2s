#import "PMChapterOS.h"
#import "PMDoorRun.h"
#import "PMStoryCueRun.h"
#import "PMStorySequence.h"
#import "PMStockIntroResolver.hpp"
#import "PMUnlockMedia.h"
#include "PMUnlockRuntime.hpp"
#import "PMOSCheckpoint.h"
#import "PMOSAuthorProgress.h"
#import <CommonCrypto/CommonDigest.h>
#import "PMContentStore.h"
#import "PMChapterScript.h"
#import "PMChapterArt.h"
#import "PMOSMediaView.h"
#import "PMOSSpeechView.h"
#import "PMOSRevealView.h"
#include <cmath>
#import "PMChapterEditing.h"
#import "PMDiagnostics.h"
#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#include "../Core/PMChapterVM.h"
#include <memory>
#include <utility>

static NSOperationQueue *coverQueue(){static NSOperationQueue *q;static dispatch_once_t once;dispatch_once(&once,^{q=[NSOperationQueue new];q.maxConcurrentOperationCount=2;});return q;}
static UIImage *thumb(NSString *path,NSInteger pixels){CGImageSourceRef src=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],NULL);if(!src)return nil;CGImageRef cg=CGImageSourceCreateThumbnailAtIndex(src,0,(__bridge CFDictionaryRef)@{(__bridge NSString*)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge NSString*)kCGImageSourceCreateThumbnailWithTransform:@YES,(__bridge NSString*)kCGImageSourceThumbnailMaxPixelSize:@(pixels)});CFRelease(src);if(!cg)return nil;UIImage *result=[UIImage imageWithCGImage:cg];CGImageRelease(cg);return result;}
#include "PMChapterCanvas.inc"
@interface PMOSCell:UICollectionViewCell
@property(nonatomic,strong) UIImageView *image;
@property(nonatomic,strong) UILabel *name;
@property(nonatomic,strong) NSOperation *task;
@property(nonatomic,copy) NSString *path;
@end
@implementation PMOSCell
- (instancetype)initWithFrame:(CGRect)frame{if((self=[super initWithFrame:frame])){self.backgroundColor=[UIColor colorWithWhite:.16 alpha:1];self.image=[UIImageView new];self.image.clipsToBounds=YES;self.image.contentMode=UIViewContentModeScaleAspectFill;self.name=[UILabel new];self.name.textAlignment=NSTextAlignmentCenter;self.name.textColor=UIColor.whiteColor;self.name.backgroundColor=[UIColor colorWithWhite:0 alpha:.7];self.name.adjustsFontSizeToFitWidth=YES;self.name.minimumScaleFactor=.6;[self.contentView addSubview:self.image];[self.contentView addSubview:self.name];self.isAccessibilityElement=YES;self.accessibilityTraits=UIAccessibilityTraitButton;}return self;}
- (void)layoutSubviews{[super layoutSubviews];CGFloat w=self.bounds.size.width,h=self.bounds.size.height,k=w*.08;self.image.frame=self.bounds;self.name.frame=CGRectMake(k,h-40,w-2*k,36);UIBezierPath *p=[UIBezierPath bezierPath];[p moveToPoint:CGPointMake(k,0)];[p addLineToPoint:CGPointMake(w,0)];[p addLineToPoint:CGPointMake(w-k,h)];[p addLineToPoint:CGPointMake(0,h)];[p closePath];CAShapeLayer *mask=[CAShapeLayer layer];mask.path=p.CGPath;self.layer.mask=mask;}
- (void)prepareForReuse{[super prepareForReuse];[self.task cancel];self.task=nil;self.path=nil;self.image.image=nil;}
@end
@interface PMOSView : UIView <UICollectionViewDataSource,UICollectionViewDelegateFlowLayout>
@property(nonatomic,copy) NSArray<NSDictionary*> *cards;
@property(nonatomic,copy) BOOL (^selectSong)(NSString*);
@property(nonatomic,copy) BOOL (^startChallenge)(NSDictionary*);
@property(nonatomic,strong) UIButton *toggle,*back,*choose;
@property(nonatomic,strong) UICollectionView *table;
@property(nonatomic,strong) NSCache *thumbs;
@property(nonatomic,strong) UILabel *heading;
@property(nonatomic,strong) UITextView *caption;
@property(nonatomic,strong) PMOSSpeechView *speech;
@property(nonatomic,strong) UIImageView *art;
@property(nonatomic,strong) NSDictionary *detail;
@property(nonatomic,copy) NSString *chapterName;
@property(nonatomic) BOOL opened;
@property(nonatomic) BOOL ownsIntro;
@property(nonatomic,strong) PMChapterCanvas *canvas;
@property(nonatomic) CGFloat aspect;
- (void)showSong:(NSDictionary*)song;
- (void)showDetail:(NSDictionary*)song;
- (void)interruptForCheckpoint:(NSDictionary*)record relaunch:(BOOL)relaunch resume:(BOOL (^)(void))resume;
@end
static PMOSView *active;
static NSDictionary *bootTarget;
static NSString *attemptedToken;

static int readStoryFlag(void *context,const char *key,int *value) {
 PMOSAuthorProgress *progress=(__bridge PMOSAuthorProgress *)context;
 return [progress readKey:[NSString stringWithUTF8String:key] value:value];
}
static int commitStoryFlags(void *context,const PMOSProgressChange *changes,size_t count) {
 PMOSAuthorProgress *progress=(__bridge PMOSAuthorProgress *)context;
 NSMutableDictionary *values=[NSMutableDictionary dictionaryWithCapacity:count];
 for(size_t i=0;i<count;++i)values[[NSString stringWithUTF8String:changes[i].key]]=@(changes[i].value);
 return [progress commitValues:values];
}

static NSString *scriptDigest(NSData *data) {
 unsigned char digest[CC_SHA256_DIGEST_LENGTH];
 CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
 NSMutableString *hex=[NSMutableString stringWithCapacity:64];
 for(unsigned char byte:digest)[hex appendFormat:@"%02x",byte];
 return hex;
}

void PMChapterOSResumeAfterBoot(BOOL (^available)(NSString *), BOOL (^navigate)(NSString *)) {
 if(PMStorySequenceRoute(available,navigate))return;
 NSDictionary *record=PMOSPendingCheckpoint();
 if(!record||[attemptedToken isEqual:record[@"token"]])return;
 NSString *chapter=record[@"chapter"];
 attemptedToken=record[@"token"];
 if(![PMContentStore.shared hasChapterScript:chapter]){
  PMOSClearCheckpoint(attemptedToken);
  PMDiagnosticsWrite("Chapter OS resume discarded: chapter or script removed");return;
 }
 NSString *path=[[PMContentStore.shared asset:chapter] stringByAppendingPathComponent:PMChapterScriptName];
 NSData *source=PMChapterScriptData([NSURL fileURLWithPath:path],nil);
 if(!source||![record[@"scriptHash"] isEqual:scriptDigest(source)]){
  PMOSClearCheckpoint(attemptedToken);
  PMDiagnosticsWrite("Chapter OS resume discarded: script changed");return;
 }
 if(!available(chapter)){PMDiagnosticsWrite("Chapter OS resume deferred: chapter unavailable");return;}
 bootTarget=record;
 if(!navigate(chapter)){bootTarget=nil;PMDiagnosticsWrite("Chapter OS resume deferred: navigation unavailable");}
}
static NSUInteger generation;
static UIView *hostView(){for(UIScene *s in UIApplication.sharedApplication.connectedScenes)if(s.activationState==UISceneActivationStateForegroundActive && [s isKindOfClass:UIWindowScene.class])for(UIWindow *w in ((UIWindowScene*)s).windows)if(!w.hidden&&w.windowLevel==UIWindowLevelNormal&&w.rootViewController.view.window==w)return w.rootViewController.view;return nil;}
static UIButton *control(NSString *title,id target,SEL action){UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];[b setTitle:title forState:UIControlStateNormal];b.backgroundColor=UIColor.whiteColor;b.tintColor=UIColor.blackColor;[b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];return b;}
@implementation PMOSView
- (UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)event{UIView *hit=[super hitTest:p withEvent:event];return !self.opened&&hit==self?nil:hit;}
- (instancetype)initWithFrame:(CGRect)frame{if((self=[super initWithFrame:frame])){
 self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
 UICollectionViewFlowLayout *flow=[UICollectionViewFlowLayout new];flow.scrollDirection=UICollectionViewScrollDirectionHorizontal;flow.minimumLineSpacing=12;self.table=[[UICollectionView alloc]initWithFrame:CGRectZero collectionViewLayout:flow];[self.table registerClass:PMOSCell.class forCellWithReuseIdentifier:@"os"];self.table.backgroundColor=UIColor.clearColor;self.thumbs=[NSCache new];self.thumbs.countLimit=24;self.table.delegate=self;self.table.dataSource=self;
 self.heading=[UILabel new];self.heading.textColor=UIColor.whiteColor;self.heading.font=[UIFont systemFontOfSize:22 weight:UIFontWeightMedium];self.heading.adjustsFontSizeToFitWidth=YES;self.heading.minimumScaleFactor=.65;
 self.caption=[UITextView new];self.caption.backgroundColor=UIColor.clearColor;self.caption.textColor=UIColor.whiteColor;self.caption.editable=NO;self.caption.font=[UIFont systemFontOfSize:16];
 self.art=[UIImageView new];self.art.contentMode=UIViewContentModeScaleAspectFit;
 self.toggle=control(@"OS",self,@selector(toggleOS));self.back=control(@"←",self,@selector(closeDetail));self.choose=control(@"在普通选曲中选择",self,@selector(chooseSong));
 for(UIView *v in @[self.table,self.heading,self.caption,self.art,self.back,self.choose,self.toggle])[self addSubview:v];
 }return self;}
- (void)layoutSubviews{[super layoutSubviews];CGRect s=UIEdgeInsetsInsetRect(self.bounds,self.safeAreaInsets);CGFloat x=CGRectGetMinX(s),y=CGRectGetMinY(s),w=s.size.width,h=s.size.height;
 if(self.canvas){CGRect area=CGRectMake(x,y,w,MAX(1,h-52));if(self.aspect>0){CGFloat cw=MIN(w,area.size.height*self.aspect),ch=cw/self.aspect;area=CGRectInset(area,(w-cw)*.5,(area.size.height-ch)*.5);}self.canvas.frame=area;}
 self.toggle.frame=self.opened?CGRectMake(x+w*.5-50,y+h-46,100,42):CGRectMake(x+w*.54,y+4,60,42);
 self.back.frame=CGRectMake(x+12,y+8,52,42);self.heading.frame=CGRectMake(x+78,y+6,MAX(60,w-106),46);
 CGFloat cardHeight=MAX(1,MIN(MIN(420.,(w-32)*.62)/1.7,h-114));self.table.frame=CGRectMake(x+16,y+(h-cardHeight)*.5,w-32,cardHeight);self.caption.frame=CGRectMake(x+24,y+62,w*.44,MAX(60,h-132));self.speech.frame=self.caption.frame;self.art.frame=CGRectMake(x+w*.5,y+58,w*.48,MAX(60,h-128));self.choose.frame=CGRectMake(x+w-168,y+h-52,156,44);
}
- (void)refresh{BOOL detail=self.detail!=nil;self.backgroundColor=self.opened?[UIColor colorWithWhite:.075 alpha:1]:UIColor.clearColor;
 self.canvas.hidden=!self.opened||detail;self.table.hidden=!self.opened||detail||self.canvas!=nil;self.heading.hidden=!self.opened||(!detail&&self.canvas!=nil);self.back.hidden=self.caption.hidden=self.art.hidden=self.choose.hidden=!self.opened||!detail;
 [self.choose setTitle:self.detail[@"challengeID"]?@"开始挑战":@"在普通选曲中选择" forState:UIControlStateNormal];self.heading.text=detail?self.detail[@"title"]:self.chapterName;self.caption.text=self.detail[@"caption"];self.caption.hidden=self.caption.hidden||self.speech!=nil;self.speech.hidden=!self.opened||!detail;[self.toggle setTitle:self.opened?@"普通选曲":@"OS" forState:UIControlStateNormal];[self setNeedsLayout];}
- (void)toggleOS{[self.speech removeFromSuperview];self.speech=nil;self.opened=!self.opened;self.detail=nil;self.art.image=nil;[self refresh];}
- (void)closeDetail{[self.speech removeFromSuperview];self.speech=nil;self.detail=nil;self.art.image=nil;[self refresh];}
- (void)interruptForCheckpoint:(NSDictionary*)record relaunch:(BOOL)relaunch resume:(BOOL (^)(void))resume {
 NSError *error=nil;
 if(relaunch&&!PMOSSaveCheckpoint(record,&error)){PMDiagnosticsWrite(error.localizedDescription.UTF8String?:"Chapter OS checkpoint write failed");return;}
 UIView *panel=[[UIView alloc]initWithFrame:self.bounds];panel.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;panel.backgroundColor=UIColor.blackColor;
 self.canvas.hidden=YES;[self addSubview:panel];
 UILabel *message=[UILabel new];message.textColor=UIColor.whiteColor;message.numberOfLines=0;message.textAlignment=NSTextAlignmentCenter;
 message.text=relaunch?@"章节连接已中断。重新打开游戏可继续。":@"章节连接已中断。";
 UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];[button setTitle:relaunch?@"暂时返回普通选曲":@"重新连接" forState:UIControlStateNormal];button.tintColor=UIColor.whiteColor;
 UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[message,button]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=16;stack.translatesAutoresizingMaskIntoConstraints=NO;[panel addSubview:stack];
 [NSLayoutConstraint activateConstraints:@[[stack.centerXAnchor constraintEqualToAnchor:panel.centerXAnchor],[stack.centerYAnchor constraintEqualToAnchor:panel.centerYAnchor],[stack.widthAnchor constraintLessThanOrEqualToAnchor:panel.widthAnchor multiplier:.9]]];
 __weak UIView *weakPanel=panel;__weak PMOSView *weakOwner=self;
 [button addAction:[UIAction actionWithHandler:^(UIAction *action){PMOSView *owner=weakOwner;if(!owner||owner!=active)return;
  [weakPanel removeFromSuperview];[owner refresh];if(relaunch){[owner toggleOS];return;}
  if(!resume()&&owner.opened){PMDiagnosticsWrite("Chapter OS session checkpoint target unavailable");[owner toggleOS];}
 }] forControlEvents:UIControlEventTouchUpInside];
}
- (void)chooseSong{if(self.detail[@"challengeID"]){if(!self.startChallenge(self.detail)){[self.choose setTitle:@"当前无法挑战" forState:UIControlStateNormal];}return;}if(self.selectSong&&self.selectSong(self.detail[@"group"]))[self toggleOS];else self.caption.text=@"当前选曲列表中没有此曲目。";}
- (NSInteger)collectionView:(UICollectionView*)v numberOfItemsInSection:(NSInteger)s{return self.cards.count;}
- (CGSize)collectionView:(UICollectionView*)v layout:(UICollectionViewLayout*)layout sizeForItemAtIndexPath:(NSIndexPath*)p{CGFloat w=MIN(v.bounds.size.width*.62,MIN(420.,v.bounds.size.height*1.7));return CGSizeMake(MAX(1,w),MAX(1,w/1.7));}
- (UICollectionViewCell*)collectionView:(UICollectionView*)v cellForItemAtIndexPath:(NSIndexPath*)p{PMOSCell *cell=[v dequeueReusableCellWithReuseIdentifier:@"os" forIndexPath:p];NSDictionary *row=self.cards[p.item];BOOL locked=[row[@"lockedChallenge"] boolValue];cell.contentView.alpha=locked?.55:1;cell.accessibilityTraits=UIAccessibilityTraitButton|(locked?UIAccessibilityTraitNotEnabled:0);cell.name.text=row[@"title"];cell.accessibilityLabel=cell.name.text;NSString *path=row[@"art"];cell.path=path;cell.image.image=path?[self.thumbs objectForKey:path]:nil;
 if(path&&!cell.image.image){__weak PMOSCell *weakCell=cell;__weak PMOSView *weakOwner=self;cell.task=[NSBlockOperation blockOperationWithBlock:^{UIImage *image=thumb(path,384);dispatch_async(dispatch_get_main_queue(),^{PMOSCell *c=weakCell;PMOSView *owner=weakOwner;if(!owner||owner!=active||!image)return;[owner.thumbs setObject:image forKey:path];if([c.path isEqual:path])c.image.image=image;});}];[coverQueue() addOperation:cell.task];}return cell;}
- (void)collectionView:(UICollectionView*)v didSelectItemAtIndexPath:(NSIndexPath*)p{NSDictionary *card=self.cards[p.row];if(![card[@"lockedChallenge"] boolValue])[self showSong:card[@"challengeDetail"]?:card];}
- (void)presentChallenge:(NSDictionary*)card index:(NSUInteger)index {
 if(active!=self)return;
 NSArray *intro=card[@"intro"];
 if(index==intro.count){
  self.canvas.hidden=YES;
  if(![card[@"showDetail"] boolValue] && self.startChallenge(card))return;
  [self showDetail:card];return;
 }
 __weak PMOSView *weakOwner=self;
 self.canvas.hidden=YES;self.ownsIntro=YES;
 BOOL shown=pmunlock::playChapterStoryMedia(intro[index],card[@"art"],card[@"title"],^(BOOL completed){
  PMOSView *owner=weakOwner;if(!owner)return;owner.ownsIntro=NO;
  dispatch_async(dispatch_get_main_queue(),^{if(active!=owner)return;
   if(completed)[owner presentChallenge:card index:index+1];else [owner refresh];});
 });
 if(!shown){self.ownsIntro=NO;[self refresh];PMDiagnosticsWrite("Chapter OS intro unavailable");}
}
- (void)showSong:(NSDictionary*)card {
 if(self.ownsIntro)return;
 if(card[@"challengeID"]){[self presentChallenge:card index:0];return;}
 [self showDetail:card];
}
- (void)showDetail:(NSDictionary*)card{self.art.image=nil;self.detail=card;[self.speech removeFromSuperview];self.speech=nil;if(card[@"seconds"]){self.speech=[[PMOSSpeechView alloc] initWithSeconds:[card[@"seconds"] doubleValue] heading:card[@"speechHeading"] transcript:card[@"caption"]];[self insertSubview:self.speech belowSubview:self.toggle];}[UIView transitionWithView:self duration:.2 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{[self refresh];} completion:nil];NSString *path=card[@"art"];if(!path)return;
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{UIImage *image=thumb(path,768);dispatch_async(dispatch_get_main_queue(),^{if(active==self&&self.detail==card)self.art.image=image;});});}
@end
BOOL PMChapterOSVisible(){return active.opened;}
void PMCloseChapterOS(){++generation;PMOSView *previous=active;active=nil;if(previous)[coverQueue() cancelAllOperations];if(previous.ownsIntro)PMCancelUnlockMedia();[previous removeFromSuperview];}
void PMOpenChapterOS(NSString *chapter,BOOL (^selectSong)(NSString *),BOOL (^startSong)(NSString *,NSString *,BOOL (^)(NSString *,int,NSString *))){
 if(PMStorySequenceSelectorReady(chapter,startSong))return;
 NSDictionary *resume=[bootTarget[@"chapter"] isEqual:chapter]?bootTarget:nil;
 bootTarget=nil;
 PMContentStore *store=PMContentStore.shared;if(![store hasChapterScript:chapter])return;
 NSUInteger token=generation;NSString *file=[[store asset:chapter] stringByAppendingPathComponent:PMChapterScriptName];
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
 PMDoorProgressBarrier();
 NSError *err=nil;NSData *source=PMChapterScriptData([NSURL fileURLWithPath:file],&err);NSDictionary *db=[store snapshot];NSArray *order=PMChapterSongIDs(db,nil,chapter);auto plan=std::make_unique<PMOSPage>();
 PMOSAuthorProgress *progress=[[PMOSAuthorProgress alloc] initWithRoot:store.root chapter:chapter];
 PMOSProgress callbacks={(__bridge void*)progress,readStoryFlag,commitStoryFlags};
 auto *raw=source?PMOSStartWithProgress((const char*)source.bytes,source.length,(int)order.count,plan.get(),callbacks):nullptr;
 std::shared_ptr<PMOSSession> session(raw,[progress](PMOSSession *vm){(void)progress;if(vm)PMOSStop(vm);});
 if(!session){if(resume)PMOSClearCheckpoint(resume[@"token"]);PMDiagnosticsWrite([[NSString stringWithFormat:@"Chapter OS %@: %@",chapter,err.localizedDescription?:[NSString stringWithUTF8String:plan->error]] UTF8String]);return;}
 NSString *digest=scriptDigest(source);
 NSMutableArray<NSString*> *screens=[NSMutableArray arrayWithCapacity:plan->screens];
 for(int i=0;i<plan->screens;++i){NSString *name=[NSString stringWithUTF8String:plan->names[i]];if(!name){PMDiagnosticsWrite("Chapter OS invalid UTF-8 page name");return;}[screens addObject:name];}
 NSMutableDictionary *songs=[NSMutableDictionary dictionary];for(NSDictionary *song in db[@"songs"])songs[song[@"id"]]=song;
 NSString *name=chapter;for(NSDictionary *c in db[@"chapters"])if([c[@"id"] isEqual:chapter]){name=c[@"name"];break;}
 NSMutableDictionary *bySong=[NSMutableDictionary dictionary];
 for(NSString *sid in order){NSDictionary *song=songs[sid];NSMutableDictionary *row=[@{@"title":song[@"title"]?:sid,@"group":[song[@"groupId"] length]?song[@"groupId"]:sid,@"caption":song[@"composer"]?:@""} mutableCopy];if(song&&![song[@"unlock"][@"enabled"] boolValue])row[@"art"]=[[store asset:sid] stringByAppendingPathComponent:@"image.png"];bySong[sid]=row;}
 NSMutableArray *cards=[NSMutableArray array];NSMutableSet *overridden=[NSMutableSet set];
 for(NSUInteger i=0,n=plan->count?(NSUInteger)plan->count:order.count;i<n;i++){
  const PMOSCard *c=plan->count?&plan->cards[i]:nullptr;NSString *sid=order[c?c->song-1:i];NSMutableDictionary *row=[bySong[sid] mutableCopy];
  if(c&&c->title[0])row[@"title"]=[NSString stringWithUTF8String:c->title]?:sid;if(c&&c->caption[0])row[@"caption"]=[NSString stringWithUTF8String:c->caption]?:@"";if(c&&c->speech){row[@"seconds"]=@(c->seconds);row[@"speechHeading"]=(c->speechHeading[0]?[NSString stringWithUTF8String:c->speechHeading]:nil)?:@"SPEECH_TO_TEXT";}[cards addObject:row];}
 for(int i=0;i<plan->count;i++){NSString *sid=order[plan->cards[i].song-1];if(![overridden containsObject:sid]){bySong[sid]=cards[i];[overridden addObject:sid];}}
 NSString *chapterDir=file.stringByDeletingLastPathComponent;
 NSMutableArray *challengeRows=[NSMutableArray arrayWithCapacity:plan->challengeCount];
 for(int i=0;i<plan->challengeCount;i++){
  const PMOSChallenge &challenge=plan->challenges[i];const PMOSChallengeTier *tier=&challenge.tiers[0];
  for(int j=1;j<challenge.tierCount && challenge.tiers[j].after<=challenge.failures;++j)tier=&challenge.tiers[j];
  NSString *sid=order[challenge.song-1];NSMutableDictionary *row=[bySong[sid] mutableCopy];
  row[@"challengeID"]=[NSString stringWithUTF8String:challenge.id];row[@"sid"]=sid;row[@"hp"]=@(tier->hp);
  row[@"delta"]=@[@(tier->perfect),@(tier->good),@(tier->bad),@(tier->miss)];
  if(challenge.difficulty[0])row[@"difficulty"]=[NSString stringWithUTF8String:challenge.difficulty];
  row[@"showDetail"]=@(challenge.showDetail!=0);
  NSMutableArray *intro=[NSMutableArray array];
  for(int j=0;j<challenge.introCount;j++){
   NSString *name=[NSString stringWithUTF8String:challenge.intro[j]];
   NSString *path=[name hasPrefix:@"@stock/"]?PMResolveStockIntro(name):PMOSArtPath(chapterDir,name);
   if(!path||![[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFileType] isEqual:NSFileTypeRegular]){
    PMDiagnosticsWrite("Chapter OS intro file missing");return;
   }
   [intro addObject:path];
  }
  row[@"intro"]=intro;
  NSMutableArray *nextSongs=[NSMutableArray array];
  for(int j=0;j<challenge.nextSongCount;j++){
   const PMOSChallengeSong &next=challenge.nextSongs[j];
   NSMutableDictionary *entry=[@{@"songID":order[next.song-1]} mutableCopy];
   if(next.difficulty[0])entry[@"difficulty"]=[NSString stringWithUTF8String:next.difficulty];
   [nextSongs addObject:entry];
  }
  row[@"nextSongs"]=nextSongs;
  if(challenge.cueCount){
   NSMutableArray *cues=[NSMutableArray arrayWithCapacity:challenge.cueCount];
   for(int j=0;j<challenge.cueCount;j++){
    const auto &cue=plan->cues[challenge.cueStart+j];
    [cues addObject:@{@"at":@(cue.at),@"duration":@(cue.duration),@"blockPause":@(cue.blockPause!=0),
                      @"text":[NSString stringWithUTF8String:cue.text]?:@"",@"src":[NSString stringWithUTF8String:cue.src]?:@""}];
   }
   row[@"cues"]=PMStoryCuePrepare(cues,chapterDir);
  }
  [challengeRows addObject:row];
 }
 for(int i=0;i<plan->count;i++){
  int binding=plan->cards[i].challenge;
  if(binding<=0)continue;
  NSMutableDictionary *card=[cards[i] mutableCopy];
  if(plan->challenges[binding-1].state==PMOSChallengeLocked)card[@"lockedChallenge"]=@YES;
  else {
   NSDictionary *target=challengeRows[binding-1];
   NSMutableDictionary *detail=[target mutableCopy];
   if(plan->cards[i].song==plan->challenges[binding-1].song){
    for(NSString *key in @[@"title",@"caption",@"speechHeading",@"seconds"])if(card[key])detail[key]=card[key];
   }
   card[@"challengeDetail"]=detail;
  }
  cards[i]=card;
 }
 NSMutableArray *nodes=[NSMutableArray new];
 for(int i=0;i<plan->nodes;i++){const PMOSNode &n=plan->elements[i];NSMutableDictionary *model=[@{@"parent":@(n.parent),@"screen":@(n.screen),@"kind":@(n.kind),@"dest":@(n.dest),@"rect":[NSValue valueWithCGRect:CGRectMake(n.x,n.y,n.w,n.h)],@"rgba":@(n.rgba),@"fill":@(n.fill),@"loop":@(n.loop),@"handler":@(n.handler!=0),@"hidden":@(n.hidden),@"start":@(n.start),@"duration":@(n.duration),@"fade":@(n.fade)} mutableCopy];
  if(n.label[0])model[@"label"]=[NSString stringWithUTF8String:n.label];if(n.to[0])model[@"to"]=[NSString stringWithUTF8String:n.to];
  if(n.open)model[@"song"]=bySong[order[n.open-1]];
  if(n.dropIndex>=0){model[@"dropIndex"]=@(n.dropIndex);model[@"alphaHit"]=@(n.alphaHit!=0);}
  if(n.cover)model[@"path"]=bySong[order[n.cover-1]][@"art"];
  if(n.src[0]){NSString *path=PMOSArtPath(chapterDir,[NSString stringWithUTF8String:n.src]);if(!path||![[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFileType] isEqual:NSFileTypeRegular]){if(resume)PMOSClearCheckpoint(resume[@"token"]);PMDiagnosticsWrite([[NSString stringWithFormat:@"Chapter OS %@: missing or invalid image %s",chapter,n.src] UTF8String]);return;}model[@"path"]=path;}
  [nodes addObject:model];
 }
 CGFloat aspect=plan->aspect;BOOL opened=!plan->listFirst;dispatch_async(dispatch_get_main_queue(),^{if(token!=generation)return;UIView *host=hostView();if(!host)return;
 active=[[PMOSView alloc]initWithFrame:host.bounds];active.cards=cards;active.chapterName=name;active.selectSong=selectSong;
 active.startChallenge=^BOOL(NSDictionary *row){return startSong(row[@"sid"],row[@"difficulty"],^BOOL(NSString *group,int slot,NSString *chart){
  if(!PMDoorArm(chapter,row[@"challengeID"],group,slot,chart,[row[@"hp"] doubleValue],row[@"delta"]))return NO;
  if(!PMStorySequenceArm(chapter,row[@"nextSongs"])){PMDoorCancelPending();return NO;}
  PMStoryCueArm(row[@"cues"]);
  return YES;
 });};active.opened=opened;if(nodes.count){active.aspect=aspect;PMChapterCanvas *canvas=[PMChapterCanvas new];canvas.clipsToBounds=YES;canvas.nodes=nodes;__weak PMOSView *owner=active;canvas.openSong=^(NSDictionary *song){[owner showSong:song];};__weak PMChapterCanvas *weakCanvas=canvas;
  dispatch_queue_t events=dispatch_queue_create("PhiMod.ChapterOS.events",DISPATCH_QUEUE_SERIAL);
  canvas.runHandler=^(NSInteger index){PMChapterCanvas *v=weakCanvas;if(!v||v.pending)return;v.pending=YES;NSUInteger visit=v.visit, revealEpoch=v.revealEpoch;
   dispatch_async(events,^{PMOSAction result={};BOOL ok=PMOSClick(session.get(),(int)index,&result);NSString *why=ok?nil:[NSString stringWithUTF8String:result.error];NSInteger song=result.song,page=result.dest,element=result.element;BOOL visible=result.visible;int checkpoint=result.checkpoint,challengeIndex=result.challenge;
    NSString *revealTitle = result.revealTitle[0] ? [NSString stringWithUTF8String:result.revealTitle] : nil;
    NSString *revealText = revealTitle ? [NSString stringWithUTF8String:result.revealText] : nil;
    NSString *difficulty=result.difficulty[0]?[NSString stringWithUTF8String:result.difficulty]:nil;
    dispatch_async(dispatch_get_main_queue(),^{PMChapterCanvas *view=weakCanvas;if(!view||active!=owner||generation!=token||view.visit!=visit)return;view.pending=NO;
     if(!ok){PMDiagnosticsWrite([[NSString stringWithFormat:@"Chapter OS click %@: %@",chapter,why] UTF8String]);PMCloseChapterOS();return;}
     if (revealTitle) {
      PMOSView *host = owner;
      if (!host || !view.window || view.hidden || view.reveal || view.revealEpoch != revealEpoch ||
          UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
      [host layoutIfNeeded];
      UIView *source = [view revealAnchorAtIndex:index];
      UIView *target = [view revealAnchorAtIndex:element];
      if (!source || !target) return;
      NSString *sid = song ? order[song-1] : nil;
      PMOSRevealView *popup = [[PMOSRevealView alloc] initWithTitle:revealTitle text:revealText hasSong:sid != nil];
      view.pending = YES;
      view.reveal = popup;
      [view syncClock];
      popup.frame = host.bounds;
      [host addSubview:popup];
      [popup focusFrom:source to:target completion:^(PMOSRevealChoice choice) {
       PMChapterCanvas *canvas = weakCanvas;
       if (!canvas || canvas.visit != visit || generation != token || active != owner) return;
       canvas.reveal = nil;
       canvas.pending = NO;
       [canvas syncClock];
       if (choice == PMOSRevealResume || !sid) return;
       if (choice == PMOSRevealStart && startSong && startSong(sid, nil, nil)) return;
       if (active == owner && generation == token) [owner showSong:bySong[sid]];
      }];
      return;
     }
     if(challengeIndex>0&&challengeIndex<=(int)challengeRows.count){[owner showSong:challengeRows[challengeIndex-1]];return;}
     if(checkpoint){
      NSMutableDictionary *record=[@{@"token":NSUUID.UUID.UUIDString,@"chapter":chapter,@"scriptHash":digest} mutableCopy];
      if(song>0&&song<=(NSInteger)order.count){record[@"songID"]=order[song-1];if(difficulty)record[@"difficulty"]=difficulty;}
      else if(page>=0&&page<(NSInteger)screens.count)record[@"page"]=screens[page];else return;
      [owner interruptForCheckpoint:record relaunch:checkpoint==2 resume:^BOOL{
       if(record[@"page"]){[view displayPage:page];return YES;}
       return (BOOL)startSong(record[@"songID"],difficulty,nil);
      }];return;
     }
     if(song>0&&song<=(NSInteger)order.count)[owner showSong:bySong[order[song-1]]];else if(page>=0)[view displayPage:page];else if(element>=0)[view setElement:element visible:visible];});});};
  active.canvas=canvas;[active insertSubview:canvas atIndex:0];canvas.hidden=!opened;[canvas displayPage:0];}[active refresh];[host addSubview:active];
 if(resume){
  BOOL exact=[digest isEqual:resume[@"scriptHash"]];BOOL applied=NO;
  if(exact&&resume[@"page"]){NSUInteger index=[screens indexOfObject:resume[@"page"]];if(index!=NSNotFound&&active.canvas){active.opened=YES;[active.canvas displayPage:index];[active refresh];applied=YES;}}
  else if(exact&&bySong[resume[@"songID"]])applied=startSong(resume[@"songID"],resume[@"difficulty"],nil);
  PMOSClearCheckpoint(resume[@"token"]);
  if(!applied){PMDiagnosticsWrite("Chapter OS resume: target changed or inaccessible");if(active.opened)[active toggleOS];}
 }
 });
 }});
}
