#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Posted on the main queue after a successful, value-changing commit. Object = chapter ID.
FOUNDATION_EXPORT NSNotificationName const PMOSAuthorProgressChanged;
FOUNDATION_EXPORT uint64_t PMOSAuthorProgressRevision(void);
// In-memory stamp for a single canonical chapter. No file I/O.
FOUNDATION_EXPORT uint64_t PMOSChapterProgressRevision(NSString *chapter);
@interface PMOSAuthorProgress : NSObject
// root is the absolute PhiMod store root. Initialization performs no disk I/O.
- (nullable instancetype)initWithRoot:(NSString *)root chapter:(NSString *)chapter NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Synchronous worker-thread API. Keys are case-sensitive [A-Za-z0-9_.-]{1,64}.
// A missing key succeeds with zero. On failure the output is left untouched.
// One immutable worker-thread snapshot, including an empty dictionary for a new chapter.
- (nullable NSDictionary<NSString *, NSNumber *> *)snapshotValues;
- (BOOL)readKey:(NSString *)key value:(int *)value;

// Merge all entries or none. Each chapter holds up to 512 signed int32 flags.
// Invalid input, unreadable/corrupt storage, and main-thread calls return NO.
// Derive one batch under the same per-chapter lock as commitValues. A nil
// batch aborts; the block must not re-enter the store.
- (BOOL)updateValues:(NSDictionary<NSString *, NSNumber *> * _Nullable (^)(NSDictionary<NSString *, NSNumber *> *current))update;
- (BOOL)commitValues:(NSDictionary<NSString *, NSNumber *> *)values;
@end

NS_ASSUME_NONNULL_END
