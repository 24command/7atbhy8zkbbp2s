#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#include "../PhiMod/Sources/PMNativeOSFrameSequence.hpp"
#include "../PhiMod/Sources/PMChapterArt.h"
#include "../PhiMod/Sources/PMNativeOSMapMediaTiming.hpp"
#include <cassert>
#include <unistd.h>
#include <sys/stat.h>
static void png(NSString *path, size_t width, size_t height) {
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(nullptr,width,height,8,0,color,kCGImageAlphaPremultipliedLast);
    assert(ctx); CGColorSpaceRelease(color);
    CGContextSetRGBFillColor(ctx,1,0,0,.5); CGContextFillRect(ctx,CGRectMake(0,0,width,height));
    CGImageRef image = CGBitmapContextCreateImage(ctx); assert(image);
    CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],CFSTR("public.png"),1,nullptr);
    assert(dest); CGImageDestinationAddImage(dest,image,nullptr); assert(CGImageDestinationFinalize(dest));
    CFRelease(dest); CGImageRelease(image); CGContextRelease(ctx);
}
int main() { @autoreleasepool {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:[@".pma-test-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSString *chapter = [root stringByAppendingPathComponent:@"chapter"];
    NSString *dir = [chapter stringByAppendingPathComponent:@"os-media"];
    assert([fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil]);
    NSString *path = [dir stringByAppendingPathComponent:@"test.pma"], *frame = [dir stringByAppendingPathComponent:@"one.png"];
    png(frame,4,2);
    NSDictionary *valid = @{@"version":@1,@"width":@4,@"height":@2,@"fps":@2,@"frames":@[@"one.png",@"one.png"]};
    auto write = [&](id value) { assert([[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] writeToFile:path atomically:YES]); };
    auto invalid = [&](NSString *key,id value) { NSMutableDictionary *d=[valid mutableCopy];d[key]=value;write(d);NSError *e=nil;assert(!PMOSFrameSequenceOpen(path,&e));assert(e); };
    write(valid); NSError *error=nil; NSObject *sequence=PMOSFrameSequenceOpen(path,&error);
    assert(sequence && !error && PMOSFrameSequenceCount(sequence)==2 && PMOSFrameSequenceDelay(sequence)==.5);
    CGImageRef image=PMOSFrameSequenceCopyFrame(sequence,0,2,&error);assert(image && CGImageGetWidth(image)==2 && CGImageGetHeight(image)==1);CGImageRelease(image);
    assert(!PMOSFrameSequenceCopyFrame(sequence,2,2,&error));
    assert(!PMOSFrameSequenceCopyFrame(sequence,0,0,&error));
    for (NSString *key in @[@"version",@"width",@"height",@"fps"]) { invalid(key,@YES);invalid(key,@"1");invalid(key,NSNull.null); }
    invalid(@"version",@2);invalid(@"width",@0);invalid(@"width",@2049);invalid(@"height",@1.5);
    invalid(@"fps",@0);invalid(@"fps",@61);invalid(@"fps",@0.001);invalid(@"frames",@[]);invalid(@"extra",@1);
    for (id name in @[@"../one.png",@"sub/one.png",@"sub\\one.png",@"/one.png",@"x:one.png",@".one.png",@"x\n.png",@"one.jpg",@"missing.png",@1]) invalid(@"frames",@[name]);
    invalid(@"frames",@[[[@"x" stringByPaddingToLength:252 withString:@"x" startingAtIndex:0] stringByAppendingString:@".png"]]);
    NSMutableArray *many=[NSMutableArray array];for(int i=0;i<4097;++i)[many addObject:@"one.png"];invalid(@"frames",many);
    NSMutableDictionary *max=[valid mutableCopy];[many removeLastObject];max[@"frames"]=many;max[@"fps"]=@60;write(max);assert(PMOSFrameSequenceOpen(path,&error));
    max[@"frames"]=@[@"one.png"];max[@"fps"]=@(1./600.);write(max);assert(PMOSFrameSequenceOpen(path,&error));
    assert([[NSMutableData dataWithLength:2*1024*1024+1] writeToFile:path atomically:YES]);assert(!PMOSFrameSequenceOpen(path,&error));
    assert([[@"{" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);assert(!PMOSFrameSequenceOpen(path,&error));
    write(@[]);assert(!PMOSFrameSequenceOpen(path,&error));write(valid);
    // Header/dimension/corrupt-image failures are checked lazily, not preloaded.
    png(frame,5,2);sequence=PMOSFrameSequenceOpen(path,&error);assert(sequence);assert(!PMOSFrameSequenceCopyFrame(sequence,0,2,&error));
    png(frame,2049,2);assert(!PMOSFrameSequenceCopyFrame(sequence,0,2,&error));
    assert([[@"not a PNG" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:frame atomically:YES]);assert(!PMOSFrameSequenceCopyFrame(sequence,0,2,&error));
    // Replacing a validated frame with a symlink is also rejected at decode time.
    png(frame,4,2);sequence=PMOSFrameSequenceOpen(path,&error);assert(sequence);
    NSString *outside=[root stringByAppendingPathComponent:@"outside.png"];png(outside,4,2);
    assert([fm removeItemAtPath:frame error:nil]);assert(symlink(outside.fileSystemRepresentation,frame.fileSystemRepresentation)==0);
    assert(!PMOSFrameSequenceCopyFrame(sequence,0,2,&error));assert(!PMOSFrameSequenceOpen(path,&error));
    assert([fm removeItemAtPath:frame error:nil]);assert(mkfifo(frame.fileSystemRepresentation,0600)==0);assert(!PMOSFrameSequenceOpen(path,&error));
    assert([fm removeItemAtPath:frame error:nil]);png(frame,4,2);
    assert([fm removeItemAtPath:path error:nil]);assert(symlink(outside.fileSystemRepresentation,path.fileSystemRepresentation)==0);assert(!PMOSFrameSequenceOpen(path,&error));
    assert([fm removeItemAtPath:path error:nil]);write(valid);
    NSString *saved=[chapter stringByAppendingPathComponent:@"saved"];assert([fm moveItemAtPath:dir toPath:saved error:nil]);assert(symlink(saved.fileSystemRepresentation,dir.fileSystemRepresentation)==0);assert(!PMOSFrameSequenceOpen(path,&error));
    // The already-open sequence owns its pinned directory even after a rename.
    image=PMOSFrameSequenceCopyFrame(sequence,0,2,&error);assert(image);CGImageRelease(image);
    assert([fm removeItemAtPath:dir error:nil]);assert([fm moveItemAtPath:saved toPath:dir error:nil]);
    assert(PMOSArtPath(chapter,@"test.pma"));assert(!PMOSEntryVideoPath(chapter,@"test.pma"));assert(!PMOSArtPath(chapter,@"../test.pma"));
    using pmnativeosmap::playback::nextFrame;
    assert(nextFrame(0,2,false)==1 && nextFrame(1,2,false)==2 && nextFrame(1,2,true)==0 && nextFrame(0,1,true)==1);
    // Reopen/revisit starts from requested frame zero, independent of prior decoder state.
    sequence=PMOSFrameSequenceOpen(path,&error);image=PMOSFrameSequenceCopyFrame(sequence,0,2,&error);assert(image);CGImageRelease(image);
    sequence=nil;assert([fm removeItemAtPath:root error:nil]);
    puts("PMA schema, budgets, symlinks, lazy PNG dimensions and playback boundaries passed");
} }
