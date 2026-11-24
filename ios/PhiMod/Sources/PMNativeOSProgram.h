#pragma once
#import <Foundation/Foundation.h>
#import "../Core/PMChapterVM.h"

NS_ASSUME_NONNULL_BEGIN
@class PMNativeOSProgram;
typedef void (^PMNativeOSLoadCompletion)(PMNativeOSProgram * _Nullable program, NSError * _Nullable error);
// action is borrowed for the duration of the completion. On failure its error field is set.
typedef void (^PMNativeOSClickCompletion)(BOOL success, const PMOSAction *action);

@interface PMNativeOSProgram : NSObject
// Borrowed immutable declaration; retain the program while using *page. Node indices match nodes.
@property(nonatomic, readonly) const PMOSPage *page;
@property(nonatomic, readonly, copy) NSString *chapter;
@property(nonatomic, readonly, copy) NSString *chapterName;
@property(nonatomic, readonly, copy) NSString *scriptHash;
@property(nonatomic, readonly, copy) NSArray<NSString *> *screens;
@property(nonatomic, readonly, copy) NSArray<NSString *> *order;
@property(nonatomic, readonly, copy) NSDictionary<NSString *, NSDictionary *> *bySong;
// bySong retains presentation metadata for unlock scenes. Interactive routes use visibleBySong.
@property(nonatomic, readonly, copy) NSDictionary<NSString *, NSDictionary *> *visibleBySong;
@property(nonatomic, readonly, copy) NSArray<NSDictionary *> *cards;
@property(nonatomic, readonly, copy) NSArray<NSDictionary *> *nodes;
// Resolved video path, otherwise nil. Timeline paths remain in nodes at their
// original declaration indices; select page->entryTransition.screen.
@property(nonatomic, readonly, copy, nullable) NSString *transitionPath;
// Resource failure is nonfatal: host must use native covered entry, ignoring
// authored load/timing. The immutable declaration and reserved screen remain
// intact, so failed transition nodes never become ordinary map content.
@property(nonatomic, readonly, copy, nullable) NSString *transitionError;
@property(nonatomic, readonly, copy) NSArray<NSDictionary *> *challengeRows;
// Declaration values. Successful clicks return the current switch and tier in PMOSAction.
@property(nonatomic, readonly) BOOL listSwitchHidden;
@property(nonatomic, readonly) BOOL listFirst;
@property(nonatomic, readonly) NSInteger nativeChapter; // Native chapter 8 or 9 (default).
@property(nonatomic, readonly) double aspect;
@property(nonatomic, readonly) NSInteger selectedLifeTier;

// Each load owns an independent VM and chapter progress context. Both methods complete
// asynchronously on the main queue. Click indices are zero-based and execute in FIFO order.
+ (void)loadChapter:(NSString *)chapter completion:(PMNativeOSLoadCompletion)completion;
- (NSDictionary<NSString *,NSString *> *)unlockFieldsForSong:(NSInteger)song;
- (void)markUnlockSeen:(NSInteger)index completion:(void (^)(BOOL))completion;
- (void)markEntryMovieSeen:(void (^)(BOOL))completion;
- (void)clickNode:(NSInteger)index completion:(PMNativeOSClickCompletion)completion;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
NS_ASSUME_NONNULL_END
