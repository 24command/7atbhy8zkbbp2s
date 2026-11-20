#import "PMOfficialUI.h"
#import <QuartzCore/QuartzCore.h>
static UIBezierPath *PMSlantWithCut(CGRect r, CGFloat cut){
 UIBezierPath*p=[UIBezierPath bezierPath];
 [p moveToPoint:CGPointMake(CGRectGetMinX(r)+cut,CGRectGetMinY(r))];
 [p addLineToPoint:CGPointMake(CGRectGetMaxX(r),CGRectGetMinY(r))];
 [p addLineToPoint:CGPointMake(CGRectGetMaxX(r)-cut,CGRectGetMaxY(r))];
 [p addLineToPoint:CGPointMake(CGRectGetMinX(r),CGRectGetMaxY(r))];[p closePath];return p;
}
static UIBezierPath *PMSlant(CGRect r){return PMSlantWithCut(r,MIN(r.size.height*.267949,r.size.width*.25));}
@implementation PMOfficialCard
- (instancetype)initWithFrame:(CGRect)frame{if((self=[super initWithFrame:frame])){self.backgroundColor=UIColor.clearColor;self.opaque=NO;self.fillColor=[UIColor colorWithRed:.08 green:.10 blue:.14 alpha:.94];}return self;}
- (void)setFillColor:(UIColor*)color{_fillColor=color;[self setNeedsDisplay];}
- (void)drawRect:(CGRect)rect{[self.fillColor setFill];[PMSlant(self.bounds) fill];}
@end
@implementation PMOfficialButton
- (instancetype)initWithFrame:(CGRect)frame{if((self=[super initWithFrame:frame])){self.backgroundColor=UIColor.clearColor;self.opaque=NO;self.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];self.titleLabel.adjustsFontSizeToFitWidth=YES;self.titleLabel.minimumScaleFactor=.7;[self setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];[self setTitleColor:UIColor.blackColor forState:UIControlStateSelected];[self.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;}return self;}
- (void)setEnabled:(BOOL)enabled{[super setEnabled:enabled];[self setNeedsDisplay];}
- (void)setSelected:(BOOL)selected{[super setSelected:selected];[self setNeedsDisplay];}
- (void)setHighlighted:(BOOL)highlighted{[super setHighlighted:highlighted];self.alpha=highlighted?.6:1;}
- (void)drawRect:(CGRect)rect{if(!self.flatStyle){[(self.selected?UIColor.whiteColor:[UIColor colorWithWhite:.04 alpha:.64]) setFill];UIBezierPath *shape=self.inverseSlope>0?PMSlantWithCut(self.bounds,MIN(self.bounds.size.width,self.bounds.size.height*self.inverseSlope)):PMSlant(self.bounds);if(self.inverseSlope>0&&!self.enabled)[[UIColor colorWithWhite:.25 alpha:.85] setFill];[shape fill];}[super drawRect:rect];}
@end
@interface PMOfficialToggle ()
@property(nonatomic,strong) CAShapeLayer *track;
@property(nonatomic,strong) CAShapeLayer *handle;
@property(nonatomic,strong) CAShapeLayer *tick;
@end
@implementation PMOfficialToggle
- (instancetype)initWithFrame:(CGRect)frame{if((self=[super initWithFrame:frame])){self.backgroundColor=UIColor.clearColor;self.track=[CAShapeLayer layer];self.handle=[CAShapeLayer layer];self.tick=[CAShapeLayer layer];for(CAShapeLayer*l in @[self.track,self.handle,self.tick])[self.layer addSublayer:l];self.isAccessibilityElement=YES;self.accessibilityTraits=UIAccessibilityTraitButton;[self addTarget:self action:@selector(flip) forControlEvents:UIControlEventTouchUpInside];[self.widthAnchor constraintEqualToConstant:96].active=YES;[self.heightAnchor constraintEqualToConstant:44].active=YES;[self setOn:NO];}return self;}
- (CGSize)intrinsicContentSize{return CGSizeMake(96,44);}
- (void)layoutSubviews{[super layoutSubviews];CGFloat w=self.bounds.size.width,h=MIN(36,self.bounds.size.height),y=(self.bounds.size.height-h)/2;
 [CATransaction begin];[CATransaction setDisableActions:YES];self.track.path=PMSlant(CGRectMake(0,y+h*.11,w,h*.78)).CGPath;self.track.fillColor=[UIColor colorWithWhite:.02 alpha:.34].CGColor;
 self.handle.path=PMSlant(CGRectMake(0,y,w*52/96,h)).CGPath;self.handle.fillColor=UIColor.whiteColor.CGColor;self.handle.position=CGPointMake(self.on?w*(1-52.0/96):0,0);
 UIBezierPath*p=[UIBezierPath bezierPath];[p moveToPoint:CGPointMake(w*.18,y+h*.45)];[p addLineToPoint:CGPointMake(w*.235,y+h*.60)];[p addLineToPoint:CGPointMake(w*.36,y+h*.31)];self.tick.path=p.CGPath;self.tick.fillColor=UIColor.clearColor.CGColor;self.tick.strokeColor=UIColor.whiteColor.CGColor;self.tick.lineWidth=h*.035;self.tick.opacity=self.on?1:0;[CATransaction commit];}
- (void)setOn:(BOOL)on{_on=on;self.accessibilityValue=on?@"开启":@"关闭";self.accessibilityTraits=UIAccessibilityTraitButton|(on?UIAccessibilityTraitSelected:0);[self setNeedsLayout];}
- (void)flip{CGFloat from=((CALayer*)self.handle.presentationLayer ?: self.handle).position.x;self.on=!self.on;[self layoutIfNeeded];if(!UIAccessibilityIsReduceMotionEnabled()){CABasicAnimation*a=[CABasicAnimation animationWithKeyPath:@"position.x"];a.fromValue=@(from);a.toValue=@(self.handle.position.x);a.duration=.18;[self.handle addAnimation:a forKey:@"toggle"];}[self sendActionsForControlEvents:UIControlEventValueChanged];}
- (BOOL)accessibilityActivate{[self flip];return YES;}
@end
// Paths from Android VectorIcons.java (24-unit viewport).
static UIImage*PMCategoryIcon(NSInteger index){
 NSArray*paths=@[@"M 3 6 L 10 6 L 13 9 L 21 9 L 21 21 L 3 21 Z",@"M 3 3 L 21 3 L 21 21 L 3 21 Z M 3 18 L 9 11 L 14 16 L 17 12 L 21 17 M 16 7 L 17 7",@"M 3 12 L 9 18 L 21 5",@"M 6 3 L 21 12 L 6 21 Z",@"M 9 2 L 15 2 L 16 5 L 19 5 L 22 10 L 20 12 L 22 14 L 19 19 L 16 19 L 15 22 L 9 22 L 8 19 L 5 19 L 2 14 L 4 12 L 2 10 L 5 5 L 8 5 Z M 10 8 L 14 8 L 16 10 L 16 14 L 14 16 L 10 16 L 8 14 L 8 10 Z"];
 NSArray*tokens=[paths[index] componentsSeparatedByString:@" "];UIBezierPath*p=[UIBezierPath bezierPath];
 for(NSUInteger i=0;i<tokens.count;){NSString*command=tokens[i++];if([command isEqualToString:@"Z"]){[p closePath];continue;}CGFloat x=[tokens[i++] doubleValue],y=[tokens[i++] doubleValue];if([command isEqualToString:@"M"])[p moveToPoint:CGPointMake(x,y)];else[p addLineToPoint:CGPointMake(x,y)];}
 p.lineWidth=1.4;p.lineJoinStyle=kCGLineJoinRound;p.lineCapStyle=kCGLineCapRound;
 UIGraphicsImageRenderer*renderer=[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(20,20)];return [[renderer imageWithActions:^(UIGraphicsImageRendererContext*context){CGContextScaleCTM(context.CGContext,20.0/24,20.0/24);[UIColor.whiteColor setStroke];[p stroke];}] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}
@interface PMCategoryButton : PMOfficialButton
@end
@implementation PMCategoryButton
// Category bar draws the shared rail; the button keeps its title and icon.
@end
@interface PMOfficialCategories ()
@property(nonatomic,strong) NSArray<PMOfficialButton*> *buttons;
@property(nonatomic,strong) UILabel *detail;
@end
@implementation PMOfficialCategories
- (instancetype)initWithFrame:(CGRect)frame{if((self=[super initWithFrame:frame])){NSMutableArray*a=[NSMutableArray new];NSArray*names=@[@"谱库",@"章节",@"判定",@"模式",@"设置"];
 for(NSInteger i=0;i<5;++i){PMOfficialButton*b=[PMCategoryButton new];b.flatStyle=YES;b.tag=i;[b setTitle:[@"  " stringByAppendingString:names[i]] forState:UIControlStateNormal];[b setImage:PMCategoryIcon(i) forState:UIControlStateNormal];b.accessibilityLabel=names[i];[b addTarget:self action:@selector(choose:) forControlEvents:UIControlEventTouchUpInside];[self addSubview:b];[a addObject:b];}self.buttons=a;self.detail=[UILabel new];self.detail.font=[UIFont systemFontOfSize:12];self.detail.textColor=[UIColor colorWithWhite:1 alpha:.7];self.detail.adjustsFontSizeToFitWidth=YES;self.detail.minimumScaleFactor=.75;[self addSubview:self.detail];self.expanded=YES;self.selectedSegmentIndex=3;}return self;}
- (void)setSelectedSegmentIndex:(NSInteger)value{_selectedSegmentIndex=MAX(0,MIN(4,value));NSArray*d=@[@"导入、编辑与管理谱面",@"章节排序与显示",@"判定范围与窗口",@"演示、练习与生存规则",@"界面选项与诊断日志"];self.detail.text=d[_selectedSegmentIndex];[self setNeedsDisplay];for(PMOfficialButton*b in self.buttons){b.selected=b.tag==_selectedSegmentIndex;b.tintColor=b.selected?UIColor.blackColor:UIColor.whiteColor;}[self setNeedsLayout];}
- (void)setExpanded:(BOOL)value{_expanded=value;self.detail.hidden=!value;[self setNeedsLayout];}
- (void)drawRect:(CGRect)rect{CGFloat cut=41*.267949,slot=(self.bounds.size.width-cut)/5;[[UIColor colorWithWhite:0 alpha:.47]setFill];[PMSlant(CGRectMake(0,4,self.bounds.size.width,41))fill];[UIColor.whiteColor setFill];[PMSlant(CGRectMake(slot*self.selectedSegmentIndex,0,slot+cut,46))fill];}
- (void)layoutSubviews{[super layoutSubviews];CGFloat cut=41*.267949,w=MAX(1,(self.bounds.size.width-cut)/5);for(NSInteger i=0;i<5;++i)self.buttons[i].frame=CGRectMake(i*w+cut/2,0,w,46);self.detail.frame=CGRectMake(2,48,MAX(1,self.bounds.size.width-28),27);}
- (void)choose:(UIButton*)sender{NSInteger previous=self.selectedSegmentIndex;self.selectedSegmentIndex=sender.tag;[self sendActionsForControlEvents:UIControlEventValueChanged];if(previous!=self.selectedSegmentIndex&&!UIAccessibilityIsReduceMotionEnabled()){self.detail.alpha=0;[UIView animateWithDuration:.18 animations:^{self.detail.alpha=1;}];}}
@end
