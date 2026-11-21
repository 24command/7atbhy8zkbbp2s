#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A read-only Chapter OS detail panel. Give the view a frame or constrain its size.
/// A finite, nonnegative duration is displayed in seconds. Pass a negative value to omit it.
@interface PMOSSpeechView : UIView
- (instancetype)initWithSeconds:(double)seconds
                        heading:(NSString *)heading
                     transcript:(NSString *)transcript NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
