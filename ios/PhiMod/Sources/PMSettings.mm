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
 self.defaults=@{@"enabled":@NO,@"autoplay":@NO,@"noise":@NO,@"unified":@0,@"perfect":@80,@"good":@180,@"radius":@1,@"holdGrace":@100,@"holdFx":@150,@"noiseGrace":@250,@"noiseVisual":@YES,@"clearOriginalNoise":@NO,@"fullScreen":@NO,@"noCombo":@NO,@"challenge":@0,@"hpEnabled":@NO,@"hpMax":@200,@"hpPerfect":@1,@"hpGood":@(-4),@"hpBad":@(-16),@"hpMiss":@(-25),@"hpTopEffect":@YES,@"hpBackgroundEffect":@YES,@"hpRed":@30,@"hpBlue":@60,@"showShortcuts":@YES,@"opacity":@0.96};
 self.ranges=@{@"perfect":@[@1,@1000],@"good":@[@1,@2000],@"radius":@[@0.3,@3],@"holdGrace":@[@0,@500],@"holdFx":@[@100,@2000],@"noiseGrace":@[@0,@1500],@"unified":@[@0,@4],@"challenge":@[@0,@2],@"hpMax":@[@1,@10000],@"hpPerfect":@[@(-10000),@10000],@"hpGood":@[@(-10000),@10000],@"hpBad":@[@(-10000),@10000],@"hpMiss":@[@(-10000),@10000],@"hpRed":@[@0,@100],@"hpBlue":@[@0,@100],@"opacity":@[@0.15,@1]};
 } return self;
}
- (id)value:(NSString *)key { return [self.store objectForKey:[@"phimod.ios.config." stringByAppendingString:key]] ?: self.defaults[key]; }
- (NSDictionary *)snapshot { NSMutableDictionary *v=[NSMutableDictionary new]; for(NSString *key in self.defaults)v[key]=[self value:key]; return v; }
- (BOOL)setValue:(id)value forKey:(NSString *)key error:(NSString **)error {
 NSString *message=nil;
 if(!self.defaults[key] || ![value isKindOfClass:NSNumber.class])message=@"未知配置或非数值输入";
 else {
 double n=[value doubleValue]; NSArray *range=self.ranges[key];
 if(!std::isfinite(n))message=@"输入必须是有限数值";
 else if(range && (n<[range[0] doubleValue] || n>[range[1] doubleValue]))message=[NSString stringWithFormat:@"范围 %@–%@",range[0],range[1]];
 else if(!range && n!=0 && n!=1)message=@"开关只能为 0 或 1";
 else if(([@[@"unified",@"challenge"] containsObject:key]) && floor(n)!=n)message=@"模式必须为整数";
 else {
 NSMutableDictionary *candidate=[[self snapshot] mutableCopy];candidate[key]=value;
 if([candidate[@"perfect"] doubleValue]>[candidate[@"good"] doubleValue])message=@"Perfect 不得大于 Good";
 if([candidate[@"hpRed"] doubleValue]>[candidate[@"hpBlue"] doubleValue])message=@"红色阈值不得大于蓝色阈值";
 }
 }
 if(message){if(error)*error=message;return NO;}
 [self.store setObject:value forKey:[@"phimod.ios.config." stringByAppendingString:key]];return YES;
}
@end
