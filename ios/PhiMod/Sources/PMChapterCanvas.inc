// Included in the OS presentation unit to share its bounded thumbnail worker.
#import <QuartzCore/QuartzCore.h>
#include <algorithm>
#include <limits>

// Page time is monotonic and excludes time spent away. The end is exclusive.
// Each phase supplies the next boundary and, during a fade, the current alpha.
struct PMCanvasPhase {
    bool visible;
    double alpha, targetAlpha, next;
};
static PMCanvasPhase PMPhaseAt(double t, double start, double duration, double fade) {
    const double forever = std::numeric_limits<double>::infinity();
    if (t < start) return {false, 0, 0, start};
    const double end = duration > 0 ? start + duration : forever;
    if (t >= end) return {false, 0, 0, forever};
    if (duration > 0) fade = std::min(fade, duration / 2);
    if (t < start + fade) return {true, (t - start) / fade, 1, start + fade};
    if (t >= end - fade) return {true, (end - t) / fade, 0, end};
    return {true, 1, 1, end - fade};
}

#include "PMCanvasAlpha.inc"

@interface PMCanvasItem : UIControl
@property(nonatomic,weak) UIView *layoutParent;
@property(nonatomic,weak) PMCanvasItem *dropTarget;
@property(nonatomic,weak) UIImageView *hitImage;
@property(nonatomic) BOOL placed, alphaHit;
@property(nonatomic) NSUInteger dragVisit;
@property(nonatomic) BOOL actionable;
@property(nonatomic) CGRect relative;
@property(nonatomic) NSTimeInterval start, duration, fade, animationEnd;
@end
@implementation PMCanvasItem
- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
 UIView *v = [super hitTest:point withEvent:event];
 if (v != self) return v;
 if (!self.actionable) return nil;
 if (self.alphaHit && !PMCanvasOpaquePixel(self.hitImage, point)) return nil;
 return self;
}
@end
@interface PMChapterCanvas : UIView <UIGestureRecognizerDelegate>
@property(nonatomic,weak) PMCanvasItem *dragging;
@property(nonatomic,strong) UIView *dragPreview;
@property(nonatomic) CGPoint dragOrigin;
@property(nonatomic) CGSize dragCanvasSize;
@property(nonatomic,strong) NSMutableIndexSet *placements;
@property(nonatomic,copy) NSArray<NSDictionary*> *nodes;
@property(nonatomic,copy) void (^openSong)(NSDictionary *song);
@property(nonatomic) NSInteger page;
@property(nonatomic,copy) void (^runHandler)(NSInteger);
@property(nonatomic) BOOL pending;
@property(nonatomic,strong) PMOSRevealView *reveal;
@property(nonatomic) NSUInteger revealEpoch;
- (UIView *)revealAnchorAtIndex:(NSInteger)index;
@property(nonatomic) NSUInteger visit;
@property(nonatomic) BOOL clockRunning;
@property(nonatomic) CFTimeInterval elapsed, resumedAt;
@property(nonatomic,strong) NSTimer *boundaryTimer;
@property(nonatomic,strong) NSMutableDictionary<NSNumber*,NSNumber*> *visibility;
- (void)setElement:(NSInteger)index visible:(BOOL)visible;
@property(nonatomic,strong) NSMutableArray<PMCanvasItem*> *items;
@property(nonatomic,strong) NSMutableArray<NSOperation*> *jobs;
@property(nonatomic,strong) NSMutableArray<PMOSMediaView*> *players;
- (void)displayPage:(NSInteger)index;
@end
@implementation PMChapterCanvas
#include "PMCanvasDrop.inc"
- (UIView *)revealAnchorAtIndex:(NSInteger)index {
    for (PMCanvasItem *item in self.items) if (item.tag == index) return item;
    return nil;
}
- (void)cancelReveal {
    [self.reveal cancel];
    self.reveal = nil;
}
- (void)deactivateReveal:(NSNotification *)note {
    ++self.revealEpoch; // Also invalidate a reveal still being decoded on the events queue.
    if (!self.reveal) return;
    self.pending = NO;
    [self cancelReveal];
    [self syncClock];
}
- (void)updatePlayers {
 for(PMOSMediaView *player in self.players){BOOL show=self.clockRunning;for(UIView *v=player.superview;show&&v&&v!=self;v=v.superview)show=!v.hidden;[player setPlaying:show];}
}
- (void)refreshTimeline {
    [self.boundaryTimer invalidate];
    self.boundaryTimer = nil;
    CFTimeInterval now = CACurrentMediaTime();
    double t = self.elapsed + (self.clockRunning ? now - self.resumedAt : 0);
    double next = std::numeric_limits<double>::infinity();
    // Parents precede children in the layout. Their hidden state gates the whole subtree,
    // and UIKit composes their alpha with each child's own fade.
    for (PMCanvasItem *item in self.items) {
        NSNumber *manualOverride = self.visibility[@(item.tag)];
        BOOL manual = manualOverride ? manualOverride.boolValue : ![self.nodes[item.tag][@"hidden"] boolValue];
        BOOL eligible = (self.clockRunning || self.reveal != nil) && manual && !item.layoutParent.hidden;
        PMCanvasPhase phase = PMPhaseAt(t, item.start, item.duration, item.fade);
        if (eligible && self.clockRunning) next = std::min(next, phase.next);
        item.hidden = !eligible || !phase.visible;
        BOOL animate = self.clockRunning && !item.hidden && phase.alpha != phase.targetAlpha;
        if (animate && item.animationEnd == phase.next) continue;
        if (item.animationEnd) {
            [item.layer removeAnimationForKey:@"opacity"];
            item.animationEnd = 0;
        }
        if (item.hidden) continue;
        [UIView performWithoutAnimation:^{ item.alpha = phase.alpha; }];
        if (animate) {
            item.animationEnd = phase.next;
            [UIView animateWithDuration:phase.next - t delay:0
                options:UIViewAnimationOptionCurveLinear | UIViewAnimationOptionAllowUserInteraction |
                        UIViewAnimationOptionOverrideInheritedDuration | UIViewAnimationOptionOverrideInheritedCurve
                animations:^{ item.alpha = phase.targetAlpha; } completion:nil];
        }
    }
    if (self.dragging && ![self visibleForDrop:self.dragging]) [self discardDrag];
    [self updatePlayers];
    if (std::isfinite(next)) {
        // Account for time spent updating views. Late callbacks sample the current phase.
        double delay = std::max(0.0, (next - t) - (CACurrentMediaTime() - now));
        __weak PMChapterCanvas *owner = self;
        self.boundaryTimer = [NSTimer timerWithTimeInterval:delay repeats:NO block:^(NSTimer *timer) {
            PMChapterCanvas *canvas = owner;
            if (canvas.boundaryTimer == timer) [canvas refreshTimeline];
        }];
        [NSRunLoop.mainRunLoop addTimer:self.boundaryTimer forMode:NSRunLoopCommonModes];
    }
}
- (void)syncClock {
    BOOL running = !self.reveal && self.window != nil && !self.hidden && self.items.count > 0;
    if (running != self.clockRunning) {
        CFTimeInterval now = CACurrentMediaTime();
        if (running) self.resumedAt = now;
        else self.elapsed += now - self.resumedAt;
        self.clockRunning = running;
    }
    [self refreshTimeline];
}
- (void)setElement:(NSInteger)index visible:(BOOL)visible {
    if (!self.visibility) self.visibility = [NSMutableDictionary dictionary];
    self.visibility[@(index)] = @(visible);
    [self refreshTimeline];
}
- (void)setHidden:(BOOL)value {
    if (self.hidden == value) return;
    [self cancelReveal];
    [self discardDrag];
    self.visit++;
    self.pending = NO;
    [super setHidden:value];
    [self syncClock];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
    if (self.window) [center addObserver:self selector:@selector(deactivateReveal:) name:UIApplicationWillResignActiveNotification object:nil];
    else { [self cancelReveal]; [self discardDrag]; self.visit++; self.pending = NO; }
    [self syncClock];
}
- (void)dealloc {
    [_boundaryTimer invalidate];
    for (NSOperation *job in _jobs) [job cancel];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.dragging && !CGSizeEqualToSize(self.bounds.size, self.dragCanvasSize)) [self discardDrag];
    [self layoutPieces];
}
- (void)activate:(PMCanvasItem*)sender {if(self.pending || self.dragging || sender.dropTarget || !self.clockRunning || ![self.items containsObject:sender])return;NSDictionary *n=self.nodes[sender.tag];if([n[@"handler"] boolValue]){self.runHandler(sender.tag);return;}if(n[@"song"])self.openSong(n[@"song"]);else if([n[@"dest"] integerValue]>=0)[self displayPage:[n[@"dest"] integerValue]];}
- (void)displayPage:(NSInteger)index {
 [self cancelReveal];
 [self discardDrag];
 if (!self.placements) self.placements = [NSMutableIndexSet indexSet];
 [self.boundaryTimer invalidate];
 self.boundaryTimer = nil;
 self.clockRunning = NO;
 self.elapsed = 0;
 for (PMCanvasItem *item in self.items) [item.layer removeAnimationForKey:@"opacity"];
 self.visit++;self.pending=NO;self.page=index;for(PMOSMediaView *p in self.players)[p setPlaying:NO];self.players=[NSMutableArray new];for(NSOperation *job in self.jobs)[job cancel];self.jobs=[NSMutableArray new];for(UIView *v in self.subviews)[v removeFromSuperview];self.items=[NSMutableArray new];
 NSMutableDictionary<NSNumber*,PMCanvasItem*> *parents=[NSMutableDictionary dictionary];NSMutableDictionary<NSString*,NSMutableArray<UIImageView*>*> *images=[NSMutableDictionary dictionary];
 for(NSUInteger i=0;i<self.nodes.count;i++){NSDictionary *node=self.nodes[i];if([node[@"screen"] integerValue]!=index)continue;
  PMCanvasItem *item=[[PMCanvasItem alloc]initWithFrame:CGRectZero];item.tag=i;
  item.start=[node[@"start"] doubleValue];item.duration=[node[@"duration"] doubleValue];item.fade=[node[@"fade"] doubleValue];item.hidden=YES;
  item.relative=[node[@"rect"] CGRectValue];item.clipsToBounds=YES;item.actionable=[node[@"handler"] boolValue]||node[@"song"]!=nil||[node[@"dest"] integerValue]>=0;item.accessibilityTraits=UIAccessibilityTraitButton;item.isAccessibilityElement=item.actionable&&[node[@"kind"] intValue]!=PMOSFrame;
  item.accessibilityLabel=node[@"label"]?:node[@"song"][@"title"]?:node[@"to"];if(item.actionable && !node[@"dropIndex"])[item addTarget:self action:@selector(activate:) forControlEvents:UIControlEventTouchUpInside];
  unsigned color=[node[@"rgba"] unsignedIntValue];item.backgroundColor=[UIColor colorWithRed:(color>>24)/255. green:((color>>16)&255)/255. blue:((color>>8)&255)/255. alpha:(color&255)/255.];
  UIView *parent=parents[node[@"parent"]]?:self;item.layoutParent=parent;[parent addSubview:item];parents[@(i)]=item;[self.items addObject:item];
  item.alphaHit=[node[@"alphaHit"] boolValue];
  NSString *path=node[@"path"];if([@[@"gif",@"mp4"] containsObject:path.pathExtension.lowercaseString?:@""]){
   item.alphaHit=NO; // Animated media uses rectangular hit testing.
   PMOSMediaView *player=[[PMOSMediaView alloc]initWithPath:path loop:[node[@"loop"] boolValue] fill:[node[@"fill"] boolValue]];player.frame=item.bounds;player.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;player.userInteractionEnabled=NO;[item addSubview:player];[self.players addObject:player];
  }else if(path){UIImageView *image=[[UIImageView alloc]initWithFrame:item.bounds];image.contentMode=[node[@"fill"] boolValue]?UIViewContentModeScaleAspectFill:UIViewContentModeScaleAspectFit;image.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[item addSubview:image];item.hitImage=image;if(!images[path])images[path]=[NSMutableArray new];[images[path] addObject:image];}
  if(node[@"label"]&&[node[@"kind"] intValue]!=PMOSHotspot){UILabel *label=[[UILabel alloc]initWithFrame:item.bounds];label.text=node[@"label"];label.textColor=UIColor.whiteColor;label.textAlignment=NSTextAlignmentCenter;label.numberOfLines=2;label.adjustsFontSizeToFitWidth=YES;label.minimumScaleFactor=.6;label.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[item addSubview:label];}
 }
 for (PMCanvasItem *piece in self.items) {
  NSNumber *indexOfTarget = self.nodes[piece.tag][@"dropIndex"];
  if (!indexOfTarget) continue;
  piece.dropTarget = parents[indexOfTarget];
  UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPiece:)];
  pan.maximumNumberOfTouches = 1;
  pan.delegate = self;
  [piece addGestureRecognizer:pan];
  if ([self.placements containsIndex:piece.tag]) {
   piece.placed = YES;
   [piece.dropTarget.superview addSubview:piece];
  }
 }
 [self syncClock];[self setNeedsLayout];NSInteger pixels=MIN(1536,(NSInteger)std::sqrt(4.*1024*1024/MAX(1,images.count))); // Bound the decoded pixels of an entire page.
 for(NSString *path in images){NSArray *targets=[images[path] copy];__weak PMChapterCanvas *owner=self;__weak NSMutableArray *token=self.jobs;
  NSBlockOperation *job=[NSBlockOperation blockOperationWithBlock:^{UIImage *image=thumb(path,pixels);dispatch_async(dispatch_get_main_queue(),^{PMChapterCanvas *canvas=owner;if(!canvas||!token||canvas.jobs!=token)return;for(UIImageView *v in targets)v.image=image;});}];[self.jobs addObject:job];[coverQueue() addOperation:job];}
}
@end
