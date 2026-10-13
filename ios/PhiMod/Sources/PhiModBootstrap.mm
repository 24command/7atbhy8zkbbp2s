#import <UIKit/UIKit.h>
#import "PhiModBootstrap.h"

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
    [self.panel addSubview:self.body];

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
    self.body.frame = CGRectMake(inner, 124, panelWidth - inner * 2, panelHeight - 140);
    [self clampBubble];
}

- (void)renderPage {
    for (UIView *view in self.body.arrangedSubviews.copy) {
        [self.body removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    NSArray *names = @[@"谱库", @"章节", @"判定", @"模式", @"设置"];
    self.pageTitle = [self label:names[self.selectedTab] size:18 color:PMColor(0xfff1f5fa)];
    self.pageTitle.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    [self.body addArrangedSubview:self.pageTitle];
    UILabel *notice = [self label:@"当前阶段仅验证 iOS 浮窗加载、触摸穿透、拖动和页面结构。游戏功能将在完成 IL2CPP 定位后接入。" size:13 color:PMColor(0xff92a2b9)];
    [self.body addArrangedSubview:notice];
    UIButton *test = [self textButton:@"UI 自检" action:@selector(runSelfTest)];
    [self.body addArrangedSubview:test];
    UIView *spacer = [UIView new];
    [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
    [self.body addArrangedSubview:spacer];
    for (UIButton *button in self.tabBar.arrangedSubviews) {
        BOOL selected = button.tag == 200 + self.selectedTab;
        button.backgroundColor = selected ? PMColor(0xff71e1cf) : PMColor(0xff252f40);
        [button setTitleColor:selected ? PMColor(0xff142b35) : PMColor(0xfff1f5fa) forState:UIControlStateNormal];
    }
}

- (void)togglePanel {
    self.open = !self.open;
    self.panel.hidden = !self.open;
    self.bubble.alpha = self.open ? 0.65 : 1.0;
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
