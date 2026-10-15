#import <Foundation/Foundation.h>
/// Portable gameplay rules are connected here; no backend is marked ready automatically.
@interface PMGameplay : NSObject
+ (NSDictionary<NSString *, id> *)previewConfiguration;
+ (NSDictionary<NSString *, id> *)validateConfiguration;
@end
