#import "PMDiagnostics.h"

static const NSUInteger PMDiagnosticsMaxBytes = 1024 * 1024;
static NSString * const PMDiagnosticsFileName = @"PhiMod-diagnostics.log";

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

void PMDiagnosticsWrite(const char *message) {
    if (!message || !*message) return;
    @autoreleasepool {
        @synchronized ([PMDiagnosticsFileName self]) {
            NSString *path = PMDiagnosticsResolvedPath();
            [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                                      withIntermediateDirectories:YES attributes:nil error:nil];
            NSDateFormatter *formatter = [NSDateFormatter new];
            formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
            NSString *line = [NSString stringWithFormat:@"[%@] %s\n", [formatter stringFromDate:NSDate.date], message];
            NSString *existing = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
            NSMutableString *contents = [existing mutableCopy];
            [contents appendString:line];
            if ([contents lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > PMDiagnosticsMaxBytes) {
                NSArray<NSString *> *allLines = [contents componentsSeparatedByString:@"\n"];
                NSUInteger start = allLines.count > 5001 ? allLines.count - 5001 : 0;
                contents = [[[allLines subarrayWithRange:NSMakeRange(start, allLines.count - start)] componentsJoinedByString:@"\n"] mutableCopy];
            }
            [contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
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
