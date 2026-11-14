#import <Foundation/Foundation.h>
#import "../PhiMod/Sources/PMSettings.h"
#include <cassert>
int main(){@autoreleasepool{
 NSUserDefaults*d=NSUserDefaults.standardUserDefaults;NSString*key=@"phimod.ios.config.snapshot.v2",*legacy=@"phimod.ios.config.opacity";id old=[d objectForKey:key],oldLegacy=[d objectForKey:legacy];
 @try{
  [d removeObjectForKey:key];[d removeObjectForKey:legacy];PMSettings*first=[PMSettings new];NSString*error=nil;
  assert([first setValue:@0 forKey:@"opacity" error:&error]);assert([[first value:@"opacity"]doubleValue]==0);assert([[first snapshot][@"opacity"]doubleValue]==0);
  PMSettings*restart=[PMSettings new];assert([[restart value:@"opacity"]doubleValue]==.96);
  for(NSNumber*v in @[@0,@.01,@.149,@.15,@.4,@1]){
   assert([restart setValue:v forKey:@"opacity" error:&error]);assert([[restart value:@"opacity"]doubleValue]==v.doubleValue);
   PMSettings*next=[PMSettings new];double expected=v.doubleValue<.15?.96:v.doubleValue;assert([[next value:@"opacity"]doubleValue]==expected);
  }
  [d removeObjectForKey:key];[d setObject:@.1 forKey:legacy];PMSettings*legacyRestart=[PMSettings new];assert([[legacyRestart value:@"opacity"]doubleValue]==.96);
  assert([restart setValue:@.4 forKey:@"opacity" error:&error]);PMSettings*again=[PMSettings new];assert([[again value:@"opacity"]doubleValue]==.4);
  assert(![again setValue:@(-.1) forKey:@"opacity" error:&error]);assert(![again setValue:@1.1 forKey:@"opacity" error:&error]);
 }@finally{if(old)[d setObject:old forKey:key];else[d removeObjectForKey:key];if(oldLegacy)[d setObject:oldLegacy forKey:legacy];else[d removeObjectForKey:legacy];}
 puts("PASS opacity below 0.15 remains current-session-only and defaults return on reinitialization");
}}
