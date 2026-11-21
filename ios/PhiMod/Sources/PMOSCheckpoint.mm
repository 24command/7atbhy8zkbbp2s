#import "PMOSCheckpoint.h"
#import <CoreFoundation/CoreFoundation.h>

#include <cerrno>
#include <climits>
#include <fcntl.h>
#include <unistd.h>

#ifdef PMOS_CHECKPOINT_HOST_TEST
extern NSString *PMOSCheckpointTestRoot(void);
#endif

namespace {
NSString *checkpointRoot() {
#ifdef PMOS_CHECKPOINT_HOST_TEST
    return PMOSCheckpointTestRoot();
#else
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [documents stringByAppendingPathComponent:@"PhiMod"];
#endif
}

NSString *processID() {
    static NSString *const uuid = NSUUID.UUID.UUIDString;
    return uuid;
}

NSString *checkpointPath(NSString *root) {
    return [root stringByAppendingPathComponent:@"chapter-checkpoint.plist"];
}

bool hasText(id value) {
    return [value isKindOfClass:NSString.class] &&
           [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
}

bool validPage(id page) {
    if (hasText(page)) return true;
    if (![page isKindOfClass:NSNumber.class]) return false;
    CFTypeRef number = (__bridge CFTypeRef)page;
    if (CFGetTypeID(number) != CFNumberGetTypeID() || CFNumberIsFloatType((CFNumberRef)number)) return false;
    NSNumber *index = page;
    return [index compare:@0] != NSOrderedAscending && [index compare:@(INT_MAX)] != NSOrderedDescending;
}

bool validRecord(NSDictionary *record) {
    if (![record isKindOfClass:NSDictionary.class] || !hasText(record[@"token"]) ||
        !hasText(record[@"chapter"]) || !hasText(record[@"scriptHash"])) return false;
    if (record[@"page"]) return record.count == 4 && validPage(record[@"page"]);
    if (!hasText(record[@"songID"])) return false;
    return record[@"difficulty"] ? record.count == 5 && hasText(record[@"difficulty"]) : record.count == 4;
}

NSDictionary *readEnvelope(NSString *root) {
    NSData *data = [NSData dataWithContentsOfFile:checkpointPath(root)];
    if (!data) return nil;
    NSDictionary *envelope = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable
                                                                         format:nullptr error:nullptr];
    if (![envelope isKindOfClass:NSDictionary.class] || !validRecord(envelope[@"record"])) return nil;
    NSString *writer = envelope[@"writer"];
    if (![writer isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:writer]) return nil;
    return envelope;
}

// Lock a stable sibling inode. Replacing the plist atomically must not release
// the lock between comparing a token and unlinking the matching record.
BOOL withWriteLock(NSString *root, NSError **error, BOOL (^operation)(NSError **)) {
    NSString *path = [root stringByAppendingPathComponent:@"chapter-checkpoint.lock"];
    int fd;
    do {
        fd = open(path.fileSystemRepresentation, O_CREAT | O_RDWR | O_EXLOCK | O_CLOEXEC, 0600);
    } while (fd == -1 && errno == EINTR);
    if (fd == -1) {
        int code = errno;
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];
        return NO;
    }
    @try {
        return operation(error);
    } @finally {
        close(fd);
    }
}
} // namespace

BOOL PMOSSaveCheckpoint(NSDictionary *record, NSError **error) {
    if (!validRecord(record)) {
        if (error) *error = [NSError errorWithDomain:@"PhiMod.ChapterCheckpoint" code:1 userInfo:@{
            NSLocalizedDescriptionKey: @"Invalid chapter checkpoint fields or destination."}];
        return NO;
    }
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{@"writer": processID(), @"record": record}
                                                              format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!data) return NO;
    NSString *root = checkpointRoot();
    if (![NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    return withWriteLock(root, error, ^BOOL(NSError **writeError) {
        return [data writeToFile:checkpointPath(root) options:NSDataWritingAtomic error:writeError];
    });
}

NSDictionary *PMOSPendingCheckpoint(void) {
    NSDictionary *envelope = readEnvelope(checkpointRoot());
    return [processID() isEqual:envelope[@"writer"]] ? nil : envelope[@"record"];
}

NSDictionary *PMOSLastCheckpoint(void) {
    return readEnvelope(checkpointRoot())[@"record"];
}

BOOL PMOSClearCheckpoint(NSString *token) {
    if (!hasText(token)) return NO;
    NSString *root = checkpointRoot();
    return withWriteLock(root, nullptr, ^BOOL(NSError **) {
        if (![readEnvelope(root)[@"record"][@"token"] isEqual:token]) return NO;
        return [NSFileManager.defaultManager removeItemAtPath:checkpointPath(root) error:nullptr];
    });
}
