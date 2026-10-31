#pragma once
#import <Foundation/Foundation.h>
#include <cmath>

// Android org.json accepts numeric strings and treats optional JSON null as
// absent. Normalize only known schema fields; unknown condition types still fail.
inline id PMNormalizeUnlockRule(id raw){
 if(!raw||raw==NSNull.null)return nil;
 if(![raw isKindOfClass:NSDictionary.class])return raw;
 NSMutableDictionary*rule=[raw mutableCopy];
 void (^number)(NSMutableDictionary*,NSString*)=^(NSMutableDictionary*d,NSString*k){
  id v=d[k];if(v==NSNull.null){[d removeObjectForKey:k];return;}
  if(![v isKindOfClass:NSString.class])return;
  NSScanner*scanner=[NSScanner scannerWithString:v];double n=0;
  if([scanner scanDouble:&n]&&scanner.isAtEnd&&std::isfinite(n))d[k]=@(n);
 };
 void (^boolean)(NSMutableDictionary*,NSString*)=^(NSMutableDictionary*d,NSString*k){
  id v=d[k];if(v==NSNull.null){[d removeObjectForKey:k];return;}
  if([v isKindOfClass:NSString.class]){if([v caseInsensitiveCompare:@"true"]==NSOrderedSame)d[k]=@YES;else if([v caseInsensitiveCompare:@"false"]==NSOrderedSame)d[k]=@NO;}
 };
 for(NSString*k in @[@"mode",@"animation",@"chain",@"conditions"])if(rule[k]==NSNull.null)[rule removeObjectForKey:k];
 boolean(rule,@"enabled");number(rule,@"playTiming");
 if([rule[@"conditions"] isKindOfClass:NSArray.class]){
  NSMutableArray*out=[NSMutableArray new];
  for(id rawCondition in rule[@"conditions"]){
   if(![rawCondition isKindOfClass:NSDictionary.class]){[out addObject:rawCondition];continue;}
   NSMutableDictionary*c=[rawCondition mutableCopy];number(c,@"value");number(c,@"slot");[out addObject:c];
  }rule[@"conditions"]=out;
 }
 if([rule[@"chain"] isKindOfClass:NSDictionary.class]){NSMutableDictionary*c=[rule[@"chain"] mutableCopy];boolean(c,@"enabled");number(c,@"slot");rule[@"chain"]=c;}
 return rule;
}

// Mirrors UnlockRules.validate in the Android chapter format.
inline NSString *PMUnlockValidationError(id raw) {
 if (!raw) return nil;
 if (![raw isKindOfClass:NSDictionary.class]) return @"Unlock rule must be an object";
 NSDictionary *rule=raw;
 for(NSString *key in @[@"enabled",@"playTiming"])if(rule[key]&&![rule[key] isKindOfClass:NSNumber.class])return @"Invalid unlock rule value";
 NSInteger timing=[rule[@"playTiming"] integerValue];
 if(timing<0||timing>2)return @"Invalid unlock animation timing";
 NSString *mode=rule[@"mode"]?:@"all";
 if(![@[@"all",@"any"] containsObject:mode])return @"Invalid unlock condition mode";
 NSArray *conditions=rule[@"conditions"];
 if(conditions&&![conditions isKindOfClass:NSArray.class])return @"Unlock conditions must be an array";
 if(([rule[@"enabled"] boolValue]&&!conditions.count)||conditions.count>64)return @"Unlock rule requires 1 to 64 conditions";
 for(id rawCondition in conditions){
  if(![rawCondition isKindOfClass:NSDictionary.class])return @"Invalid unlock condition";
  NSDictionary *c=rawCondition;NSString *type=c[@"type"];
  if(![@[@"score",@"acc",@"fc",@"phi",@"rks",@"chapter"] containsObject:type?:@""])return @"Unknown unlock condition type";
  if(![type isEqualToString:@"rks"]&&(![c[@"ref"] isKindOfClass:NSString.class]||![c[@"ref"] length]))return @"Missing unlock reference";
  if(c[@"slot"]&&![c[@"slot"] isKindOfClass:NSNumber.class])return @"Invalid unlock difficulty";
  NSInteger slot=c[@"slot"]?[c[@"slot"] integerValue]:-1;
  if(slot < -1||slot>3)return @"Invalid unlock difficulty";
  if([@[@"score",@"acc",@"rks"] containsObject:type]){
   if(![c[@"value"] isKindOfClass:NSNumber.class])return @"Missing unlock threshold";
   double value=[c[@"value"] doubleValue],maximum=[type isEqualToString:@"score"]?1000000:100;
   if(!std::isfinite(value)||value<=0||value>maximum||([type isEqualToString:@"score"]&&value!=std::round(value)))return @"Invalid unlock threshold";
  }
 }
 NSString *animation=rule[@"animation"];
 if(animation&&![animation isKindOfClass:NSString.class])return @"Invalid unlock animation";
 if(animation.length){
  NSRegularExpression *pattern=[NSRegularExpression regularExpressionWithPattern:@"^unlock-[a-zA-Z0-9-]+\\.(mp4|gif)$" options:0 error:nil];
  if([pattern numberOfMatchesInString:animation options:0 range:NSMakeRange(0,animation.length)]!=1)return @"Invalid unlock animation filename";
 }
 NSDictionary *chain=rule[@"chain"];
 if(chain&&![chain isKindOfClass:NSDictionary.class])return @"Invalid unlock chain";
 if(chain[@"enabled"]&&![chain[@"enabled"] isKindOfClass:NSNumber.class])return @"Invalid unlock chain";
 if([chain[@"enabled"] boolValue]&&(![chain[@"song"] isKindOfClass:NSString.class]||![chain[@"song"] length]||![chain[@"slot"] isKindOfClass:NSNumber.class]||[chain[@"slot"] integerValue]<0||[chain[@"slot"] integerValue]>3))return @"Invalid unlock chain song or difficulty";
 return nil;
}
