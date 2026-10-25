#pragma once
#import <Foundation/Foundation.h>

// Persist only semantic rule identity and player progress, never package progress.
inline NSString *PMUnlockSignature(NSDictionary *rule) {
 NSMutableArray *conditions=[NSMutableArray new];
 for(NSDictionary*c in rule[@"conditions"])[conditions addObject:@[c[@"type"]?:@"",c[@"ref"]?:@"",c[@"slot"]?:@(-1),c[@"value"]?:@0]];
 NSData *data=[NSJSONSerialization dataWithJSONObject:@[rule[@"mode"]?:@"all",conditions] options:0 error:nil];
 return [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
}
@interface PMUnlockProgress : NSObject
- (instancetype)initWithRoot:(NSString*)root;
- (BOOL)isOpen:(NSString*)identifier rule:(NSDictionary*)rule;
- (BOOL)isSeen:(NSString*)identifier rule:(NSDictionary*)rule;
- (BOOL)open:(NSString*)identifier rule:(NSDictionary*)rule error:(NSError**)error;
- (BOOL)seen:(NSString*)identifier signature:(NSString*)signature error:(NSError**)error;
@end
