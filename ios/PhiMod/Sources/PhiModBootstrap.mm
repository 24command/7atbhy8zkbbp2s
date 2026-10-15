#import <UIKit/UIKit.h>
#import "PhiModBootstrap.h"
#import "PMSettings.h"
#import "PMRuntime.h"
#import "PMGameplay.h"

static const NSInteger PMOverlayRootTag = 0x50484D4F;
static NSString * const PMBubbleXKey = @"phimod.ios.bubble.x";
static NSString * const PMBubbleYKey = @"phimod.ios.bubble.y";

@interface PMPassthroughView : UIView
@property(nonatomic, copy) void (^layoutCallback)(void);
@end

@implementation PMPassthroughView
- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.layoutCallback) self.layoutCallback();
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

@interface PMOverlayController : NSObject
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, strong) PMPassthroughView *root;
@property(nonatomic, strong) UIButton *bubble;
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) UIView *panelHeader;
@property(nonatomic, strong) UILabel *pageTitle;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIStackView *tabBar;
@property(nonatomic, strong) UIStackView *body;
@property(nonatomic, strong) UIScrollView *scroll;
@property(nonatomic, assign) NSInteger selectedTab;
@property(nonatomic, assign) BOOL open;
+ (instancetype)shared;
- (void)install;
@end

@implementation PMOverlayController

+ (instancetype)shared {
    static PMOverlayController *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [PMOverlayController new]; });
    return instance;
}

static UIColor *PMColor(uint32_t argb) {
    return [UIColor colorWithRed:((argb >> 16) & 0xff) / 255.0
                           green:((argb >> 8) & 0xff) / 255.0
                            blue:(argb & 0xff) / 255.0
                           alpha:((argb >> 24) & 0xff) / 255.0];
}

- (UIWindow *)foregroundWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *candidate in windowScene.windows) if (candidate.isKeyWindow) return candidate;
        for (UIWindow *candidate in windowScene.windows) if (!candidate.hidden && candidate.alpha > 0) return candidate;
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

- (UILabel *)label:(NSString *)text size:(CGFloat)size color:(UIColor *)color {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont systemFontOfSize:size];
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

- (UIButton *)textButton:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:PMColor(0xfff1f5fa) forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    button.backgroundColor = PMColor(0xff252f40);
    button.layer.cornerRadius = 8;
    button.contentEdgeInsets = UIEdgeInsetsMake(7, 10, 7, 10);
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)install {
    NSAssert(NSThread.isMainThread, @"PhiMod UI must be installed on the main thread");
    UIWindow *window = [self foregroundWindow];
    if (!window) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self install]; });
        return;
    }
    if (self.root.superview == window) {
        [window bringSubviewToFront:self.root];
        return;
    }
    UIView *old = [window viewWithTag:PMOverlayRootTag];
    [old removeFromSuperview];
    [self.root removeFromSuperview];
    self.window = window;
    [self buildInWindow:window];
}

- (void)buildInWindow:(UIWindow *)window {
    self.root = [[PMPassthroughView alloc] initWithFrame:window.bounds];
    __weak PMOverlayController *weakSelf = self;
    self.root.layoutCallback = ^{ [weakSelf layoutOverlay]; };
    self.root.tag = PMOverlayRootTag;
    self.root.backgroundColor = UIColor.clearColor;
    self.root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [window addSubview:self.root];

    self.bubble = [UIButton buttonWithType:UIButtonTypeCustom];
    self.bubble.frame = CGRectMake(18, 60, 52, 52);
    self.bubble.backgroundColor = PMColor(0xef1a2637);
    self.bubble.layer.cornerRadius = 26;
    self.bubble.layer.borderWidth = 1;
    self.bubble.layer.borderColor = PMColor(0xff506878).CGColor;
    self.bubble.layer.shadowColor = UIColor.blackColor.CGColor;
    self.bubble.layer.shadowOpacity = 0.35;
    self.bubble.layer.shadowRadius = 8;
    self.bubble.layer.shadowOffset = CGSizeMake(0, 3);
    [self.bubble setTitle:@"Φ" forState:UIControlStateNormal];
    [self.bubble setTitleColor:PMColor(0xff71e1cf) forState:UIControlStateNormal];
    self.bubble.titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightMedium];
    [self.bubble addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.bubble addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragBubble:)]];
    [self.root addSubview:self.bubble];
    [self restoreBubblePosition];
    self.bubble.alpha=[[[PMSettings shared] value:@"opacity"] doubleValue];

    self.panel = [UIView new];
    self.panel.backgroundColor = PMColor(0xf51a2130);
    self.panel.layer.cornerRadius = 18;
    self.panel.layer.shadowColor = UIColor.blackColor.CGColor;
    self.panel.layer.shadowOpacity = 0.45;
    self.panel.layer.shadowRadius = 14;
    self.panel.layer.shadowOffset = CGSizeMake(0, 5);
    self.panel.clipsToBounds = NO;
    [self.root addSubview:self.panel];

    self.panelHeader = [UIView new];
    [self.panel addSubview:self.panelHeader];
    [self.panelHeader addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanel:)]];

    UILabel *title = [self label:@"PhiMod" size:18 color:PMColor(0xfff1f5fa)];
    title.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    title.tag = 101;
    [self.panelHeader addSubview:title];

    UIButton *close = [self textButton:@"收起" action:@selector(togglePanel)];
    close.tag = 102;
    [self.panelHeader addSubview:close];

    self.statusLabel = [self label:@"iOS UI 预览 · 功能尚未接入" size:11 color:PMColor(0xff92a2b9)];
    [self.panel addSubview:self.statusLabel];

    self.tabBar = [[UIStackView alloc] init];
    self.tabBar.axis = UILayoutConstraintAxisHorizontal;
    self.tabBar.distribution = UIStackViewDistributionFillEqually;
    self.tabBar.spacing = 4;
    NSArray<NSString *> *tabs = @[@"谱库", @"章节", @"判定", @"模式", @"设置"];
    [tabs enumerateObjectsUsingBlock:^(NSString *name, NSUInteger idx, BOOL *stop) {
        UIButton *button = [self textButton:name action:@selector(selectTab:)];
        button.tag = 200 + (NSInteger)idx;
        button.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        [self.tabBar addArrangedSubview:button];
    }];
    [self.panel addSubview:self.tabBar];

    self.body = [[UIStackView alloc] init];
    self.body.axis = UILayoutConstraintAxisVertical;
    self.body.alignment = UIStackViewAlignmentFill;
    self.body.spacing = 10;
    self.scroll=[UIScrollView new];
    [self.panel addSubview:self.scroll];
    [self.scroll addSubview:self.body];
    self.body.translatesAutoresizingMaskIntoConstraints=NO;
    [NSLayoutConstraint activateConstraints:@[
      [self.body.leadingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.leadingAnchor],
      [self.body.trailingAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.trailingAnchor],
      [self.body.topAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.topAnchor],
      [self.body.bottomAnchor constraintEqualToAnchor:self.scroll.contentLayoutGuide.bottomAnchor],
      [self.body.widthAnchor constraintEqualToAnchor:self.scroll.frameLayoutGuide.widthAnchor]
    ]];

    self.selectedTab = 0;
    [self renderPage];
    [self layoutOverlay];
    self.open = NO;
    self.panel.hidden = YES;
}

- (void)layoutOverlay {
    if (!self.root) return;
    CGRect safe = UIEdgeInsetsInsetRect(self.root.bounds, self.root.safeAreaInsets);
    CGFloat panelWidth = MAX(1, MIN(420, CGRectGetWidth(safe) - 32));
    CGFloat panelHeight = MAX(1, MIN(480, CGRectGetHeight(safe) - 30));
    if (CGRectIsEmpty(self.panel.frame)) {
        CGFloat x = MIN(CGRectGetMinX(safe) + 76, CGRectGetMaxX(safe) - panelWidth);
        self.panel.frame = CGRectMake(MAX(CGRectGetMinX(safe) + 8, x), CGRectGetMinY(safe) + 14, panelWidth, panelHeight);
    } else {
        CGRect frame = self.panel.frame;
        frame.size = CGSizeMake(panelWidth, panelHeight);
        frame.origin.x = MIN(MAX(frame.origin.x, CGRectGetMinX(safe)), CGRectGetMaxX(safe) - panelWidth);
        frame.origin.y = MIN(MAX(frame.origin.y, CGRectGetMinY(safe)), CGRectGetMaxY(safe) - panelHeight);
        self.panel.frame = frame;
    }
    CGFloat inner = 16;
    self.panelHeader.frame = CGRectMake(inner, 10, panelWidth - inner * 2, 38);
    UIView *title = [self.panelHeader viewWithTag:101];
    UIView *close = [self.panelHeader viewWithTag:102];
    close.frame = CGRectMake(CGRectGetWidth(self.panelHeader.bounds) - 68, 1, 68, 34);
    title.frame = CGRectMake(0, 0, CGRectGetMinX(close.frame) - 8, 36);
    self.statusLabel.frame = CGRectMake(inner + 4, 50, panelWidth - inner * 2 - 8, 18);
    self.tabBar.frame = CGRectMake(inner, 72, panelWidth - inner * 2, 40);
    self.scroll.frame = CGRectMake(inner, 124, panelWidth - inner * 2, MAX(1, panelHeight - 140));
    [self clampBubble];
}

- (void)addSetting:(NSString *)key title:(NSString *)title boolean:(BOOL)boolean {
 UIStackView *row=[UIStackView new];row.axis=UILayoutConstraintAxisHorizontal;row.spacing=8;row.alignment=UIStackViewAlignmentCenter;
 UILabel *label=[self label:title size:13 color:PMColor(0xfff1f5fa)];[row addArrangedSubview:label];
 if(boolean){UISwitch *control=[UISwitch new];control.accessibilityIdentifier=key;control.on=[[[PMSettings shared] value:key] boolValue];[control addTarget:self action:@selector(settingSwitch:) forControlEvents:UIControlEventValueChanged];[row addArrangedSubview:control];}
 else {UITextField *field=[UITextField new];field.accessibilityIdentifier=key;field.text=[[[PMSettings shared] value:key] description];field.textColor=PMColor(0xff71e1cf);field.borderStyle=UITextBorderStyleRoundedRect;field.keyboardType=UIKeyboardTypeNumbersAndPunctuation;field.returnKeyType=UIReturnKeyDone;[field.widthAnchor constraintEqualToConstant:100].active=YES;[field addTarget:self action:@selector(settingNumber:) forControlEvents:UIControlEventEditingDidEnd];[field addTarget:field action:@selector(resignFirstResponder) forControlEvents:UIControlEventEditingDidEndOnExit];[row addArrangedSubview:field];}
 [self.body addArrangedSubview:row];
}
- (void)settingSwitch:(UISwitch *)sender {NSString *error=nil;BOOL ok=[[PMSettings shared] setValue:@(sender.on) forKey:sender.accessibilityIdentifier error:&error];if(!ok)sender.on=[[[PMSettings shared] value:sender.accessibilityIdentifier] boolValue];self.statusLabel.text=ok?@"配置已保存；尚未应用到游戏":error;}
- (void)settingNumber:(UITextField *)sender {
 NSScanner *scanner=[NSScanner scannerWithString:sender.text ?: @""];scanner.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];double number=0;NSString *error=nil;
 BOOL parsed=[scanner scanDouble:&number] && scanner.isAtEnd;
 BOOL ok=parsed && [[PMSettings shared] setValue:@(number) forKey:sender.accessibilityIdentifier error:&error];
 sender.text=[[[PMSettings shared] value:sender.accessibilityIdentifier] description];self.statusLabel.text=ok?@"配置已保存；尚未应用到游戏":(error ?: @"请输入有效数值");
 if(ok && [sender.accessibilityIdentifier isEqualToString:@"opacity"])self.bubble.alpha=number*(self.open?0.65:1);
}
- (void)probeRuntime {self.statusLabel.text=[PMRuntime probe];}
- (void)previewGameplay {NSDictionary *r=[PMGameplay previewConfiguration];self.statusLabel.text=r[@"message"] ?: @"配置错误";}
- (void)validateGameplay {NSDictionary *r=[PMGameplay validateConfiguration];self.statusLabel.text=r[@"message"] ?: @"配置错误";}
- (void)readGameSnapshot {
 NSDictionary *s=[PMRuntime gameSnapshot];
 if(![s[@"ok"] boolValue]){self.statusLabel.text=[@"读取失败：" stringByAppendingString:(s[@"message"] ?: @"未知错误")];return;}
 self.statusLabel.text=[NSString stringWithFormat:@"语言 %@ · P %.0f/G %.0f/B %.0f ms · RKS %.3f",s[@"language"], [s[@"perfectMs"] doubleValue],[s[@"goodMs"] doubleValue],[s[@"badMs"] doubleValue],[s[@"rks"] doubleValue]];
}
- (void)setChinese {NSDictionary *r=[PMRuntime setGameLanguage:6];self.statusLabel.text=r[@"message"] ?: @"完成";}
- (void)setEnglish {NSDictionary *r=[PMRuntime setGameLanguage:10];self.statusLabel.text=r[@"message"] ?: @"完成";}
- (void)renderPage {
 for(UIView *view in self.body.arrangedSubviews.copy){[self.body removeArrangedSubview:view];[view removeFromSuperview];}
 NSArray *names=@[@"谱库",@"章节",@"判定",@"模式",@"设置"];
 [self.body addArrangedSubview:[self label:names[self.selectedTab] size:18 color:PMColor(0xfff1f5fa)]];
 [self.body addArrangedSubview:[self label:@"设置页已接入游戏语言切换与状态读取（待真机验证）。判定／模式开关仍仅保存草案。" size:12 color:PMColor(0xff92a2b9)]];
 if(self.selectedTab==0 || self.selectedTab==1){[self.body addArrangedSubview:[self label:@"等待移植谱面存储、导入和游戏导航；不会修改原版曲库。" size:13 color:PMColor(0xff92a2b9)]];}
 if(self.selectedTab==2){[self addSetting:@"enabled" title:@"自定义判定（草案）" boolean:YES];[self addSetting:@"perfect" title:@"Perfect / ms" boolean:NO];[self addSetting:@"good" title:@"Good / ms" boolean:NO];[self addSetting:@"holdGrace" title:@"Hold 容错 / ms" boolean:NO];}
 if(self.selectedTab==3){
 NSArray *flags=@[@[@"autoplay",@"AutoPlay"],@[@"noise",@"噪域"],@[@"clearOriginalNoise",@"清除原噪域"],@[@"fullScreen",@"全屏判定"],@[@"noCombo",@"隐藏 Combo"],@[@"hpEnabled",@"HP 生存"],@[@"noiseVisual",@"噪域视觉"],@[@"hpTopEffect",@"顶部 HP 特效"],@[@"hpBackgroundEffect",@"背景 HP 特效"]];
 for(NSArray *p in flags)[self addSetting:p[0] title:p[1] boolean:YES];
 NSArray *numbers=@[@[@"unified",@"统一键型 0–4"],@[@"challenge",@"挑战 0关 / 1AP / 2FC"],@[@"radius",@"噪域半径"],@[@"noiseGrace",@"噪域容错 / ms"],@[@"holdFx",@"Hold 特效间隔 / ms"],@[@"hpMax",@"最大 HP"],@[@"hpPerfect",@"Perfect HP 增减"],@[@"hpGood",@"Good HP 增减"],@[@"hpBad",@"Bad HP 增减"],@[@"hpMiss",@"Miss HP 增减"],@[@"hpRed",@"红色阈值 %"],@[@"hpBlue",@"蓝色阈值 %"]];
 for(NSArray *p in numbers)[self addSetting:p[0] title:p[1] boolean:NO];
 }
 if(self.selectedTab==4){[self addSetting:@"opacity" title:@"浮窗透明度 0.15–1（立即生效）" boolean:NO];[self addSetting:@"showShortcuts" title:@"选曲快捷按钮（待接入）" boolean:YES];[self.body addArrangedSubview:[self textButton:@"读取游戏状态（实际读取）" action:@selector(readGameSnapshot)]];[self.body addArrangedSubview:[self textButton:@"切换中文" action:@selector(setChinese)]];[self.body addArrangedSubview:[self textButton:@"切换 English" action:@selector(setEnglish)]];[self.body addArrangedSubview:[self textButton:@"只读探测 IL2CPP" action:@selector(probeRuntime)]];}
 [self.body addArrangedSubview:[self textButton:@"玩法核心配置校验（不应用）" action:@selector(validateGameplay)]];
 [self.body addArrangedSubview:[self textButton:@"玩法核心预览（不应用）" action:@selector(previewGameplay)]];
 [self.body addArrangedSubview:[self textButton:@"UI 自检" action:@selector(runSelfTest)]];
 for(UIButton *button in self.tabBar.arrangedSubviews){BOOL selected=button.tag==200+self.selectedTab;button.backgroundColor=selected?PMColor(0xff71e1cf):PMColor(0xff252f40);[button setTitleColor:selected?PMColor(0xff142b35):PMColor(0xfff1f5fa) forState:UIControlStateNormal];}
 self.scroll.contentOffset=CGPointZero;
}

- (void)togglePanel {
    self.open = !self.open;
    self.panel.hidden = !self.open;
    self.bubble.alpha = [[[PMSettings shared] value:@"opacity"] doubleValue] * (self.open ? 0.65 : 1.0);
    if (self.open) {
        [self.root bringSubviewToFront:self.panel];
        [self.root bringSubviewToFront:self.bubble];
    }
}

- (void)selectTab:(UIButton *)sender {
    self.selectedTab = sender.tag - 200;
    [self renderPage];
}

- (void)runSelfTest {
    self.statusLabel.text = [NSString stringWithFormat:@"UI 正常 · %@", [NSDateFormatter localizedStringFromDate:NSDate.date dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle]];
}

- (void)dragBubble:(UIPanGestureRecognizer *)gesture {
    CGPoint delta = [gesture translationInView:self.root];
    CGPoint center = self.bubble.center;
    center.x += delta.x; center.y += delta.y;
    self.bubble.center = center;
    [gesture setTranslation:CGPointZero inView:self.root];
    [self clampBubble];
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) [self saveBubblePosition];
}

- (void)dragPanel:(UIPanGestureRecognizer *)gesture {
    CGPoint delta = [gesture translationInView:self.root];
    CGRect frame = self.panel.frame;
    frame.origin.x += delta.x; frame.origin.y += delta.y;
    self.panel.frame = frame;
    [gesture setTranslation:CGPointZero inView:self.root];
    CGRect safe = UIEdgeInsetsInsetRect(self.root.bounds, self.root.safeAreaInsets);
    frame = self.panel.frame;
    frame.origin.x = MIN(MAX(frame.origin.x, CGRectGetMinX(safe)), CGRectGetMaxX(safe) - CGRectGetWidth(frame));
    frame.origin.y = MIN(MAX(frame.origin.y, CGRectGetMinY(safe)), CGRectGetMaxY(safe) - CGRectGetHeight(frame));
    self.panel.frame = frame;
}

- (void)clampBubble {
    CGRect safe = UIEdgeInsetsInsetRect(self.root.bounds, self.root.safeAreaInsets);
    CGRect frame = self.bubble.frame;
    frame.origin.x = MIN(MAX(frame.origin.x, CGRectGetMinX(safe)), CGRectGetMaxX(safe) - CGRectGetWidth(frame));
    frame.origin.y = MIN(MAX(frame.origin.y, CGRectGetMinY(safe)), CGRectGetMaxY(safe) - CGRectGetHeight(frame));
    self.bubble.frame = frame;
}

- (void)saveBubblePosition {
    CGRect bounds = self.root.bounds;
    if (CGRectGetWidth(bounds) <= 0 || CGRectGetHeight(bounds) <= 0) return;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setDouble:self.bubble.center.x / CGRectGetWidth(bounds) forKey:PMBubbleXKey];
    [defaults setDouble:self.bubble.center.y / CGRectGetHeight(bounds) forKey:PMBubbleYKey];
}

- (void)restoreBubblePosition {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:PMBubbleXKey] && [defaults objectForKey:PMBubbleYKey]) {
        self.bubble.center = CGPointMake([defaults doubleForKey:PMBubbleXKey] * CGRectGetWidth(self.root.bounds),
                                         [defaults doubleForKey:PMBubbleYKey] * CGRectGetHeight(self.root.bounds));
        [self clampBubble];
    }
}
@end

void PhiModInstallOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[PMOverlayController shared] install]; });
}

__attribute__((constructor)) static void PhiModEntry(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(__unused NSNotification *note) { PhiModInstallOverlay(); }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ PhiModInstallOverlay(); });
    });
}
