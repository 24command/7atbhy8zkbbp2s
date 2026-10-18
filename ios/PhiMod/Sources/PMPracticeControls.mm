#import "PMPracticeControls.h"
#import "PMHookBackend.h"
#import "PMSettings.h"
#include <cmath>
@interface PMPracticeControls ()
@property(nonatomic,strong) NSTimer*timer;
@property(nonatomic,strong) UILabel*clock;
@property(nonatomic,strong) UILabel*range;
@property(nonatomic,strong) UISlider*timeline;
@property(nonatomic,strong) UIStackView*body;
@property(nonatomic,strong) UIButton*pauseButton;
@property(nonatomic,strong) UIButton*loopButton;
@property(nonatomic,strong) UIButton*countButton;
@property(nonatomic,strong) UIButton*foldButton;
@property(nonatomic,strong) UISegmentedControl*rates;
@property(nonatomic,strong) NSDictionary*state;
@property(nonatomic,assign) BOOL folded;
@property(nonatomic,assign) BOOL wasPaused;
@property(nonatomic,assign) BOOL scrubbing;
@end
@implementation PMPracticeControls
- (UIButton*)button:(NSString*)text action:(SEL)action {UIButton*b=[UIButton buttonWithType:UIButtonTypeSystem];[b setTitle:text forState:UIControlStateNormal];[b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];b.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];[b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];return b;}
- (UIStackView*)row:(NSArray<UIView*>*)views {UIStackView*r=[[UIStackView alloc]initWithArrangedSubviews:views];r.axis=UILayoutConstraintAxisHorizontal;r.distribution=UIStackViewDistributionFillEqually;r.spacing=6;return r;}
- (instancetype)initWithFrame:(CGRect)frame {if((self=[super initWithFrame:frame])){
 self.backgroundColor=[UIColor colorWithWhite:.06 alpha:.93];self.layer.cornerRadius=12;self.hidden=YES;
 self.clock=[UILabel new];self.clock.textColor=UIColor.whiteColor;self.clock.font=[UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightSemibold];
 self.foldButton=[self button:@"收起" action:@selector(fold)];self.pauseButton=[self button:@"开始" action:@selector(pause)];
 UIStackView*header=[[UIStackView alloc]initWithArrangedSubviews:@[self.clock,self.pauseButton,self.foldButton]];header.axis=UILayoutConstraintAxisHorizontal;header.spacing=12;[self.pauseButton.widthAnchor constraintEqualToConstant:78].active=YES;[self.foldButton.widthAnchor constraintEqualToConstant:52].active=YES;
 self.timeline=[UISlider new];self.timeline.minimumValue=0;[self.timeline addTarget:self action:@selector(scrubBegin) forControlEvents:UIControlEventTouchDown];[self.timeline addTarget:self action:@selector(scrubChanged) forControlEvents:UIControlEventValueChanged];[self.timeline addTarget:self action:@selector(scrubEnd) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];[self.timeline addTarget:self action:@selector(scrubCancel) forControlEvents:UIControlEventTouchCancel];
 self.range=[UILabel new];self.range.font=[UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];self.range.textColor=[UIColor colorWithWhite:.8 alpha:1];self.range.textAlignment=NSTextAlignmentCenter;
 self.loopButton=[self button:@"循环" action:@selector(loop)];self.countButton=[self button:@"倒数" action:@selector(countIn)];
 UIStackView*actions=[self row:@[[self button:@"设为起点" action:@selector(markStart)],[self button:@"设为终点" action:@selector(markEnd)],[self button:@"重播" action:@selector(repeatRange)],[self button:@"整首" action:@selector(fullSong)],self.loopButton,self.countButton]];
 self.rates=[[UISegmentedControl alloc]initWithItems:@[@"0.5×",@"0.75×",@"1×",@"1.25×",@"1.5×",@"2×"]];self.rates.selectedSegmentTintColor=[UIColor colorWithWhite:.75 alpha:1];[self.rates setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.whiteColor} forState:UIControlStateNormal];[self.rates setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.blackColor} forState:UIControlStateSelected];[self.rates addTarget:self action:@selector(rateChanged) forControlEvents:UIControlEventValueChanged];
 self.body=[[UIStackView alloc]initWithArrangedSubviews:@[header,self.timeline,self.range,actions,self.rates]];self.body.axis=UILayoutConstraintAxisVertical;self.body.spacing=4;self.body.translatesAutoresizingMaskIntoConstraints=NO;[self addSubview:self.body];[NSLayoutConstraint activateConstraints:@[[self.body.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],[self.body.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],[self.body.topAnchor constraintEqualToAnchor:self.topAnchor constant:6]]];
 __weak PMPracticeControls*weakSelf=self;self.timer=[NSTimer timerWithTimeInterval:.2 repeats:YES block:^(NSTimer*t){[weakSelf tick];}];[NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
 }return self;}
- (void)dealloc {[self.timer invalidate];}
- (NSString*)clockText:(double)value {value=MAX(0,value);NSInteger minutes=(NSInteger)(value/60);return [NSString stringWithFormat:@"%02ld:%05.2f",(long)minutes,value-minutes*60];}
- (void)tick {NSDictionary*r=[PMHookBackend practiceStatus];NSDictionary*s=r[@"state"];BOOL visible=[r[@"ok"] boolValue]&&[s[@"active"] boolValue]&&[s[@"segment"] boolValue]&&[s[@"ready"] boolValue];BOOL wasHidden=self.hidden;self.hidden=!visible;if(!visible)return;self.state=s;
 BOOL paused=[s[@"paused"] boolValue]||[s[@"countdown"] boolValue];if(wasHidden||paused!=self.wasPaused)self.folded=!paused;self.wasPaused=paused;
 self.clock.text=[NSString stringWithFormat:@"练习 %@ / %@ · %.2g×%@",[self clockText:[s[@"cursor"] doubleValue]],[self clockText:[s[@"duration"] doubleValue]],[s[@"effectiveRate"] doubleValue],[s[@"countdown"] boolValue]?@" 倒数":@""];
 [self.pauseButton setTitle:[s[@"countdown"] boolValue]?@"暂停":paused?@"开始 / 继续":@"暂停" forState:UIControlStateNormal];[self.foldButton setTitle:self.folded?@"展开":@"收起" forState:UIControlStateNormal];
 self.timeline.maximumValue=MAX(.01,[s[@"duration"] floatValue]);if(!self.scrubbing)self.timeline.value=[s[@"cursor"] floatValue];self.range.text=[NSString stringWithFormat:@"区间 %@ — %@",[self clockText:[s[@"start"] doubleValue]],[self clockText:[s[@"end"] doubleValue]]];
 [self.loopButton setTitle:[s[@"loop"] boolValue]?@"循环 ✓":@"循环" forState:UIControlStateNormal];[self.countButton setTitle:[s[@"countIn"] boolValue]?@"倒数 ✓":@"倒数" forState:UIControlStateNormal];NSArray*values=@[@0.5,@0.75,@1,@1.25,@1.5,@2];self.rates.selectedSegmentIndex=UISegmentedControlNoSegment;for(NSUInteger i=0;i<values.count;++i)if(std::fabs([values[i] doubleValue]-[s[@"rate"] doubleValue])<.001)self.rates.selectedSegmentIndex=i;
 for(NSUInteger i=1;i<self.body.arrangedSubviews.count;++i)self.body.arrangedSubviews[i].hidden=self.folded;
 UIView*parent=self.superview;if(parent){UIEdgeInsets safe=parent.safeAreaInsets;CGFloat height=self.folded?46:188,width=MIN(760,parent.bounds.size.width-safe.left-safe.right-24);self.frame=CGRectMake((parent.bounds.size.width-width)/2,parent.bounds.size.height-safe.bottom-height-8,width,height);}
}
- (BOOL)put:(NSString*)key value:(id)value {NSString*error=nil;if(![[PMSettings shared] setValue:value forKey:key error:&error]){self.range.text=error;return NO;}return YES;}
- (void)run:(NSInteger)action {NSDictionary*r=[PMHookBackend practiceCommand:action];if(![r[@"ok"] boolValue])self.range.text=r[@"message"];[self tick];}
- (void)fold {self.folded=!self.folded;[self tick];}
- (void)pause {[self run:1];}
- (void)repeatRange {[self run:2];}
- (void)fullSong {[self run:3];}
- (void)scrubBegin {self.scrubbing=YES;if(![self.state[@"paused"] boolValue]&&![self.state[@"countdown"] boolValue])[PMHookBackend practiceCommand:1];}
- (void)scrubChanged {self.clock.text=[NSString stringWithFormat:@"定位 %@",[self clockText:self.timeline.value]];}
- (void)scrubEnd {self.scrubbing=NO;if([self put:@"practicePosition" value:@(self.timeline.value)])[self run:7];}
- (void)scrubCancel {self.scrubbing=NO;[self tick];}
- (void)markStart {float value=MAX(0,[self.state[@"cursor"] floatValue]);if(value>=[self.state[@"end"] floatValue]-.01){self.range.text=@"起点必须早于终点";return;}if([self put:@"practiceStart" value:@(value)])[self run:6];}
- (void)markEnd {float value=MAX(0,[self.state[@"cursor"] floatValue]);if(value<=[self.state[@"start"] floatValue]+.01){self.range.text=@"终点必须晚于起点";return;}if([self put:@"practiceEnd" value:@(value)])[self run:6];}
- (void)loop {if([self put:@"practiceLoop" value:@(![self.state[@"loop"] boolValue])])[self run:6];}
- (void)countIn {if([self put:@"practiceCountdown" value:@(![self.state[@"countIn"] boolValue])])[self run:6];}
- (void)rateChanged {NSArray*values=@[@0.5,@0.75,@1,@1.25,@1.5,@2];NSInteger i=self.rates.selectedSegmentIndex;if(i>=0&&i<(NSInteger)values.count&&[self put:@"playbackRate" value:values[i]])[self run:4];}
@end
