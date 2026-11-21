#import "PMChapterOS.h"
#import "PMContentStore.h"
#import "PMChapterScript.h"
#import "PMChapterEditing.h"
#import "PMDiagnostics.h"
#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#include "../Core/PMChapterVM.h"
#include <memory>

static NSOperationQueue *coverQueue(){static NSOperationQueue *q;static dispatch_once_t once;dispatch_once(&once,^{q=[NSOperationQueue new];q.maxConcurrentOperationCount=2;});return q;}
static UIImage *thumb(NSString *path,NSInteger pixels){CGImageSourceRef src=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],NULL);if(!src)return nil;CGImageRef cg=CGImageSourceCreateThumbnailAtIndex(src,0,(__bridge CFDictionaryRef)@{(__bridge NSString*)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge NSString*)kCGImageSourceCreateThumbnailWithTransform:@YES,(__bridge NSString*)kCGImageSourceThumbnailMaxPixelSize:@(pixels)});CFRelease(src);if(!cg)return nil;UIImage *result=[UIImage imageWithCGImage:cg];CGImageRelease(cg);return result;}
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
@property(nonatomic,strong) UIButton *toggle,*back,*choose;
@property(nonatomic,strong) UICollectionView *table;
@property(nonatomic,strong) NSCache *thumbs;
@property(nonatomic,strong) UILabel *heading;
@property(nonatomic,strong) UITextView *caption;
@property(nonatomic,strong) UIImageView *art;
@property(nonatomic,strong) NSDictionary *detail;
@property(nonatomic,copy) NSString *chapterName;
@property(nonatomic) BOOL opened;
@end
static PMOSView *active;
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
 self.toggle.frame=self.opened?CGRectMake(x+w*.5-50,y+h-46,100,42):CGRectMake(x+w*.54,y+4,60,42);
 self.back.frame=CGRectMake(x+12,y+8,52,42);self.heading.frame=CGRectMake(x+78,y+6,MAX(60,w-106),46);
 CGFloat cardHeight=MAX(1,MIN(MIN(420.,(w-32)*.62)/1.7,h-114));self.table.frame=CGRectMake(x+16,y+(h-cardHeight)*.5,w-32,cardHeight);self.caption.frame=CGRectMake(x+24,y+62,w*.44,MAX(60,h-132));self.art.frame=CGRectMake(x+w*.5,y+58,w*.48,MAX(60,h-128));self.choose.frame=CGRectMake(x+w-168,y+h-52,156,44);
}
- (void)refresh{BOOL detail=self.detail!=nil;self.backgroundColor=self.opened?[UIColor colorWithWhite:.075 alpha:1]:UIColor.clearColor;
 self.table.hidden=!self.opened||detail;self.heading.hidden=!self.opened;self.back.hidden=self.caption.hidden=self.art.hidden=self.choose.hidden=!self.opened||!detail;
 self.heading.text=detail?self.detail[@"title"]:self.chapterName;self.caption.text=self.detail[@"caption"];[self.toggle setTitle:self.opened?@"普通选曲":@"OS" forState:UIControlStateNormal];[self setNeedsLayout];}
- (void)toggleOS{self.opened=!self.opened;self.detail=nil;self.art.image=nil;[self refresh];}
- (void)closeDetail{self.detail=nil;self.art.image=nil;[self refresh];}
- (void)chooseSong{if(self.selectSong&&self.selectSong(self.detail[@"group"]))[self toggleOS];else self.caption.text=@"当前选曲列表中没有此曲目。";}
- (NSInteger)collectionView:(UICollectionView*)v numberOfItemsInSection:(NSInteger)s{return self.cards.count;}
- (CGSize)collectionView:(UICollectionView*)v layout:(UICollectionViewLayout*)layout sizeForItemAtIndexPath:(NSIndexPath*)p{CGFloat w=MIN(v.bounds.size.width*.62,MIN(420.,v.bounds.size.height*1.7));return CGSizeMake(MAX(1,w),MAX(1,w/1.7));}
- (UICollectionViewCell*)collectionView:(UICollectionView*)v cellForItemAtIndexPath:(NSIndexPath*)p{PMOSCell *cell=[v dequeueReusableCellWithReuseIdentifier:@"os" forIndexPath:p];NSDictionary *row=self.cards[p.item];cell.name.text=row[@"title"];cell.accessibilityLabel=cell.name.text;NSString *path=row[@"art"];cell.path=path;cell.image.image=path?[self.thumbs objectForKey:path]:nil;
 if(path&&!cell.image.image){__weak PMOSCell *weakCell=cell;__weak PMOSView *weakOwner=self;cell.task=[NSBlockOperation blockOperationWithBlock:^{UIImage *image=thumb(path,384);dispatch_async(dispatch_get_main_queue(),^{PMOSCell *c=weakCell;PMOSView *owner=weakOwner;if(!owner||owner!=active||!image)return;[owner.thumbs setObject:image forKey:path];if([c.path isEqual:path])c.image.image=image;});}];[coverQueue() addOperation:cell.task];}return cell;}
- (void)collectionView:(UICollectionView*)v didSelectItemAtIndexPath:(NSIndexPath*)p{NSDictionary *card=self.cards[p.row];self.detail=card;[UIView transitionWithView:self duration:.2 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{[self refresh];} completion:nil];NSString *path=card[@"art"];if(!path)return;
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{UIImage *image=thumb(path,768);dispatch_async(dispatch_get_main_queue(),^{if(active==self&&self.detail==card)self.art.image=image;});});}
@end
BOOL PMChapterOSVisible(){return active.opened;}
void PMCloseChapterOS(){++generation;if(active)[coverQueue() cancelAllOperations];[active removeFromSuperview];active=nil;}
void PMOpenChapterOS(NSString *chapter,BOOL (^selectSong)(NSString *)){
 PMContentStore *store=PMContentStore.shared;if(![store hasChapterScript:chapter])return;
 NSUInteger token=generation;NSString *file=[[store asset:chapter] stringByAppendingPathComponent:PMChapterScriptName];
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
 NSError *err=nil;NSData *source=PMChapterScriptData([NSURL fileURLWithPath:file],&err);NSDictionary *db=[store snapshot];NSArray *order=PMChapterSongIDs(db,nil,chapter);auto plan=std::make_unique<PMOSPage>();
 if(!source||!PMBuildOSPage((const char*)source.bytes,source.length,(int)order.count,plan.get())){PMDiagnosticsWrite([[NSString stringWithFormat:@"Chapter OS %@: %@",chapter,err.localizedDescription?:[NSString stringWithUTF8String:plan->error]] UTF8String]);return;}
 NSMutableDictionary *songs=[NSMutableDictionary dictionary];for(NSDictionary *song in db[@"songs"])songs[song[@"id"]]=song;
 NSString *name=chapter;for(NSDictionary *c in db[@"chapters"])if([c[@"id"] isEqual:chapter]){name=c[@"name"];break;}
 NSMutableArray *cards=[NSMutableArray array];for(NSUInteger i=0,n=plan->count?(NSUInteger)plan->count:order.count;i<n;i++){
 const PMOSCard *c=plan->count?&plan->cards[i]:nullptr;NSString *sid=order[c?c->song-1:i];NSDictionary *song=songs[sid];NSString *title=c&&c->title[0]?[NSString stringWithUTF8String:c->title]:nil;
 NSMutableDictionary *row=[@{@"title":title?:song[@"title"]?:sid,@"group":song[@"groupId"]?:sid,@"caption":(c&&c->caption[0]?[NSString stringWithUTF8String:c->caption]:nil)?:song[@"composer"]?:@""} mutableCopy];if(song && ![song[@"unlock"][@"enabled"] boolValue])row[@"art"]=[[store asset:sid] stringByAppendingPathComponent:@"image.png"];[cards addObject:row];}
 BOOL opened=!plan->listFirst;dispatch_async(dispatch_get_main_queue(),^{if(token!=generation)return;UIView *host=hostView();if(!host)return;
 active=[[PMOSView alloc]initWithFrame:host.bounds];active.cards=cards;active.chapterName=name;active.selectSong=selectSong;active.opened=opened;[active refresh];[host addSubview:active];});
 }});
}
