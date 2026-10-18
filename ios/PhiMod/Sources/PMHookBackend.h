#import <Foundation/Foundation.h>
@interface PMHookBackend : NSObject
+ (NSDictionary *)install;
+ (NSDictionary *)status;
+ (BOOL)protectJudgeChange; // latch before changing an active attempt
+ (NSDictionary *)practiceCommand:(NSInteger)action;
+ (NSDictionary *)practiceStatus;
+ (NSDictionary*)contentSnapshot;
+ (NSDictionary*)contentCommand:(NSString*)action identifier:(NSString*)identifier slot:(NSInteger)slot;
+ (void)contentPulse;
@end
