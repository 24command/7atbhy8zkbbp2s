#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@class PMNativeOSProgram;
@class PMNativeOSEntryTimeline;
typedef void (^PMNativeOSEntryTimelineCompletion)(PMNativeOSEntryTimeline * _Nullable timeline,
                                                NSError * _Nullable error);

// A transient, input-transparent entry overlay; never acquires the native OS map
// or invokes Lua. The presenter owns insertion/removal and the playback clock.
@interface PMNativeOSEntryTimeline : NSObject
// Always completes asynchronously on the main queue, including invalid input.
// Uses program.nodes at the original global indices on entryTransition.screen.
// PNG/JPG/WebP sources decode serially off-main. Repeated resolved paths share
// one bitmap; per preparation: <=32 MiB retained, <=2048px output edge,
// <=32 MiB/16 Mi-pixel source (oversized/animated/invalid resources fail closed).
// Failure returns nil/error so the host can choose native covered entry.
+ (void)prepareWithProgram:(PMNativeOSProgram *)program
               completion:(PMNativeOSEntryTimelineCompletion)completion;
// Main-thread UIKit view. Size it to the presentation bounds; normalized child
// geometry and the canvas aspect-fit are recomputed when its bounds change.
@property(nonatomic, readonly) UIView *view;
// Main thread only. Absolute seconds (not deltas), safely seekable/repeatable.
// Samples at/after the end hold the last authored frame; no timer is owned here.
- (void)sample:(double)seconds;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_ASSUME_NONNULL_END
