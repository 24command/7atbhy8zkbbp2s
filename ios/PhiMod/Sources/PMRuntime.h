#import <Foundation/Foundation.h>
/// All operations must be called on the UIKit/Unity main thread.
@interface PMRuntime : NSObject
+ (NSString *)probe;
+ (NSDictionary<NSString *, id> *)gameSnapshot;
+ (NSDictionary<NSString *, id> *)setGameLanguage:(NSInteger)language;
+ (NSDictionary<NSString *, id> *)applyJudgeSettings:(BOOL)enabled perfectMs:(double)perfectMs goodMs:(double)goodMs;
@end
