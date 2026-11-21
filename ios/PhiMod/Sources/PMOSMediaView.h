#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Main-thread view for a local chapter GIF or MP4. fill selects aspect fill or aspect fit.
@interface PMOSMediaView : UIView
- (instancetype)initWithPath:(NSString *)path loop:(BOOL)loop fill:(BOOL)fill;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

/// Playback starts on window attachment. Forward page visibility here if an ancestor hides the page.
/// NO releases playback resources. A subsequent YES restarts from the beginning.
- (void)setPlaying:(BOOL)playing;
@end

NS_ASSUME_NONNULL_END
