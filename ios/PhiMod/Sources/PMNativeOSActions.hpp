#pragma once
#import "PMNativeOSProgram.h"

NS_ASSUME_NONNULL_BEGIN
// Retain one instance for the exclusive native scene visit. All calls are on main.
// current checks the coordinator's visit identity. Call invalidate before leaving the scene.
typedef NS_ENUM(NSInteger, PMNativeRevealChoice) {
    PMNativeRevealContinue, PMNativeRevealDetail, PMNativeRevealStart
};
@interface PMNativeOSActions : NSObject
- (instancetype)initWithProgram:(PMNativeOSProgram *)program current:(BOOL (^)(void))current;
- (instancetype)init NS_UNAVAILABLE;
@property(nonatomic, readonly) const PMOSPage *page;
@property(nonatomic, readonly, copy) NSArray<NSDictionary *> *nodes;
@property(nonatomic, readonly) BOOL cardOnly;
// Call on synthetic node presses instead of clickNode:. A card returns its exact hydrated
// row (including challengeDetail overrides). A pager changes page/nodes and calls rebuild.
- (void)activateCardNode:(NSInteger)index open:(void (^)(NSDictionary *row))open rebuild:(void (^)(void))rebuild;
// YES accepts the presentation. Keep map input/clock paused until completion. A rejected
// request has no callback. invalidate cancels an accepted request without a continuation.
- (BOOL)playIntro:(NSDictionary *)row completion:(void (^)(BOOL completed))completion;
- (BOOL)reveal:(const PMOSAction *)action fromNode:(NSInteger)index completion:(void (^)(PMNativeRevealChoice choice))completion;
// Reconnect applies the supplied record. A relaunch checkpoint is persisted before
// showing the panel and returns via leave. Its token survives leaving the scene.
- (BOOL)checkpoint:(const PMOSAction *)action resume:(void (^)(NSDictionary *record))resume leave:(void (^)(void))leave;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
