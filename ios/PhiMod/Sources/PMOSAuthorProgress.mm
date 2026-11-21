#import "PMOSAuthorProgress.h"
#import <CoreFoundation/CoreFoundation.h>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <fcntl.h>
#include <mutex>
#include <atomic>
#include <sys/stat.h>
#include <unistd.h>

NSNotificationName const PMOSAuthorProgressChanged = @"PMOSAuthorProgressChanged";

static std::atomic<uint64_t> authorRevision{0};
uint64_t PMOSAuthorProgressRevision(void) { return authorRevision.load(); }

static NSMutableDictionary<NSString *, NSNumber *> *chapterRevisions() {
    static NSMutableDictionary *versions;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ versions = [NSMutableDictionary new]; });
    return versions;
}
uint64_t PMOSChapterProgressRevision(NSString *chapter) {
    NSDictionary *versions = chapterRevisions();
    @synchronized (versions) { return [versions[chapter.precomposedStringWithCanonicalMapping] unsignedLongLongValue]; }
}

namespace {
constexpr NSUInteger maxKeys = 512;
// Even 512 distinct 64-byte keys with int32 values fit in a 64 KiB binary plist.
constexpr size_t maxFileBytes = 128 * 1024;

struct File {
    const int fd;
    explicit File(int descriptor) : fd(descriptor) {}
    ~File() { if (fd >= 0) close(fd); }
    File(const File &) = delete;
    File &operator=(const File &) = delete;
};

// Hex-encode canonical UTF-8 so different chapter IDs stay distinct on a
// case-insensitive filesystem and Lua input never becomes a path component.
NSString *chapterStem(NSString *chapter) {
    if (![chapter isKindOfClass:NSString.class] || !chapter.length || chapter.length > 255 ||
        [chapter isEqual:@"."] || [chapter isEqual:@".."] || [chapter containsString:@"/"] ||
        [chapter containsString:@"\\"] ||
        [chapter rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return nil;
    NSData *bytes = [chapter.precomposedStringWithCanonicalMapping dataUsingEncoding:NSUTF8StringEncoding];
    if (!bytes.length || bytes.length > 96) return nil; // content-store ID limit
    static const char hex[] = "0123456789abcdef";
    char name[96 * 2];
    const auto *input = static_cast<const uint8_t *>(bytes.bytes);
    for (NSUInteger i = 0; i < bytes.length; ++i) {
        name[2*i] = hex[input[i] >> 4];
        name[2*i+1] = hex[input[i] & 15];
    }
    return [[NSString alloc] initWithBytes:name length:2*bytes.length encoding:NSASCIIStringEncoding];
}

bool validKey(NSString *key) {
    if (![key isKindOfClass:NSString.class] || !key.length || key.length > 64) return false;
    for (NSUInteger i = 0; i < key.length; ++i) {
        unichar c = [key characterAtIndex:i];
        if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
              c == '_' || c == '.' || c == '-')) return false;
    }
    return true;
}

bool validValues(NSDictionary *values) {
    if (![values isKindOfClass:NSDictionary.class] || values.count > maxKeys) return false;
    for (NSString *key in values) {
        NSNumber *value = values[key];
        if (!validKey(key) || ![value isKindOfClass:NSNumber.class]) return false;
        CFNumberRef number = (__bridge CFNumberRef)value;
        if (CFGetTypeID(number) != CFNumberGetTypeID() || CFNumberIsFloatType(number) ||
            [value compare:@(INT32_MIN)] == NSOrderedAscending ||
            [value compare:@(INT32_MAX)] == NSOrderedDescending) return false;
    }
    return true;
}

// ENOENT alone means an empty chapter. Read a bounded regular file through
// one descriptor so an atomic replacement cannot mix two snapshots.
NSDictionary *readValues(int directory, NSString *name) {
    File file(openat(directory, name.UTF8String, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK));
    if (file.fd < 0) return errno == ENOENT ? @{} : nil;
    struct stat info;
    if (fstat(file.fd, &info) || !S_ISREG(info.st_mode) || info.st_size <= 0 || info.st_size > (off_t)maxFileBytes) return nil;
    NSMutableData *bytes = [NSMutableData dataWithLength:(NSUInteger)info.st_size];
    auto *buffer = static_cast<uint8_t *>(bytes.mutableBytes);
    size_t offset = 0;
    while (offset < bytes.length) {
        ssize_t count = read(file.fd, buffer + offset, bytes.length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return nil;
        offset += count;
    }
    NSDictionary *values = [NSPropertyListSerialization propertyListWithData:bytes options:NSPropertyListImmutable
                                                                      format:nullptr error:nullptr];
    return validValues(values) ? values : nil;
}

bool replaceValues(int directory, NSString *name, NSDictionary *values) {
    NSData *bytes = [NSPropertyListSerialization dataWithPropertyList:values format:NSPropertyListBinaryFormat_v1_0
                                                              options:0 error:nullptr];
    if (!bytes || bytes.length > maxFileBytes) return false;
    NSString *temporary = [NSUUID.UUID.UUIDString stringByAppendingString:@".tmp"];
    File file(openat(directory, temporary.UTF8String, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0600));
    if (file.fd < 0) return false;
    const auto *buffer = static_cast<const uint8_t *>(bytes.bytes);
    size_t offset = 0;
    while (offset < bytes.length) {
        ssize_t count = write(file.fd, buffer + offset, bytes.length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        offset += count;
    }
    if (offset == bytes.length && fsync(file.fd) == 0 &&
        renameat(directory, temporary.UTF8String, directory, name.UTF8String) == 0) return true;
    unlinkat(directory, temporary.UTF8String, 0);
    return false;
}
} // namespace

@implementation PMOSAuthorProgress {
    NSString *_chapter;
    NSString *_directory;
    NSString *_name;
    NSString *_lockName;
}

- (instancetype)initWithRoot:(NSString *)root chapter:(NSString *)chapter {
    if (!(self = [super init])) return nil;
    NSString *stem = chapterStem(chapter);
    if (![root isKindOfClass:NSString.class] || !root.isAbsolutePath || !stem) return nil;
    _chapter = [chapter copy];
    _directory = [root stringByAppendingPathComponent:@"author-progress"];
    _name = [stem stringByAppendingPathExtension:@"plist"];
    _lockName = [stem stringByAppendingPathExtension:@"lock"];
    return self;
}

- (NSDictionary<NSString *, NSNumber *> *)snapshotValues {
    if (NSThread.isMainThread) return nil;
    File directory(open(_directory.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC));
    if (directory.fd < 0) return errno == ENOENT ? @{} : nil;
    return readValues(directory.fd, _name);
}

- (BOOL)readKey:(NSString *)key value:(int *)value {
    if (!value || !validKey(key)) return NO;
    NSDictionary *values = [self snapshotValues];
    if (!values) return NO;
    *value = [values[key] intValue];
    return YES;
}

- (BOOL)commitValues:(NSDictionary<NSString *, NSNumber *> *)values {
    if (NSThread.isMainThread || !validValues(values)) return NO;
    return [self updateValues:^NSDictionary *(NSDictionary *unused){ return values; }];
}

- (BOOL)updateValues:(NSDictionary *(^)(NSDictionary *))update {
    if (NSThread.isMainThread || !update) return NO;
    // Separate instances share this mutex. Acquire it before directory setup
    // and hold it through replacement, with the per-chapter file lock inside.
    static std::mutex commitMutex;
    const std::lock_guard<std::mutex> guard(commitMutex);
    constexpr int directoryFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC;
    int directoryFD = open(_directory.fileSystemRepresentation, directoryFlags);
    if (directoryFD < 0 && errno == ENOENT) {
        [NSFileManager.defaultManager createDirectoryAtPath:_directory withIntermediateDirectories:YES
                                                attributes:nil error:nullptr];
        // Another process may have created it. The verified open decides success.
        directoryFD = open(_directory.fileSystemRepresentation, directoryFlags);
    }
    File directory(directoryFD);
    if (directory.fd < 0) return NO;
    // Lock a stable sibling inode across the entire read/merge/rename.
    int fd;
    do {
        fd = openat(directory.fd, _lockName.UTF8String, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC | O_EXLOCK, 0600);
    } while (fd < 0 && errno == EINTR);
    File lock(fd);
    if (lock.fd < 0) return NO;
    NSDictionary *previous = readValues(directory.fd, _name);
    if (!previous) return NO;
    NSDictionary *values = update(previous);
    if (!values || !validValues(values)) return NO;
    if (!values.count) return YES;
    NSMutableDictionary *merged = [previous mutableCopy];
    [merged addEntriesFromDictionary:values];
    if ([previous isEqualToDictionary:merged]) return YES;
    if (merged.count > maxKeys || !replaceValues(directory.fd, _name, merged)) return NO;
    NSMutableDictionary *versions = chapterRevisions();
    @synchronized (versions) { versions[_chapter.precomposedStringWithCanonicalMapping] = @(++authorRevision); }
    NSString *chapter = _chapter;
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:PMOSAuthorProgressChanged object:chapter];
    });
    return YES;
}
@end
