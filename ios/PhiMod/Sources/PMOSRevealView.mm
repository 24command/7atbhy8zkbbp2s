#import "PMOSRevealView.h"
#import <QuartzCore/QuartzCore.h>

@interface PMOSRevealView ()
@property(nonatomic,strong) UIView *ring, *panel;
@property(nonatomic,weak) UIView *anchor;
@property(nonatomic,copy) void (^completion)(PMOSRevealChoice);
@end

@implementation PMOSRevealView
- (instancetype)initWithTitle:(NSString *)title text:(NSString *)text hasSong:(BOOL)hasSong {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.accessibilityViewIsModal = YES;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:.45];
    _ring = [UIView new];
    _ring.layer.borderColor = UIColor.whiteColor.CGColor;
    _ring.layer.borderWidth = 2;
    _ring.layer.cornerRadius = 6;
    [self addSubview:_ring];

    UILabel *heading = [UILabel new];
    heading.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    heading.textColor = UIColor.whiteColor;
    heading.numberOfLines = 2;
    heading.text = title;
    UITextView *body = [UITextView new];
    body.backgroundColor = UIColor.clearColor;
    body.textColor = UIColor.whiteColor;
    body.editable = NO;
    body.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    body.text = text;

    UIStackView *buttons = [UIStackView new];
    buttons.distribution = UIStackViewDistributionFillEqually;
    NSArray *labels = hasSong ? @[@"继续", @"曲目详情", @"开始演奏"] : @[@"继续"];
    for (NSUInteger i = 0; i < labels.count; ++i) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:labels[i] forState:UIControlStateNormal];
        button.tintColor = UIColor.whiteColor;
        button.tag = i;
        [button addTarget:self action:@selector(chose:) forControlEvents:UIControlEventTouchUpInside];
        [buttons addArrangedSubview:button];
    }
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[heading, body, buttons]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.layoutMargins = UIEdgeInsetsMake(12, 16, 8, 16);
    stack.layoutMarginsRelativeArrangement = YES;
    stack.backgroundColor = [UIColor colorWithWhite:.10 alpha:.98];
    stack.layer.cornerRadius = 10;
    stack.hidden = YES;
    [self addSubview:stack];
    _panel = stack;
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect safe = UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets);
    CGFloat w = MIN(480, CGRectGetWidth(safe) * .92), h = MIN(250, CGRectGetHeight(safe) * .65);
    CGRect focus = [self.anchor convertRect:self.anchor.bounds toView:self];
    if (self.anchor) self.ring.frame = focus;
    CGFloat y = CGRectGetMidY(focus) < CGRectGetMidY(safe) ? CGRectGetMaxY(safe)-h-8 : CGRectGetMinY(safe)+8;
    self.panel.frame = CGRectMake(CGRectGetMidX(safe)-w/2, y, w, h);
}

- (void)focusFrom:(UIView *)source to:(UIView *)target completion:(void (^)(PMOSRevealChoice))completion {
    self.completion = completion;
    self.ring.frame = [source convertRect:source.bounds toView:self];
    self.anchor = target;
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : .38 animations:^{
        self.ring.frame = [target convertRect:target.bounds toView:self];
    } completion:^(BOOL finished) {
        if (!self.completion) return;
        [self setNeedsLayout];
        self.panel.hidden = NO;
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, self.panel.subviews.firstObject);
    }];
}

- (void)chose:(UIButton *)button {
    if (self.panel.hidden) return;
    [self finish:(PMOSRevealChoice)button.tag];
}

- (BOOL)accessibilityPerformEscape {
    [self finish:PMOSRevealResume];
    return YES;
}

- (void)finish:(PMOSRevealChoice)choice {
    void (^done)(PMOSRevealChoice) = self.completion;
    [self cancel];
    if (done) done(choice);
}

- (void)cancel {
    self.completion = nil;
    [self.ring.layer removeAllAnimations];
    [self removeFromSuperview];
}
@end
