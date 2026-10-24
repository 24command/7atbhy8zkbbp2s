#import <Foundation/Foundation.h>
@interface PMSettings : NSObject
+ (instancetype)shared;
- (id)value:(NSString *)key;
- (BOOL)setValue:(id)value forKey:(NSString *)key error:(NSString **)error;
- (NSDictionary *)snapshot;
- (BOOL)validateSnapshot:(NSDictionary *)values error:(NSString **)error;
- (BOOL)replaceConfiguration:(NSDictionary *)values error:(NSString **)error;
@end

#ifdef __OBJC__
static inline BOOL PMSettingBool(const char *key){ NSString *name=[NSString stringWithUTF8String:key ?: ""]; return [[[PMSettings shared] value:name] boolValue]; }
static inline float PMSettingFloat(const char *key){ NSString *name=[NSString stringWithUTF8String:key ?: ""]; return [[[PMSettings shared] value:name] floatValue]; }
#else
inline bool PMSettingBool(const char*){ return false; }
inline float PMSettingFloat(const char*){ return 1.f; }
#endif
