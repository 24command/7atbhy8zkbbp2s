#import <Foundation/Foundation.h>
@interface PMSettings : NSObject
+ (instancetype)shared;
- (id)value:(NSString *)key;
- (BOOL)setValue:(id)value forKey:(NSString *)key error:(NSString **)error;
- (NSDictionary *)snapshot;
- (BOOL)validateSnapshot:(NSDictionary *)values error:(NSString **)error;
- (BOOL)replaceConfiguration:(NSDictionary *)values error:(NSString **)error;
@end
