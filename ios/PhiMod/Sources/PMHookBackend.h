#import <Foundation/Foundation.h>
@interface PMHookBackend : NSObject
+ (NSDictionary *)install;
+ (NSDictionary *)status;
+ (BOOL)protectJudgeChange; // latch before changing an active attempt
@end
