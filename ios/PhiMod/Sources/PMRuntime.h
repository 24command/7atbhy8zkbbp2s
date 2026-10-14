#import <Foundation/Foundation.h>
/// Read-only metadata probe. Never invokes gameplay methods or writes fields.
@interface PMRuntime : NSObject
+ (NSString *)probe;
@end
