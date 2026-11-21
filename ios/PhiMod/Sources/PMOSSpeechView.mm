#import "PMOSSpeechView.h"
#include <cmath>

static UILabel *SpeechLabel(NSString *text, UIFontTextStyle style) {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [UIFont preferredFontForTextStyle:style];
    label.adjustsFontForContentSizeCategory = YES;
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.textAlignment = NSTextAlignmentNatural;
    label.textColor = UIColor.whiteColor;
    label.isAccessibilityElement = YES;
    return label;
}

@implementation PMOSSpeechView

- (instancetype)initWithSeconds:(double)seconds
                        heading:(NSString *)heading
                     transcript:(NSString *)transcript {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    self.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    self.layer.cornerRadius = 8;
    self.clipsToBounds = YES;
    self.isAccessibilityElement = NO;

    // Scroll the heading and duration with the transcript even in a short viewport.
    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    scroll.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    scroll.showsHorizontalScrollIndicator = NO;
    [self addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    stack.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(10, 14, 10, 14);
    stack.layoutMarginsRelativeArrangement = YES;
    [scroll addSubview:stack];

    if (heading.length) {
        UILabel *title = SpeechLabel(heading, UIFontTextStyleHeadline);
        title.accessibilityTraits |= UIAccessibilityTraitHeader;
        [stack addArrangedSubview:title];
    }

    if (std::isfinite(seconds) && seconds >= 0) {
        NSMeasurement *duration = [[NSMeasurement alloc] initWithDoubleValue:seconds unit:NSUnitDuration.seconds];
        NSMeasurementFormatter *formatter = [[NSMeasurementFormatter alloc] init];
        formatter.unitOptions = NSMeasurementFormatterUnitOptionsProvidedUnit;
        formatter.unitStyle = NSFormattingUnitStyleShort;
        formatter.numberFormatter.maximumFractionDigits = 2;
        UILabel *length = SpeechLabel([formatter stringFromMeasurement:duration], UIFontTextStyleFootnote);
        length.textColor = [UIColor colorWithWhite:0.82 alpha:1];
        formatter.unitStyle = NSFormattingUnitStyleLong;
        length.accessibilityLabel = [formatter stringFromMeasurement:duration];
        [stack addArrangedSubview:length];
    }

    if (transcript.length) {
        if (stack.arrangedSubviews.count) {
            // A flat signal baseline is decorative. No audio samples are available here.
            UIView *baseline = [[UIView alloc] init];
            baseline.backgroundColor = [UIColor colorWithWhite:0.48 alpha:1];
            baseline.isAccessibilityElement = NO;
            [stack addArrangedSubview:baseline];
            [baseline.heightAnchor constraintEqualToConstant:1].active = YES;
        }
        [stack addArrangedSubview:SpeechLabel(transcript, UIFontTextStyleBody)];
    }

    UILayoutGuide *content = scroll.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:content.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
    ]];
    return self;
}

@end
