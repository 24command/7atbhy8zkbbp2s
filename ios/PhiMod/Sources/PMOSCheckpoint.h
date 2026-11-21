#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Required: nonblank string token, chapter and scriptHash. Supply exactly one
// destination: page (screen name or zero-based int index), or songID (string)
// with an optional nonblank difficulty label. Use a fresh token per checkpoint.
FOUNDATION_EXPORT BOOL PMOSSaveCheckpoint(NSDictionary *record, NSError * _Nullable * _Nullable error);

// Both reads return the stored record without consuming it. Pending hides a
// record written by this process. Missing or malformed storage returns nil.
FOUNDATION_EXPORT NSDictionary * _Nullable PMOSPendingCheckpoint(void);
FOUNDATION_EXPORT NSDictionary * _Nullable PMOSLastCheckpoint(void);

// YES only when the record with this token was removed.
FOUNDATION_EXPORT BOOL PMOSClearCheckpoint(NSString *token);

NS_ASSUME_NONNULL_END
