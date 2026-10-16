#import "PMGameplay.h"
#import "PMSettings.h"
#import "PMRuntime.h"
#include "../Core/PMGameplayCore.hpp"
#include <stdexcept>

namespace {
phimod::Options readOptions(NSDictionary *s) {
 phimod::Options o;
 o.judge=[s[@"enabled"] boolValue];o.autoplay=[s[@"autoplay"] boolValue];
 o.noise=[s[@"noise"] boolValue];o.clearNoise=[s[@"clearOriginalNoise"] boolValue];
 o.fullscreen=[s[@"fullScreen"] boolValue];o.accuracyOnly=[s[@"noCombo"] boolValue];
 o.hpEnabled=[s[@"hpEnabled"] boolValue];o.noiseVisual=[s[@"noiseVisual"] boolValue];
 o.hpTop=[s[@"hpTopEffect"] boolValue];o.hpBackground=[s[@"hpBackgroundEffect"] boolValue];
 double unified=[s[@"unified"] doubleValue],challenge=[s[@"challenge"] doubleValue];
 if(!std::isfinite(unified)||!std::isfinite(challenge)||unified!=std::floor(unified)||challenge!=std::floor(challenge)||unified<0||unified>4||challenge<0||challenge>2)
  throw std::invalid_argument("Invalid integer mode");
 o.unified=(int)unified;o.challenge=(int)challenge;
 o.perfectMs=[s[@"perfect"] floatValue];o.goodMs=[s[@"good"] floatValue];
 o.radius=[s[@"radius"] floatValue];o.holdGraceMs=[s[@"holdGrace"] floatValue];
 o.holdFxMs=[s[@"holdFx"] floatValue];o.noiseGraceMs=[s[@"noiseGrace"] floatValue];
 o.hpMax=[s[@"hpMax"] floatValue];o.hpDelta={[s[@"hpPerfect"] floatValue],[s[@"hpGood"] floatValue],[s[@"hpBad"] floatValue],[s[@"hpMiss"] floatValue]};
 o.hpRed=[s[@"hpRed"] floatValue]/100.f;o.hpBlue=[s[@"hpBlue"] floatValue]/100.f;
 o.validate();return o;
}
NSDictionary *errorResult(const std::exception &e) {return @{ @"ok":@NO,@"message":[NSString stringWithUTF8String:e.what()] ?: @"玩法配置错误" };}
}
@implementation PMGameplay
+ (NSDictionary<NSString *,id> *)validateConfiguration {
 try {auto options=readOptions([[PMSettings shared] snapshot]);
  return @{ @"ok":@YES,@"assisted":@(options.assisted()),@"backendReady":@NO,
   @"message":@"Config valid. Custom judge: use Read game state. Other gameplay/save/result hooks are not installed." };
 } catch(const std::exception &e){return errorResult(e);}
}
+ (NSDictionary<NSString *,id> *)previewConfiguration {
 try {
  auto options=readOptions([[PMSettings shared] snapshot]);
  // Computes a draft without forging Coverage or touching any Unity object.
  phimod::Windows windows;
  if(options.judge)windows={options.perfectMs/1000.f,options.goodMs/1000.f,std::max(.22f,options.goodMs/1000.f+.04f)};
  NSDictionary *actual=[PMRuntime gameSnapshot];
  NSString *live=[actual[@"ok"] boolValue] ? [NSString stringWithFormat:@"Actual P %.0f/G %.0f/B %.0f ms (%@)",[actual[@"perfectMs"] doubleValue],[actual[@"goodMs"] doubleValue],[actual[@"badMs"] doubleValue],actual[@"judgeStatus"]] : actual[@"message"];
  return @{ @"actualJudge":actual,@"ok":@YES,@"backendReady":@NO,@"assisted":@(options.assisted()),
   @"perfectMs":@(windows.perfect*1000),@"goodMs":@(windows.good*1000),@"badMs":@(windows.bad*1000),
   @"hpMax":@(options.hpMax),@"holdGraceMs":@(options.holdGraceMs),@"holdFxMs":@(options.holdFxMs),
   @"message":[NSString stringWithFormat:@"Preview P %.0f/G %.0f/B %.0f ms (preview does not apply); %@",windows.perfect*1000,windows.good*1000,windows.bad*1000,live] };
 } catch(const std::exception &e){return errorResult(e);}
}
@end
