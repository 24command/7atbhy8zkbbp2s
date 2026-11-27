// Compile-time syscall substitution is confined to this test translation unit.
// Production has no root override or filesystem hook.
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#include <cassert>
#include <cerrno>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
static NSString *testHome();
static int testOpen(const char *path, int flags, ...);
static int testOpenAt(int fd, const char *path, int flags, ...);
static int testClose(int fd);
#define NSHomeDirectory testHome
#define open testOpen
#define openat testOpenAt
#define close testClose
#include "../PhiMod/Sources/PMNativeOSFrameSequence.mm"
#undef NSHomeDirectory
#undef open
#undef openat
#undef close

static NSString *trustedHome;
static NSString *deniedComponent;
static int deniedRootError;
static unsigned rootOpens, ancestorOpens, relativeOpens;
static NSString *testHome() { return trustedHome; }
static int testOpen(const char *path, int flags, ...) {
    ++rootOpens;
    assert((flags & O_ACCMODE) == O_RDONLY && (flags & O_DIRECTORY));
    NSString *name = [NSString stringWithUTF8String:path];
    if (![name isEqualToString:containerSpelling(trustedHome)]) {
        ++ancestorOpens; errno = EACCES; return -1;
    }
    assert((flags & O_NOFOLLOW) && (flags & O_CLOEXEC));
    if (deniedRootError) { errno = deniedRootError; return -1; }
    return ::open(path,flags);
}
static int testOpenAt(int fd, const char *path, int flags, ...) {
    ++relativeOpens;
    NSString *name = [NSString stringWithUTF8String:path];
    assert(![name containsString:@"/"] && ![name isEqualToString:@".."]);
    assert((flags & O_NOFOLLOW) && (flags & O_CLOEXEC));
    if ([name isEqualToString:deniedComponent]) { errno = EPERM; return -1; }
    return ::openat(fd,path,flags);
}
static int testClose(int fd) {
    int result = ::close(fd);
    errno = EBADF; // Deliberately clobber errno to check failure preservation.
    return result;
}
static void posixError(NSError *error, int code, NSString *operation, NSString *part) {
    assert([error.domain isEqualToString:@"PhiMod.FrameSequence"]);
    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    assert([underlying.domain isEqualToString:NSPOSIXErrorDomain] && underlying.code == code);
    assert([error.localizedDescription containsString:operation]);
    assert([error.localizedDescription containsString:part]);
    assert(([error.localizedDescription containsString:[NSString stringWithFormat:@"errno %d",code]]));
    puts(error.localizedDescription.UTF8String);
}
int main() { @autoreleasepool {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *parent = [root stringByAppendingPathComponent:@"search-only"];
    trustedHome = [parent stringByAppendingPathComponent:@"container"];
    NSString *chapter = [trustedHome stringByAppendingPathComponent:@"Documents/chapter"];
    NSString *dir = [chapter stringByAppendingPathComponent:@"os-media"];
    assert([fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil]);
    NSString *path = [dir stringByAppendingPathComponent:@"test.pma"];
    NSDictionary *manifest = @{@"version":@1,@"width":@1,@"height":@1,@"fps":@1,@"frames":@[@"one.png"]};
    assert([[NSJSONSerialization dataWithJSONObject:manifest options:0 error:nil] writeToFile:path atomically:YES]);
    // Open validates file type/size; image decoding is covered by the companion test.
    assert([[@"lazy PNG bytes" dataUsingEncoding:NSUTF8StringEncoding]
        writeToFile:[dir stringByAppendingPathComponent:@"one.png"] atomically:YES]);
    assert(chmod(parent.fileSystemRepresentation,0111) == 0);
    if (geteuid() != 0) {
        int ancestor = ::open(parent.fileSystemRepresentation,O_RDONLY | O_DIRECTORY);
        assert(ancestor < 0 && errno == EACCES);
        puts("Real search-only ancestor: open(O_RDONLY|O_DIRECTORY) failed with EACCES");
    } else puts("Real ancestor permission probe skipped for root; mocked denial remains active");
    // The previous loader's first syscall fails under this sandbox model.
    assert(testOpen("/",O_RDONLY | O_DIRECTORY | O_CLOEXEC) == -1 && errno == EACCES);
    rootOpens = ancestorOpens = relativeOpens = 0;
    NSError *error = nil;
    NSObject *sequence = PMOSFrameSequenceOpen(path,&error);
    assert(sequence && !error && PMOSFrameSequenceCount(sequence) == 1);
    assert(rootOpens == 1 && ancestorOpens == 0 && relativeOpens == 5);
    sequence = nil;
    puts("Container-relative PMA open succeeded despite denied ancestors");
    // Match /var and /private/var only; no general symlink canonicalization.
    assert([containerSpelling(@"/var/mobile/container") isEqualToString:@"/private/var/mobile/container"]);
    assert([containerSpelling(@"/variant/container") isEqualToString:@"/variant/container"]);
    if ([trustedHome hasPrefix:@"/var/"] || [trustedHome hasPrefix:@"/private/var/"]) {
        NSString *canonical = containerSpelling(path);
        sequence = PMOSFrameSequenceOpen(canonical,&error);assert(sequence && !error);sequence = nil;
        NSString *originalHome = trustedHome;
        trustedHome = containerSpelling(trustedHome);
        sequence = PMOSFrameSequenceOpen([canonical substringFromIndex:8],&error);
        assert(sequence && !error);sequence = nil;
        trustedHome = originalHome;
    }
    unsigned before = rootOpens;
    for (NSString *bad in @[
        [trustedHome stringByAppendingString:@"-sibling/os-media/test.pma"],
        [parent stringByAppendingPathComponent:@"os-media/test.pma"],
        [trustedHome stringByAppendingString:@"/../os-media/test.pma"],
        [trustedHome stringByAppendingString:@"/Documents/../chapter/os-media/test.pma"],
        [trustedHome stringByAppendingString:@"/Documents/./chapter/os-media/test.pma"],
        [trustedHome stringByAppendingString:@"/Documents/\0hidden/os-media/test.pma"],
        @"relative/os-media/test.pma"]) {
        assert(!PMOSFrameSequenceOpen(bad,&error) && error);
    }
    assert(rootOpens == before); // Invalid paths rejected before any syscall.
    deniedRootError = EACCES;
    assert(!PMOSFrameSequenceOpen(path,&error));posixError(error,EACCES,@"open container",trustedHome.lastPathComponent);
    deniedRootError = 0;deniedComponent = @"chapter";
    assert(!PMOSFrameSequenceOpen(path,&error));posixError(error,EPERM,@"openat component",@"chapter");
    deniedComponent = nil;
    // Reject a linked intermediate directory even when its target is in-container.
    NSString *saved = [trustedHome stringByAppendingPathComponent:@"saved-chapter"];
    assert([fm moveItemAtPath:chapter toPath:saved error:nil]);
    assert(symlink(saved.fileSystemRepresentation,chapter.fileSystemRepresentation) == 0);
    assert(!PMOSFrameSequenceOpen(path,&error) && error.userInfo[NSUnderlyingErrorKey]);
    puts(error.localizedDescription.UTF8String); // Darwin may return ELOOP or ENOTDIR.
    assert([fm removeItemAtPath:chapter error:nil]);
    assert([fm moveItemAtPath:saved toPath:chapter error:nil]);
    sequence = PMOSFrameSequenceOpen(path,&error);assert(sequence && !error);sequence = nil;
    assert(ancestorOpens == 0);
    assert(chmod(parent.fileSystemRepresentation,0700) == 0);
    assert([fm removeItemAtPath:root error:nil]);
    puts("PMA container boundary, ancestor permissions, aliases, symlinks and POSIX diagnostics passed");
} }
