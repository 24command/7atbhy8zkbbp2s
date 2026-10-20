#import "PMOfficialUI.h"
#import <QuartzCore/QuartzCore.h>
static UIBezierPath *PMSlant(CGRect r){
 CGFloat cut=MIN(r.size.height*.267949,r.size.width*.25);
 UIBezierPath*p=[UIBezierPath bezierPath];
 [p moveToPoint:CGPointMake(CGRectGetMinX(r)+cut,CGRectGetMinY(r))];
 [p addLineToPoint:CGPointMake(CGRectGetMaxX(r),CGRectGetMinY(r))];
 [p addLineToPoint:CGPointMake(CGRectGetMaxX(r)-cut,CGRectGetMaxY(r))];
 [p addLineToPoint:CGPointMake(CGRectGetMinX(r),CGRectGetMaxY(r))];[p closePath];return p;
}
@implementation PMOfficialCard
- (instancetype)initWithFrame:(CGRect)frame{if((self=[super initWithFrame:frame])){self.backgroundColor=UIColor.clearColor;self.opaque=NO;self.fillColor=[UIColor colorWithRed:.08 green:.10 blue:.14 alpha:.94];}return self;}
- (void)setFillColor:(UIColor*)color{_fillColor=color;[self setNeedsDisplay];}
- (void)drawRect:(CGRect)rect{[self.fillColor setFill];[PMSlant(self.bounds) fill];}
@end
@implementation PMOfficialButton
- (instancetype)initWithFrame:(CGRect)frame{if((self=[super initWithFrame:frame])){self.backgroundColor=UIColor.clearColor;self.opaque=NO;self.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];self.titleLabel.adjustsFontSizeToFitWidth=YES;self.titleLabel.minimumScaleFactor=.7;[self setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];[self setTitleColor:UIColor.blackColor forState:UIControlStateSelected];[self.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;}return self;}
- (void)setSelected:(BOOL)selected{[super setSelected:selected];[self setNeedsDisplay];}
- (void)setHighlighted:(BOOL)highlighted{[super setHighlighted:highlighted];self.alpha=highlighted?.6:1;}
- (void)drawRect:(CGRect)rect{[(self.selected?UIColor.whiteColor:[UIColor colorWithWhite:.04 alpha:.64]) setFill];[PMSlant(self.bounds) fill];[super drawRect:rect];}
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
@interface PMOfficialCategories ()
@property(nonatomic,strong) NSArray<PMOfficialButton*> *buttons;
@property(nonatomic,strong) UILabel *detail;
@end
@implementation PMOfficialCategories
- (instancetype)initWithFrame:(CGRect)frame{if((self=[super initWithFrame:frame])){NSMutableArray*a=[NSMutableArray new];NSArray*names=@[@"谱库",@"章节",@"判定",@"模式",@"设置"];NSArray*icons=@[@"folder",@"rectangle.stack",@"checkmark.circle",@"play",@"gearshape"];
 for(NSInteger i=0;i<5;++i){PMOfficialButton*b=[PMOfficialButton new];b.tag=i;[b setTitle:[@"  " stringByAppendingString:names[i]] forState:UIControlStateNormal];[b setImage:[UIImage systemImageNamed:icons[i]] forState:UIControlStateNormal];b.accessibilityLabel=names[i];[b addTarget:self action:@selector(choose:) forControlEvents:UIControlEventTouchUpInside];[self addSubview:b];[a addObject:b];}self.buttons=a;self.detail=[UILabel new];self.detail.font=[UIFont systemFontOfSize:12];self.detail.textColor=[UIColor colorWithWhite:1 alpha:.7];self.detail.adjustsFontSizeToFitWidth=YES;self.detail.minimumScaleFactor=.75;[self addSubview:self.detail];self.expanded=YES;self.selectedSegmentIndex=3;}return self;}
- (void)setSelectedSegmentIndex:(NSInteger)value{_selectedSegmentIndex=MAX(0,MIN(4,value));NSArray*d=@[@"导入、编辑与管理谱面",@"章节排序与显示",@"判定范围与窗口",@"演示、练习与生存规则",@"界面选项与诊断日志"];self.detail.text=d[_selectedSegmentIndex];for(PMOfficialButton*b in self.buttons){b.selected=b.tag==_selectedSegmentIndex;b.tintColor=b.selected?UIColor.blackColor:UIColor.whiteColor;}[self setNeedsLayout];}
- (void)setExpanded:(BOOL)value{_expanded=value;self.detail.hidden=!value;[self setNeedsLayout];}
- (void)layoutSubviews{[super layoutSubviews];CGFloat gap=4,w=MAX(1,(self.bounds.size.width-gap*4)/5);for(NSInteger i=0;i<5;++i)self.buttons[i].frame=CGRectMake(i*(w+gap),0,w,44);self.detail.frame=CGRectMake(14,48,MAX(1,self.bounds.size.width-28),22);}
- (void)choose:(UIButton*)sender{NSInteger previous=self.selectedSegmentIndex;self.selectedSegmentIndex=sender.tag;[self sendActionsForControlEvents:UIControlEventValueChanged];if(previous!=self.selectedSegmentIndex&&!UIAccessibilityIsReduceMotionEnabled()){self.detail.alpha=0;[UIView animateWithDuration:.18 animations:^{self.detail.alpha=1;}];}}
@end
