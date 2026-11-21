#pragma once
#import <Foundation/Foundation.h>
#import "PMFileDigest.h"
#include "../Core/PMStockIntroResolver.h"

// The intro player expects a regular .mp4. Publish a verified copy under tmp,
// outside the chapter tree so chapter export never packages stock media.
static inline NSString *PMStockIntroCopy(const PMStockIntro *clip, NSString *dataDir, NSString *cache) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *source = [dataDir stringByAppendingPathComponent:@(clip->resource)];
    NSString *movie = [cache stringByAppendingPathComponent:[@(clip->sha256) stringByAppendingPathExtension:@"mp4"]];
    NSDictionary *src = [fm attributesOfItemAtPath:source error:nil];
    if (![[fm attributesOfItemAtPath:dataDir error:nil][NSFileType] isEqual:NSFileTypeDirectory] ||
        ![src[NSFileType] isEqual:NSFileTypeRegular] || [src[NSFileSize] unsignedLongLongValue] != clip->size) return nil;

    static NSMutableDictionary *verified;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ verified = [NSMutableDictionary new]; });
    @synchronized (verified) {
        if (![fm createDirectoryAtPath:cache withIntermediateDirectories:YES attributes:nil error:nil] ||
            ![[fm attributesOfItemAtPath:cache error:nil][NSFileType] isEqual:NSFileTypeDirectory]) return nil;
        NSDictionary *dst = [fm attributesOfItemAtPath:movie error:nil];
        if (dst && ![dst[NSFileType] isEqual:NSFileTypeRegular]) return nil;
        if (dst && [verified[movie] isEqual:@[src, dst]]) return movie;

        NSString *staging = [cache stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        if (![fm copyItemAtPath:source toPath:staging error:nil] ||
            ![PMFileSHA256(staging) isEqual:@(clip->sha256)] ||
            rename(staging.fileSystemRepresentation, movie.fileSystemRepresentation) != 0) {
            [fm removeItemAtPath:staging error:nil];
            return nil;
        }
        dst = [fm attributesOfItemAtPath:movie error:nil];
        if (!dst) return nil;
        verified[movie] = @[src, dst];
        return movie;
    }
}

static inline NSString *PMResolveStockIntro(NSString *name) {
    const PMStockIntro *clip = PMStockIntroForName(name.UTF8String);
    NSBundle *bundle = NSBundle.mainBundle;
    if (!clip || ![name isEqualToString:@(clip->reference)] ||
        ![[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"4.0.4"] ||
        ![[bundle objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:@"3"]) return nil;
    return PMStockIntroCopy(clip, [bundle.bundlePath stringByAppendingPathComponent:@"Data"],
                           [NSTemporaryDirectory() stringByAppendingPathComponent:@"PMStockIntro-404"]);
}
