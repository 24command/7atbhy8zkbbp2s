#import "PMSettings.h"
#include <cmath>
@interface PMSettings ()
@property(nonatomic,strong) NSUserDefaults *store;
@property(nonatomic,strong) NSDictionary *defaults;
@property(nonatomic,strong) NSDictionary *ranges;
@end
@implementation PMSettings
+ (instancetype)shared { static PMSettings *v; static dispatch_once_t once; dispatch_once(&once, ^{v=[PMSettings new];}); return v; }
- (instancetype)init {
 if ((self=[super init])) {
 self.store=NSUserDefaults.standardUserDefaults;
 self.defaults=@{@"enabled":@NO,@"autoplay":@NO,@"noise":@NO,@"unified":@0,@"perfect":@80,@"good":@180,@"radius":@1,@"holdGrace":@100,@"holdFx":@150,@"noiseGrace":@250,@"noiseVisual":@YES,@"clearOriginalNoise":@NO,@"fullScreen":@NO,@"accuracy":@NO,@"noCombo":@NO,@"challenge":@0,@"hpEnabled":@NO,@"hpMax":@200,@"hpPerfect":@1,@"hpGood":@(-4),@"hpBad":@(-16),@"hpMiss":@(-25),@"hpTopEffect":@YES,@"hpBackgroundEffect":@YES,@"hpRed":@30,@"hpBlue":@60,@"practiceMode":@NO,@"practiceLoop":@YES,@"practiceCountdown":@NO,@"practiceStart":@0,@"practiceEnd":@(-1),@"practicePosition":@0,@"playbackRate":@1,@"practiceWhiteUi":@NO,@"noteFlowEnabled":@NO,@"noteFlow":@1,@"showShortcuts":@YES,@"dynamicLargeTextures":@NO,@"skinEnabled":@NO,@"unlockAnimation":@NO,@"mainlineUnlock":@NO,@"customDrawer":@NO,@"legacyEffects":@NO,@"shortcutAutoPlay":@YES,@"shortcutNoise":@YES,@"shortcutUnified":@YES,@"shortcutChallenge":@YES,@"shortcutHp":@YES,@"shortcutFullScreen":@YES,@"shortcutAccuracy":@YES,@"shortcutEarlyLate":@YES,@"earlyLateHints":@NO,@"opacity":@0.96};
 self.ranges=@{@"perfect":@[@1,@1000],@"good":@[@1,@2000],@"radius":@[@0.3,@3],@"holdGrace":@[@0,@500],@"holdFx":@[@100,@2000],@"noiseGrace":@[@0,@1500],@"unified":@[@0,@4],@"challenge":@[@0,@2],@"practiceStart":@[@0,@100000],@"practiceEnd":@[@(-1),@100000],@"practicePosition":@[@0,@100000],@"playbackRate":@[@0,@5],@"hpMax":@[@1,@10000],@"hpPerfect":@[@(-10000),@10000],@"hpGood":@[@(-10000),@10000],@"hpBad":@[@(-10000),@10000],@"hpMiss":@[@(-10000),@10000],@"hpRed":@[@0,@100],@"hpBlue":@[@0,@100],@"noteFlow":@[@0,@5],@"opacity":@[@0,@1]};
 // Low opacity is allowed for this process; restore a usable entry on next launch.
 NSDictionary*saved=[self.store dictionaryForKey:@"phimod.ios.config.snapshot.v2"];
 id opacity=saved[@"opacity"]?:[self.store objectForKey:@"phimod.ios.config.opacity"];
 if(opacity&&[opacity doubleValue]<0.15){NSMutableDictionary*next=saved?[saved mutableCopy]:[NSMutableDictionary new];next[@"opacity"]=self.defaults[@"opacity"];[self.store setObject:next forKey:@"phimod.ios.config.snapshot.v2"];[self.store setObject:self.defaults[@"opacity"] forKey:@"phimod.ios.config.opacity"];}

 } return self;
}
- (id)value:(NSString *)key { return [self snapshot][key]; }
- (NSDictionary *)snapshot {
 NSDictionary *saved=[self.store dictionaryForKey:@"phimod.ios.config.snapshot.v2"];
 NSMutableDictionary *v=[NSMutableDictionary new];
 for(NSString *key in self.defaults)v[key]=saved[key] ?: [self.store objectForKey:[@"phimod.ios.config." stringByAppendingString:key]] ?: self.defaults[key];
 // Migrate the old single Accuracy switch, which changed score, to the explicit no-combo mode.
 if(!saved[@"noCombo"]){id legacy=saved[@"accuracy"] ?: [self.store objectForKey:@"phimod.ios.config.noCombo"];if(legacy)v[@"noCombo"]=legacy;}
 return v;
}
- (BOOL)validateSnapshot:(NSDictionary *)values error:(NSString **)error {
 NSString *message=nil;
 if(values.count!=self.defaults.count)message=@"Incomplete settings transaction";
 for(NSString *key in values){
  id value=values[key];NSArray *range=self.ranges[key];
  if(!self.defaults[key] || ![value isKindOfClass:NSNumber.class]){message=@"Unknown key or nonnumeric value";break;}
  double n=[value doubleValue];
  if(!std::isfinite(n)){message=@"Values must be finite";break;}
  if(range && (n<[range[0] doubleValue]||n>[range[1] doubleValue])){message=[NSString stringWithFormat:@"%@: range %@ - %@",key,range[0],range[1]];break;}
  if(!range && n!=0 && n!=1){message=@"Boolean must be 0 or 1";break;}
  if([@[@"unified",@"challenge"] containsObject:key] && floor(n)!=n){message=@"Mode must be an integer";break;}
 }
 if([values[@"perfect"] doubleValue]>[values[@"good"] doubleValue])message=@"Perfect must not exceed Good";
 if([values[@"hpRed"] doubleValue]>[values[@"hpBlue"] doubleValue])message=@"Red threshold must not exceed Blue";
 double practiceEnd=[values[@"practiceEnd"] doubleValue],practiceStart=[values[@"practiceStart"] doubleValue];
 if(practiceEnd>=0&&practiceEnd<=practiceStart)message=@"Practice end must exceed start";
 if(message){if(error)*error=message;return NO;}return YES;
}
- (BOOL)replaceConfiguration:(NSDictionary *)values error:(NSString **)error {
 if(![self validateSnapshot:values error:error])return NO;
 // One dictionary replacement: Save cannot partially commit interdependent
 // fields. Cancel never writes NSUserDefaults in the first place.
 [self.store setObject:[values copy] forKey:@"phimod.ios.config.snapshot.v2"];dispatch_async(dispatch_get_main_queue(),^{[NSNotificationCenter.defaultCenter postNotificationName:@"PhiModConfigurationChanged" object:nil];});return YES;
}
- (BOOL)setValue:(id)value forKey:(NSString *)key error:(NSString **)error {
 NSMutableDictionary *candidate=[[self snapshot] mutableCopy];
 if(!value||!key){if(error)*error=@"Missing key/value";return NO;}
 candidate[key]=value;return [self replaceConfiguration:candidate error:error];
}
@end
