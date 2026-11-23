#pragma once
#import <Foundation/Foundation.h>
#include <stdio.h>
#import "PMFileDigest.h"
#include "../Core/PMStockIntroResolver.h"

// Copy only the serialized VideoClip span. Shared resources can contain audio and several MP4s.
static inline bool PMCopyIntroSpan(NSString *source, NSString *staging, const PMStockIntro *clip) {
    if (clip->offset > clip->resourceSize || clip->size > clip->resourceSize-clip->offset) return false;
    FILE *input=fopen(source.fileSystemRepresentation,"rb");
    if (!input) return false;
    FILE *output=fopen(staging.fileSystemRepresentation,"wb");
    bool ok=output && fseeko(input,(off_t)clip->offset,SEEK_SET)==0;
    unsigned char buffer[32768];
    for(unsigned long long left=clip->size; ok && left; ) {
        size_t chunk = left < sizeof(buffer) ? (size_t)left : sizeof(buffer);
        ok=fread(buffer,1,chunk,input)==chunk && fwrite(buffer,1,chunk,output)==chunk;
        left-=chunk;
    }
    fclose(input);
    if(output && fclose(output)!=0)ok=false;
    return ok;
}

// The intro player expects a regular .mp4. Publish a verified copy under tmp,
// outside the chapter tree so chapter export never packages stock media.
static inline NSString *PMStockIntroCopy(const PMStockIntro *clip, NSString *dataDir, NSString *cache) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *source = [dataDir stringByAppendingPathComponent:@(clip->resource)];
    NSString *movie = [cache stringByAppendingPathComponent:[@(clip->sha256) stringByAppendingPathExtension:@"mp4"]];
    NSDictionary *src = [fm attributesOfItemAtPath:source error:nil];
    if (![[fm attributesOfItemAtPath:dataDir error:nil][NSFileType] isEqual:NSFileTypeDirectory] ||
        ![src[NSFileType] isEqual:NSFileTypeRegular] || [src[NSFileSize] unsignedLongLongValue] != clip->resourceSize) return nil;

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
        if (!PMCopyIntroSpan(source,staging,clip) ||
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
