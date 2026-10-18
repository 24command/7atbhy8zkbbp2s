#import "PMDiagnostics.h"

static const NSUInteger PMDiagnosticsMaxBytes = 1024 * 1024;
static NSString * const PMDiagnosticsFileName = @"PhiMod-diagnostics.log";
static NSString *PMDiagnosticsSessionID;

static NSString *PMDiagnosticsResolvedPath(void) {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documents = paths.firstObject ?: NSTemporaryDirectory();
    return [documents stringByAppendingPathComponent:PMDiagnosticsFileName];
}

static NSString *PMDiagnosticsTailText(NSString *text, NSUInteger maxLines) {
    if (maxLines == 0) return @"";
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    NSUInteger start = lines.count > maxLines + 1 ? lines.count - maxLines - 1 : 0;
    return [[lines subarrayWithRange:NSMakeRange(start, lines.count - start)] componentsJoinedByString:@"\n"];
}

void PMDiagnosticsBeginSession(void) {
    @synchronized ([PMDiagnosticsFileName self]) {
        PMDiagnosticsSessionID = [NSUUID UUID].UUIDString;
    }
    NSString *marker = [NSString stringWithFormat:@"process session %@ pid=%d", PMDiagnosticsSessionID, NSProcessInfo.processInfo.processIdentifier];
    PMDiagnosticsWrite(marker.UTF8String);
}

void PMDiagnosticsWrite(const char *message) {
    if (!message || !*message) return;
    @autoreleasepool {
        @synchronized ([PMDiagnosticsFileName self]) {
            NSString *path = PMDiagnosticsResolvedPath();
            NSFileManager *files = NSFileManager.defaultManager;
            [files createDirectoryAtPath:[path stringByDeletingLastPathComponent]
             withIntermediateDirectories:YES attributes:nil error:nil];
            if (![files fileExistsAtPath:path]) [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
            static NSDateFormatter *formatter;
            static dispatch_once_t once;
            dispatch_once(&once, ^{
                formatter = [NSDateFormatter new];
                formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
                formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
            });
            NSString *line = [NSString stringWithFormat:@"[%@] [session %@] %s\n", [formatter stringFromDate:NSDate.date], PMDiagnosticsSessionID ?: @"unknown", message];
            NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
            if (handle && data) {
                [handle seekToEndOfFile];
                [handle writeData:data];
                unsigned long long size = [handle offsetInFile];
                [handle closeFile];
                if (size > PMDiagnosticsMaxBytes) {
                    NSData *existing = [NSData dataWithContentsOfFile:path];
                    if (existing.length > PMDiagnosticsMaxBytes / 2) {
                        NSUInteger start = existing.length - PMDiagnosticsMaxBytes / 2;
                        const uint8_t *bytes = (const uint8_t *)existing.bytes;
                        while (start < existing.length && bytes[start] != '\n') ++start;
                        if (start < existing.length) {
                            NSData *tail = [existing subdataWithRange:NSMakeRange(start + 1, existing.length - start - 1)];
                            [tail writeToFile:path atomically:YES];
                        }
                    }
                }
            }
            NSLog(@"[PhiMod] %s", message);
        }
    }
}

NSString *PMDiagnosticsPath(void) { return PMDiagnosticsResolvedPath(); }

NSString *PMDiagnosticsTail(NSUInteger maxLines) {
    @synchronized ([PMDiagnosticsFileName self]) {
        NSString *text = [NSString stringWithContentsOfFile:PMDiagnosticsResolvedPath()
                                                    encoding:NSUTF8StringEncoding error:nil];
        if (!text.length) return @"(PhiMod diagnostics are empty)";
        NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
        NSUInteger limit = maxLines ?: 200;
        NSUInteger start = lines.count > limit + 1 ? lines.count - limit - 1 : 0;
        return [[lines subarrayWithRange:NSMakeRange(start, lines.count - start)] componentsJoinedByString:@"\n"];
    }
}

void PMDiagnosticsClear(void) {
    @synchronized ([PMDiagnosticsFileName self]) {
        [@"" writeToFile:PMDiagnosticsResolvedPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSLog(@"[PhiMod] diagnostics cleared");
    }
}
