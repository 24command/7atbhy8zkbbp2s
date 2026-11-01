#import "PMAvatarUI.h"
#import <UIKit/UIKit.h>
#import "PhiModBootstrap.h"
#import "PMSettings.h"
#import "PMRuntime.h"
#import "PMGameplay.h"
#import "PMHookBackend.h"
#import "PMDiagnostics.h"
#import "PMPracticeControls.h"
#import "PMContentUI.h"
#import "PMResourcePackUI.h"

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
@property(nonatomic, strong) PMPracticeControls *practiceControls;
@property(nonatomic, strong) UIView *panelHeader;
@property(nonatomic, strong) UILabel *pageTitle;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIStackView *tabBar;
@property(nonatomic, strong) UIStackView *body;
@property(nonatomic, strong) UIScrollView *scroll;
@property(nonatomic, assign) NSInteger selectedTab;
@property(nonatomic, assign) NSInteger selectedModeCategory;
@property(nonatomic, assign) BOOL open;
+ (instancetype)shared;
- (void)install;
- (void)resumeJudgeAttempt:(NSInteger)attempt;
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
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows)
            if (!candidate.hidden && candidate.alpha > 0) return candidate;
    }
    return nil;
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
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
        configuration.contentInsets = NSDirectionalEdgeInsetsMake(7, 10, 7, 10);
        button.configuration = configuration;
    } else {
        // UIButtonConfiguration above provides the iOS 15+ content insets.
    }
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
    [self resumeJudgeAttempt:0];
}

- (void)resumeJudgeAttempt:(NSInteger)attempt {
    NSDictionary *backend=[PMHookBackend install];
    if (![backend[@"ok"] boolValue]) {
        self.statusLabel.text=backend[@"message"];
        if(attempt<60 && ![backend[@"failedClosed"] boolValue])
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)NSEC_PER_SEC),dispatch_get_main_queue(),^{ [self resumeJudgeAttempt:attempt+1]; });
        return;
    }
    NSDictionary *s=[[PMSettings shared] snapshot];
    if (![s[@"enabled"] boolValue]) { self.statusLabel.text=backend[@"message"]; return; }
    NSDictionary *r=[PMRuntime applyJudgeSettings:YES perfectMs:[s[@"perfect"] doubleValue] goodMs:[s[@"good"] doubleValue]];
    self.statusLabel.text=r[@"message"];
}
- (void)buildInWindow:(UIWindow *)window {
    self.root = [[PMPassthroughView alloc] initWithFrame:window.bounds];
    __weak PMOverlayController *weakSelf = self;
    self.root.layoutCallback = ^{ [weakSelf layoutOverlay]; };
    self.root.tag = PMOverlayRootTag;
    self.root.backgroundColor = UIColor.clearColor;
    self.root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [window addSubview:self.root];
    self.practiceControls=[[PMPracticeControls alloc]initWithFrame:CGRectZero];
    [self.root addSubview:self.practiceControls];

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

    self.statusLabel = [self label:@"PhiMod · 正在连接游戏引擎" size:11 color:PMColor(0xff92a2b9)];
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
    self.selectedModeCategory = 0;
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
    self.statusLabel.frame = CGRectMake(inner + 4, 50, panelWidth - inner * 2 - 8, 38);
    self.tabBar.frame = CGRectMake(inner, 94, panelWidth - inner * 2, 40);
    self.scroll.frame = CGRectMake(inner, 146, panelWidth - inner * 2, MAX(1, panelHeight - 162));
    [self clampBubble];
}

- (void)addSetting:(NSString *)key title:(NSString *)title boolean:(BOOL)boolean {
 NSSet *pending=[NSSet setWithArray:@[@"skinEnabled",@"customDrawer",@"legacyEffects"]];BOOL supported=![pending containsObject:key];
 UIStackView *row=[UIStackView new];row.alpha=supported?1:.4;row.userInteractionEnabled=supported;row.axis=UILayoutConstraintAxisHorizontal;row.spacing=8;row.alignment=UIStackViewAlignmentCenter;row.layoutMarginsRelativeArrangement=YES;row.layoutMargins=UIEdgeInsetsMake(8,12,8,12);row.backgroundColor=PMColor(0xff222c3c);row.layer.cornerRadius=10;
 UILabel *label=[self label:title size:13 color:PMColor(0xfff1f5fa)];[row addArrangedSubview:label];
 if(boolean){UISwitch *control=[UISwitch new];control.accessibilityIdentifier=key;control.on=[[[PMSettings shared] value:key] boolValue];[control addTarget:self action:@selector(settingSwitch:) forControlEvents:UIControlEventValueChanged];[row addArrangedSubview:control];}
 else {UITextField *field=[UITextField new];field.accessibilityIdentifier=key;field.text=[[[PMSettings shared] value:key] description];field.textColor=PMColor(0xff71e1cf);field.borderStyle=UITextBorderStyleRoundedRect;field.keyboardType=UIKeyboardTypeNumbersAndPunctuation;field.returnKeyType=UIReturnKeyDone;[field.widthAnchor constraintEqualToConstant:100].active=YES;[field addTarget:self action:@selector(settingNumber:) forControlEvents:UIControlEventEditingDidEnd];[field addTarget:field action:@selector(resignFirstResponder) forControlEvents:UIControlEventEditingDidEndOnExit];[row addArrangedSubview:field];}
 [self.body addArrangedSubview:row];
}
- (void)settingSwitch:(UISwitch *)sender {[self.root endEditing:YES];NSString *error=nil;BOOL ok=[[PMSettings shared] setValue:@(sender.on) forKey:sender.accessibilityIdentifier error:&error];if(!ok)sender.on=[[[PMSettings shared] value:sender.accessibilityIdentifier] boolValue];self.statusLabel.text=ok?@"已保存；玩法模式在下一首生效":error;
 if(ok && [sender.accessibilityIdentifier isEqualToString:@"enabled"]) { NSDictionary *s=[[PMSettings shared] snapshot]; NSDictionary *r=[PMRuntime applyJudgeSettings:[s[@"enabled"] boolValue] perfectMs:[s[@"perfect"] doubleValue] goodMs:[s[@"good"] doubleValue]]; self.statusLabel.text=r[@"message"] ?: @"Judge apply failed"; if(![r[@"ok"] boolValue]){[[PMSettings shared] setValue:@NO forKey:@"enabled" error:nullptr]; [self renderPage];} }
}
- (void)settingNumber:(UITextField *)sender {
 NSScanner *scanner=[NSScanner scannerWithString:sender.text ?: @""];scanner.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];double number=0;NSString *error=nil;
 BOOL parsed=[scanner scanDouble:&number] && scanner.isAtEnd;
 BOOL ok=parsed && [[PMSettings shared] setValue:@(number) forKey:sender.accessibilityIdentifier error:&error];
 sender.text=[[[PMSettings shared] value:sender.accessibilityIdentifier] description];self.statusLabel.text=ok?@"已保存；玩法模式在下一首生效":(error ?: @"请输入有效数字");
 if(ok && [[[PMSettings shared] value:@"enabled"] boolValue] && ([sender.accessibilityIdentifier isEqualToString:@"perfect"] || [sender.accessibilityIdentifier isEqualToString:@"good"])) { NSDictionary *s=[[PMSettings shared] snapshot]; NSDictionary *r=[PMRuntime applyJudgeSettings:[s[@"enabled"] boolValue] perfectMs:[s[@"perfect"] doubleValue] goodMs:[s[@"good"] doubleValue]]; self.statusLabel.text=r[@"message"] ?: @"Judge apply failed"; if(![r[@"ok"] boolValue]){[[PMSettings shared] setValue:@NO forKey:@"enabled" error:nullptr]; [self renderPage];} }
 if(ok && [sender.accessibilityIdentifier isEqualToString:@"opacity"])self.bubble.alpha=number*(self.open?0.65:1);
}
- (void)probeRuntime {self.statusLabel.text=[PMRuntime probe];}
- (void)copyDiagnostics {UIPasteboard.generalPasteboard.string=PMDiagnosticsTail(400);self.statusLabel.text=[NSString stringWithFormat:@"诊断日志已复制：%@",PMDiagnosticsPath().lastPathComponent];}
- (void)clearDiagnostics {PMDiagnosticsClear();self.statusLabel.text=@"诊断日志已清空";}
- (void)previewGameplay {NSDictionary *r=[PMGameplay previewConfiguration];self.statusLabel.text=r[@"message"] ?: @"配置错误";}
- (void)validateGameplay {NSDictionary *r=[PMGameplay validateConfiguration];self.statusLabel.text=r[@"message"] ?: @"配置错误";}
- (void)readGameSnapshot {
 NSDictionary *s=[PMRuntime gameSnapshot];
 if(![s[@"ok"] boolValue]){self.statusLabel.text=[@"读取失败：" stringByAppendingString:(s[@"message"] ?: @"未知错误")];return;}
 self.statusLabel.text=[NSString stringWithFormat:@"P %.0f/G %.0f/B %.0f ms | %@%@",[s[@"perfectMs"] doubleValue],[s[@"goodMs"] doubleValue],[s[@"badMs"] doubleValue],s[@"judgeStatus"],[s[@"judgeHookReady"] boolValue]?@"":@" (hook missing)"];
}
- (void)setChinese {NSDictionary *r=[PMRuntime setGameLanguage:6];self.statusLabel.text=r[@"message"] ?: @"完成";}
- (void)setEnglish {NSDictionary *r=[PMRuntime setGameLanguage:10];self.statusLabel.text=r[@"message"] ?: @"完成";}
- (void)selectModeCategory:(UISegmentedControl *)sender {self.selectedModeCategory=sender.selectedSegmentIndex;[self renderPage];}
- (void)practiceCommand:(UIButton *)sender {NSDictionary *r=[PMHookBackend practiceCommand:sender.tag-700];self.statusLabel.text=r[@"message"] ?: @"Practice command unavailable";}
- (void)refreshPracticeStatus {NSDictionary *r=[PMHookBackend practiceStatus];self.statusLabel.text=r[@"message"] ?: @"Practice status unavailable";}
- (void)openLibrary {self.open=NO;self.panel.hidden=YES;PMShowContent(self.root,NO);}
- (void)openChapters {self.open=NO;self.panel.hidden=YES;PMShowContent(self.root,YES);}
- (void)openAvatar {PMShowAvatarMenu(self.root);}
- (void)openResourcePack {PMShowResourcePackPicker(self.root);}
- (void)renderPage {
 for(UIView *view in self.body.arrangedSubviews.copy){[self.body removeArrangedSubview:view];[view removeFromSuperview];}
 NSArray *names=@[@"谱库",@"章节",@"判定",@"模式",@"设置"];
 [self.body addArrangedSubview:[self label:names[self.selectedTab] size:18 color:PMColor(0xfff1f5fa)]];
 [self.body addArrangedSubview:[self label:@"选曲页可直接切换模式；完整设置位于游戏设置的 MOD 页。请先备份存档。" size:12 color:PMColor(0xff92a2b9)]];
 if(self.selectedTab==0 || self.selectedTab==1){[self.body addArrangedSubview:[self label:@"ZIP / PEZ、原生 JSON / PEC / RPE 谱包。文件保存在应用 Documents/PhiMod，可导入多文件、分组、编辑章节与导出。" size:13 color:PMColor(0xff92a2b9)]];[self.body addArrangedSubview:[self textButton:self.selectedTab==0?@"打开谱库管理":@"打开章节管理" action:self.selectedTab==0?@selector(openLibrary):@selector(openChapters)]];}
 if(self.selectedTab==2){[self addSetting:@"enabled" title:@"自定义判定（应用到游戏）" boolean:YES];[self addSetting:@"perfect" title:@"Perfect / ms" boolean:NO];[self addSetting:@"good" title:@"Good / ms" boolean:NO];[self addSetting:@"holdGrace" title:@"噪域 Hold 容错 / ms" boolean:NO];}
 if(self.selectedTab==3){
  NSArray *categories=@[@"模式",@"练习",@"噪域",@"HP"];
  UISegmentedControl *seg=[[UISegmentedControl alloc]initWithItems:categories];seg.selectedSegmentIndex=self.selectedModeCategory;seg.tintColor=PMColor(0xff71e1cf);[seg addTarget:self action:@selector(selectModeCategory:) forControlEvents:UIControlEventValueChanged];[self.body addArrangedSubview:seg];
  if(self.selectedModeCategory==0){
   [self.body addArrangedSubview:[self label:@"单曲模式 · 配置对下一首生效" size:12 color:PMColor(0xff92a2b9)]];
   [self addSetting:@"autoplay" title:@"AutoPlay" boolean:YES];
   [self addSetting:@"fullScreen" title:@"全屏判定" boolean:YES];
   [self addSetting:@"accuracy" title:@"Accuracy（选曲页实时 ACC）" boolean:YES];
   [self addSetting:@"noCombo" title:@"去连击分（MOD 计分模式）" boolean:YES];
   [self addSetting:@"unified" title:@"统一键型：0 关闭 / 1 Tap / 2 Drag / 3 Hold / 4 Flick" boolean:NO];
   [self addSetting:@"challenge" title:@"AP / FC 挑战：0 关闭 / 1 AP / 2 FC" boolean:NO];
  }else if(self.selectedModeCategory==1){
   [self.body addArrangedSubview:[self label:@"区间练习在谱面与音乐加载后暂停。开始或重复区间会清空本段计分；区间练习及非 1× 倍速不保存成绩。倍速可在练习中应用。" size:12 color:PMColor(0xff92a2b9)]];
   [self addSetting:@"practiceMode" title:@"启用区间练习（下一首生效）" boolean:YES];
   [self addSetting:@"playbackRate" title:@"播放倍速 0–5×（下一首生效；练习时可应用）" boolean:NO];
   [self addSetting:@"practiceStart" title:@"区间起点 / 秒" boolean:NO];
   [self addSetting:@"practiceEnd" title:@"区间终点 / 秒（-1 为曲尾）" boolean:NO];
   [self addSetting:@"practicePosition" title:@"定位位置 / 秒" boolean:NO];
   [self addSetting:@"practiceLoop" title:@"到终点后循环本区间" boolean:YES];
   [self addSetting:@"practiceCountdown" title:@"开始区间前倒数 3 秒" boolean:YES];
   [self addSetting:@"practiceWhiteUi" title:@"白色区间 UI（练习面板也可切换）" boolean:YES];
   [self addSetting:@"noteFlowEnabled" title:@"启用练习流速调整" boolean:YES];
   [self addSetting:@"noteFlow" title:@"音符流速 0–5×" boolean:NO];
   for(NSArray *entry in @[@[@"开始区间",@0],@[@"暂停 / 继续",@1],@[@"重播区间",@2],@[@"播放整首",@3],@[@"应用当前练习倍速",@4],@[@"定位并播放",@5],@[@"应用起止 / 循环 / 倒数",@6],@[@"定位并暂停预览",@7]]){UIButton *b=[self textButton:entry[0] action:@selector(practiceCommand:)];b.tag=700+[entry[1] integerValue];[self.body addArrangedSubview:b];}
   [self.body addArrangedSubview:[self textButton:@"刷新练习状态" action:@selector(refreshPracticeStatus)]];
  }else if(self.selectedModeCategory==2){
   [self addSetting:@"noise" title:@"噪域" boolean:YES];
   [self addSetting:@"clearOriginalNoise" title:@"清除原谱噪域" boolean:YES];
   [self addSetting:@"noiseVisual" title:@"显示噪域视觉" boolean:YES];
   [self addSetting:@"radius" title:@"噪域半径" boolean:NO];
   [self addSetting:@"noiseGrace" title:@"噪域容错 / ms" boolean:NO];
   [self addSetting:@"holdGrace" title:@"Hold 容错 / ms" boolean:NO];
   [self addSetting:@"holdFx" title:@"Hold 特效间隔 / ms" boolean:NO];
  }else{
   [self addSetting:@"hpEnabled" title:@"HP 生存" boolean:YES];
   [self addSetting:@"hpTopEffect" title:@"顶部 HP 特效" boolean:YES];
   [self addSetting:@"hpBackgroundEffect" title:@"背景 HP 特效" boolean:YES];
   [self addSetting:@"hpMax" title:@"最大 HP" boolean:NO];
   [self addSetting:@"hpPerfect" title:@"Perfect HP 增减" boolean:NO];
   [self addSetting:@"hpGood" title:@"Good HP 增减" boolean:NO];
   [self addSetting:@"hpBad" title:@"Bad HP 增减" boolean:NO];
   [self addSetting:@"hpMiss" title:@"Miss HP 增减" boolean:NO];
   [self addSetting:@"hpRed" title:@"红色阈值 %" boolean:NO];
   [self addSetting:@"hpBlue" title:@"蓝色阈值 %" boolean:NO];
  }
 }

 if(self.selectedTab==4){[self.body addArrangedSubview:[self textButton:@"\u81ea\u5b9a\u4e49\u5934\u50cf" action:@selector(openAvatar)]];[self addSetting:@"opacity" title:@"浮窗透明度 0.15–1（立即生效）" boolean:NO];[self addSetting:@"showShortcuts" title:@"选曲快捷按钮" boolean:YES];[self addSetting:@"shortcutAutoPlay" title:@"\u9009\u66f2\u5feb\u6377\uff1aAutoPlay" boolean:YES];[self addSetting:@"shortcutNoise" title:@"\u9009\u66f2\u5feb\u6377\uff1a\u566a\u57df" boolean:YES];[self addSetting:@"shortcutUnified" title:@"\u9009\u66f2\u5feb\u6377\uff1a\u7edf\u4e00\u952e\u578b" boolean:YES];[self addSetting:@"shortcutChallenge" title:@"\u9009\u66f2\u5feb\u6377\uff1aAP / FC" boolean:YES];[self addSetting:@"shortcutHp" title:@"\u9009\u66f2\u5feb\u6377\uff1aHP" boolean:YES];[self addSetting:@"shortcutFullScreen" title:@"\u9009\u66f2\u5feb\u6377\uff1a\u5168\u5c4f\u5224\u5b9a" boolean:YES];[self addSetting:@"shortcutAccuracy" title:@"\u9009\u66f2\u5feb\u6377\uff1a\u5b9e\u65f6 ACC" boolean:YES];[self addSetting:@"dynamicLargeTextures" title:@"大型纹理（最长边 4096；更高内存占用）" boolean:YES];[self addSetting:@"skinEnabled" title:@"\u5934\u50cf / \u8d44\u6e90\u5305\uff08\u6e38\u620f\u5185\u5e94\u7528\u5f85\u63a5\u5165\uff09" boolean:YES];[self addSetting:@"customDrawer" title:@"\u81ea\u5b9a\u4e49\u5feb\u6377\u62bd\u5c49\uff08\u5f85\u63a5\u5165\uff09" boolean:YES];[self addSetting:@"legacyEffects" title:@"\u65e7\u8c31\u4e13\u5c5e\u7279\u6548\uff08\u5f85\u63a5\u5165\uff09" boolean:YES];[self.body addArrangedSubview:[self label:@"RPE 视频与 Shader 扩展由谱面资源自动检测；资源包导入和主线解锁配置在 MOD 设置页管理。" size:12 color:PMColor(0xffffca80)]];[self.body addArrangedSubview:[self textButton:@"\u9009\u62e9 / \u5bfc\u5165\u97f3\u7b26\u76ae\u80a4" action:@selector(openResourcePack)]];[self.body addArrangedSubview:[self textButton:@"读取游戏状态（实际读取）" action:@selector(readGameSnapshot)]];[self.body addArrangedSubview:[self textButton:@"切换中文" action:@selector(setChinese)]];[self.body addArrangedSubview:[self textButton:@"切换 English" action:@selector(setEnglish)]];[self.body addArrangedSubview:[self textButton:@"只读探测 IL2CPP" action:@selector(probeRuntime)]];}
 if(self.selectedTab==4){[self.body addArrangedSubview:[self textButton:@"复制诊断日志" action:@selector(copyDiagnostics)]];[self.body addArrangedSubview:[self textButton:@"清空诊断日志" action:@selector(clearDiagnostics)]];}
 if(self.selectedTab==2){[self.body addArrangedSubview:[self textButton:@"检查玩法配置" action:@selector(validateGameplay)]];[self.body addArrangedSubview:[self textButton:@"预览下局配置（不应用）" action:@selector(previewGameplay)]];}
 if(self.selectedTab==4)[self.body addArrangedSubview:[self textButton:@"UI 自检" action:@selector(runSelfTest)]];
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
    PMDiagnosticsBeginSession();
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:NSOperationQueue.mainQueue
                                                      usingBlock:^(__unused NSNotification *note) { PhiModInstallOverlay(); }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ PhiModInstallOverlay(); });
    });
}
