#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PMOSAuthorProgress : NSObject
// root is the absolute PhiMod store root. Initialization performs no disk I/O.
- (nullable instancetype)initWithRoot:(NSString *)root chapter:(NSString *)chapter NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Synchronous worker-thread API. Keys are case-sensitive [A-Za-z0-9_.-]{1,64}.
// A missing key succeeds with zero. On failure the output is left untouched.
- (BOOL)readKey:(NSString *)key value:(int *)value;

// Merge all entries or none. Each chapter holds up to 512 signed int32 flags.
// Invalid input, unreadable/corrupt storage, and main-thread calls return NO.
- (BOOL)commitValues:(NSDictionary<NSString *, NSNumber *> *)values;
@end

NS_ASSUME_NONNULL_END
