#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#include "PMNativeOSFrameSequence.hpp"
#include <cmath>
#include <algorithm>
#include <cerrno>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {
constexpr size_t ManifestLimit = 2u * 1024u * 1024u;
constexpr size_t FrameLimit = 32u * 1024u * 1024u;
struct FD {
    int value;
    explicit FD(int fd = -1): value(fd) {}
    ~FD() { if (value >= 0) close(value); }
    FD(const FD &) = delete;
    FD &operator=(const FD &) = delete;
};
bool reject(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"PhiMod.FrameSequence" code:1
                                      userInfo:@{NSLocalizedDescriptionKey:message}];
    return false;
}
bool basename(NSString *name, NSString *extension) {
    return [name isKindOfClass:NSString.class] && name.length && ![name hasPrefix:@"."] &&
        [name lengthOfBytesUsingEncoding:NSUTF8StringEncoding] < 256 &&
        [name isEqualToString:name.lastPathComponent] &&
        [name rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/:\\"]].location == NSNotFound &&
        [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound &&
        [name.pathExtension.lowercaseString isEqualToString:extension];
}
bool number(id value, double minimum, double maximum, bool integral) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return false;
    double n = [value doubleValue];
    return std::isfinite(n) && n >= minimum && n <= maximum && (!integral || n == std::floor(n));
}
// Only Apple's /var alias is normalized; never resolve author-controlled symlinks.
NSString *containerSpelling(NSString *path) {
    return [path hasPrefix:@"/var/"] ? [@"/private" stringByAppendingString:path] : path;
}
int directoryOpenError(NSError **error, NSString *operation, NSString *path, int code) {
    if (error) {
        NSError *underlying = [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];
        *error = [NSError errorWithDomain:@"PhiMod.FrameSequence" code:1 userInfo:@{
            NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Sequence directory %@ failed (%@): %@ (errno %d)",
                operation,path,underlying.localizedDescription,code],
            NSUnderlyingErrorKey:underlying}];
    }
    return -1;
}
// Pin the trusted app container directly: its ancestors need search permission,
// but opening each ancestor for reading can be denied by the iOS sandbox.
// Every component below the container remains subject to O_NOFOLLOW.
int openMediaDirectory(NSString *directory, NSError **error) {
    NSString *home = containerSpelling(NSHomeDirectory());
    directory = containerSpelling(directory);
    if (![home hasPrefix:@"/"] || [home isEqualToString:@"/"] ||
        ![directory hasPrefix:[home stringByAppendingString:@"/"]] ||
        ![directory.lastPathComponent isEqualToString:@"os-media"] ||
        [directory rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
        reject(error,@"Sequence must be in an unlinked os-media directory inside the app container");
        return -1;
    }
    NSArray<NSString *> *parts = [[directory substringFromIndex:home.length + 1] pathComponents];
    for (NSString *part in parts) {
        if (!part.length || [part isEqualToString:@"."] || [part isEqualToString:@".."] || [part isEqualToString:@"/"]) {
            reject(error,@"Invalid sequence directory component"); return -1;
        }
    }
    int fd = open(home.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) return directoryOpenError(error,@"open container",home,errno);
    for (NSString *part in parts) {
        int next = openat(fd, part.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        int code = errno; // close() must not replace the failing openat() errno.
        close(fd);
        if (next < 0) return directoryOpenError(error,@"openat component",part,code);
        fd = next;
    }
    return fd;
}
int openFile(int directory, NSString *name, size_t limit) {
    int fd = openat(directory, name.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    struct stat st{};
    if (fd < 0) return -1;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_size <= 0 || uint64_t(st.st_size) > limit) {
        close(fd); return -1;
    }
    return fd;
}
NSData *readFile(int directory, NSString *name, size_t limit, NSError **error) {
    FD fd(openFile(directory, name, limit));
    if (fd.value < 0) { reject(error,@"Missing, linked, nonregular or oversized sequence file"); return nil; }
    NSMutableData *data = [NSMutableData data];
    unsigned char buffer[16384];
    for (;;) {
        ssize_t n = read(fd.value, buffer, sizeof(buffer));
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) { reject(error,@"Sequence file read failed"); return nil; }
        if (!n) break;
        if (data.length + size_t(n) > limit) { reject(error,@"Sequence file grew beyond its byte budget"); return nil; }
        [data appendBytes:buffer length:size_t(n)];
    }
    return data;
}
}

@interface PMNativeOSFrameSequence : NSObject {
@public
    int directoryFD;
    NSArray<NSString *> *frames;
    NSUInteger width, height;
    double fps;
    NSString *cachedName;
    NSData *cachedRGBA;
    NSUInteger cachedLimit, cachedWidth, cachedHeight;
    uint64_t revision;

}
@end
@implementation PMNativeOSFrameSequence
- (instancetype)init { if ((self = [super init])) directoryFD = -1; return self; }
- (void)dealloc { if (directoryFD >= 0) close(directoryFD); }
@end

NSObject *PMOSFrameSequenceOpen(NSString *path, NSError **error) {
    if (error) *error = nil;
    if (!basename(path.lastPathComponent,@"pma")) { reject(error,@"Invalid sequence manifest filename"); return nil; }
    PMNativeOSFrameSequence *sequence = [PMNativeOSFrameSequence new];
    sequence->directoryFD = openMediaDirectory(path.stringByDeletingLastPathComponent,error);
    if (sequence->directoryFD < 0) return nil;
    NSData *data = readFile(sequence->directoryFD,path.lastPathComponent,ManifestLimit,error);
    if (!data) return nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![root isKindOfClass:NSDictionary.class]) { reject(error,@"Sequence manifest must be a JSON object"); return nil; }
    NSSet *keys = [NSSet setWithArray:@[@"version",@"width",@"height",@"fps",@"frames"]];
    if (![[NSSet setWithArray:[root allKeys]] isEqualToSet:keys] ||
        !number(root[@"version"],1,1,true) || !number(root[@"width"],1,2048,true) ||
        !number(root[@"height"],1,2048,true) || !number(root[@"fps"],0,60,false) || [root[@"fps"] doubleValue] <= 0 ||
        ![root[@"frames"] isKindOfClass:NSArray.class]) {
        reject(error,@"Invalid sequence version, dimensions, fps or fields"); return nil;
    }
    NSArray *names = root[@"frames"];
    double fps = [root[@"fps"] doubleValue];
    if (!names.count || names.count > 4096 || double(names.count) / fps > 600.) {
        reject(error,@"Sequence exceeds 4096 frames or 600 seconds, or is empty"); return nil;
    }
    for (id name in names) {
        if (!basename(name,@"png")) { reject(error,@"Sequence frame must be a local PNG basename"); return nil; }
        FD frame(openFile(sequence->directoryFD,name,FrameLimit));
        if (frame.value < 0) { reject(error,@"Missing, linked, nonregular or oversized sequence frame"); return nil; }
    }
    sequence->frames = [names copy]; sequence->width = [root[@"width"] unsignedIntegerValue];
    sequence->height = [root[@"height"] unsignedIntegerValue]; sequence->fps = fps;
    return sequence;
}
NSUInteger PMOSFrameSequenceCount(NSObject *sequence) { return ((PMNativeOSFrameSequence *)sequence)->frames.count; }
double PMOSFrameSequenceDelay(NSObject *sequence) { return 1. / ((PMNativeOSFrameSequence *)sequence)->fps; }
CGImageRef PMOSFrameSequenceCopyFrame(NSObject *object, NSUInteger index, NSUInteger pixels, NSError **error) {
    if (error) *error = nil;
    PMNativeOSFrameSequence *sequence = (PMNativeOSFrameSequence *)object;
    if (!sequence || index >= sequence->frames.count || !pixels || pixels > 2048) {
        reject(error,@"Invalid sequence frame index or decode size"); return nullptr;
    }
    NSData *data = readFile(sequence->directoryFD,sequence->frames[index],FrameLimit,error);
    if (!data) return nullptr;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data,
        (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache:@NO});
    if (!source) { reject(error,@"Invalid sequence PNG"); return nullptr; }
    CGImageRef image = nullptr;
    @try {
        if (![(__bridge NSString *)CGImageSourceGetType(source) isEqualToString:@"public.png"] || CGImageSourceGetCount(source) != 1) {
            reject(error,@"Sequence frame must contain one PNG image"); return nullptr;
        }
        NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,nullptr));
        if (!number(props[(__bridge NSString *)kCGImagePropertyPixelWidth],sequence->width,sequence->width,true) ||
            !number(props[(__bridge NSString *)kCGImagePropertyPixelHeight],sequence->height,sequence->height,true)) {
            reject(error,@"Sequence PNG dimensions disagree with manifest"); return nullptr;
        }
        image = CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{
            (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
            (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@(pixels),
            (__bridge NSString *)kCGImageSourceShouldCacheImmediately:@YES});
        if (!image) reject(error,@"Sequence PNG decode failed");
    } @finally { CFRelease(source); }
    return image;
}

NSData *PMOSFrameSequenceRGBAFrame(NSObject *object, NSUInteger index, NSUInteger pixels,
    NSUInteger *width, NSUInteger *height, uint64_t *revision, NSError **error) {
    if (error) *error = nil;
    PMNativeOSFrameSequence *sequence = (PMNativeOSFrameSequence *)object;
    if (!sequence || index >= sequence->frames.count || !pixels || pixels > 2048) {
        reject(error,@"Invalid sequence frame index or decode size"); return nil;
    }
    NSString *name = sequence->frames[index];
    if (!sequence->cachedRGBA || sequence->cachedLimit != pixels || ![sequence->cachedName isEqualToString:name]) {
        // Drop the previous decoded buffer before allocating its replacement.
        sequence->cachedRGBA = nil; sequence->cachedName = nil;
        CGImageRef image = PMOSFrameSequenceCopyFrame(object,index,pixels,error);
        if (!image) return nil;
        size_t w = CGImageGetWidth(image), h = CGImageGetHeight(image);
        NSMutableData *rgba = [NSMutableData dataWithLength:w*h*4];
        CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef context = space ? CGBitmapContextCreate(rgba.mutableBytes,w,h,8,w*4,space,
            kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast) : nullptr;
        if (space) CGColorSpaceRelease(space);
        if (!context) { CGImageRelease(image); reject(error,@"PMA RGBA allocation failed"); return nil; }
        // Quartz bitmap row zero is the image top; Unity raw textures start at
        // the bottom. Flip the draw once, preserving the authored orientation.
        CGContextTranslateCTM(context,0,h);
        CGContextScaleCTM(context,1,-1);
        CGContextSetBlendMode(context,kCGBlendModeCopy);
        CGContextDrawImage(context,CGRectMake(0,0,w,h),image);
        CGContextRelease(context); CGImageRelease(image);
        // UI/Default and the authored additive shader both expect straight RGB.
        auto *bytes = static_cast<unsigned char *>(rgba.mutableBytes);
        for (size_t i=0; i<w*h*4; i+=4) {
            unsigned a=bytes[i+3];
            if (a==255) continue;
            for (size_t c=0;c<3;++c)
                bytes[i+c]=a ? static_cast<unsigned char>(std::min(255u,(unsigned(bytes[i+c])*255+a/2)/a)) : 0;
        }
        sequence->cachedRGBA=rgba; sequence->cachedName=name; sequence->cachedLimit=pixels;
        sequence->cachedWidth=w; sequence->cachedHeight=h; ++sequence->revision;
    }
    if (width) *width=sequence->cachedWidth;
    if (height) *height=sequence->cachedHeight;
    if (revision) *revision=sequence->revision;
    return sequence->cachedRGBA;
}
