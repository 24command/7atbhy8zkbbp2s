#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT void PMDiagnosticsWrite(const char *message);
FOUNDATION_EXPORT NSString *PMDiagnosticsPath(void);
FOUNDATION_EXPORT NSString *PMDiagnosticsTail(NSUInteger maxLines);
FOUNDATION_EXPORT void PMDiagnosticsClear(void);
NS_ASSUME_NONNULL_END
