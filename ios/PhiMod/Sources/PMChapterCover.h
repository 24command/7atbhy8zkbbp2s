#pragma once
#import "PMChapterArt.h"
#import "PMChapterScript.h"
#import "PMOSAuthorProgress.h"
#import "PMDoorRun.h"
#include "../Core/PMChapterVM.h"

namespace pmchaptercover {
static int readFlag(void *context, const char *key, int *value) {
    NSDictionary *flags = (__bridge NSDictionary *)context;
    *value = [flags[[NSString stringWithUTF8String:key]] intValue];
    return 1;
}

// All disk access and VM work lives on the worker, including the door barrier.
static NSString *evaluate(NSString *root, NSString *dir, NSString *chapter, int songs) {
    NSData *src = PMChapterScriptData([NSURL fileURLWithPath:[dir stringByAppendingPathComponent:PMChapterScriptName]],nil);
    if (!src) return nil;
    NSDictionary *flags = [[[PMOSAuthorProgress alloc] initWithRoot:root chapter:chapter] snapshotValues];
    char name[256];
    if (!flags || !PMOSPreviewCover((const char *)src.bytes,src.length,songs,{(__bridge void *)flags,readFlag,nullptr},name) || !name[0]) return nil;
    NSString *file = [NSString stringWithUTF8String:name];
    NSString *path = PMOSArtPath(dir,file);
    return path && [[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFileType] isEqual:NSFileTypeRegular] ? file : nil;
}

static NSOperationQueue *previewQueue() {
    static NSOperationQueue *queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = [NSOperationQueue new]; queue.name = @"PhiMod.ChapterCover";
        queue.maxConcurrentOperationCount = 2; queue.qualityOfService = NSQualityOfServiceUserInitiated; });
    return queue;
}
typedef void (^CoverReady)(NSString *name);
// Main-thread API. A hit (including a cached miss) never schedules or notifies.
// A cold/stale key returns the configured-cover sentinel immediately. Coalesced
// callers replace the presentation callback; workers never retain a Unity card.
static NSString *preview(NSString *root, NSString *dir, NSString *chapter, int songs,
                         NSUInteger libraryRevision, CoverReady ready) {
    NSCAssert(NSThread.isMainThread, @"cover requests belong to the selector thread");
    if (!root || !dir || !chapter || !ready) return nil;
    static NSCache *cache;
    static NSMutableDictionary *pending;
    if (!cache) { cache = [NSCache new]; cache.countLimit = 128; pending = [NSMutableDictionary new]; }
    uint64_t revision = PMOSChapterProgressRevision(chapter);
    NSArray *owner = @[root,chapter];
    NSArray *stamp = @[root,dir,chapter,@(songs),@(libraryRevision),@(revision)];
    NSMutableDictionary *request = pending[owner];
    if ([request[@"stamp"] isEqual:stamp]) { request[@"ready"] = [ready copy]; return nil; }
    [(NSOperation *)request[@"work"] cancel];
    [pending removeObjectForKey:owner];
    NSString *cached = [cache objectForKey:stamp];
    if (cached) return cached.length ? cached : nil;
    NSBlockOperation *work = [NSBlockOperation new];
    __weak NSBlockOperation *token = work;
    pending[owner] = [@{@"stamp":stamp,@"work":work,@"ready":[ready copy]} mutableCopy];
    [work addExecutionBlock:^{ @autoreleasepool {
        PMDoorProgressBarrier();
        if (token.cancelled) return;
        NSString *name = evaluate(root,dir,chapter,songs);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSDictionary *current = pending[owner];
            if (!current || current[@"work"] != token) return;
            [pending removeObjectForKey:owner];
            // A commit during evaluation will issue its own, newer request.
            if (revision != PMOSChapterProgressRevision(chapter)) return;
            [cache setObject:name ?: @"" forKey:stamp];
            CoverReady deliver = current[@"ready"];
            deliver(name);
        });
    }}];
    [previewQueue() addOperation:work];
    return nil;
}

// Put the source directory and exact basename in the key. Delayed native
// requests for old keys must never decode a newly selected path into them.
static NSString *variant(NSString *file, bool media) {
    NSString *escaped = [file stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.alphanumericCharacterSet];
    return [NSString stringWithFormat:@"~%@:%@",media ? @"os" : @"base",escaped];
}
static NSString *pathForKey(NSString *key, NSString *folder) {
    NSRange marker = [key rangeOfString:@"~"];
    if (marker.location == NSNotFound || !folder) return nil;
    NSString *tag = [key substringFromIndex:NSMaxRange(marker)];
    if ([tag hasPrefix:@"os:"]) {
        NSString *name = [[tag substringFromIndex:3] stringByRemovingPercentEncoding];
        if (![@[@"png",@"jpg",@"jpeg",@"webp"] containsObject:name.pathExtension.lowercaseString ?: @""]) return nil;
        return PMOSArtPath(folder,name);
    }
    if (![tag hasPrefix:@"base:"]) return nil;
    NSString *name = [[tag substringFromIndex:5] stringByRemovingPercentEncoding];
    if (!name || ![@[@"image.png",@"image-before.png",@"image-after.png",@"image-special.png"] containsObject:name]) return nil;
    return [folder stringByAppendingPathComponent:name];
}
}
