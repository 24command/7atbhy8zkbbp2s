#include "PMOptions.hpp"
#import "PMHookBackend.h"
#import "PMGameplay.h"
#import "PMSettings.h"
#import "PMRuntime.h"
#include "../Core/PMGameplayCore.hpp"
#include <stdexcept>

namespace {

NSDictionary *errorResult(const std::exception &e) {return @{ @"ok":@NO,@"message":[NSString stringWithUTF8String:e.what()] ?: @"玩法配置错误" };}
}
@implementation PMGameplay
 + (NSDictionary<NSString *,id> *)validateConfiguration {
 try {auto options=PMReadOptions([[PMSettings shared] snapshot]);NSDictionary *backend=[PMHookBackend install];
  bool supported=!options.noise&&!options.unified&&!options.clearNoise;
  return @{ @"ok":@(supported),@"assisted":@(options.assisted()),@"backendReady":backend[@"ok"],@"backend":backend,
   @"message":supported?backend[@"message"]:@"Disable Noise / Unified / No Noise: pipelines not implemented" };
 } catch(const std::exception &e){return errorResult(e);}
}
+ (NSDictionary<NSString *,id> *)previewConfiguration {
 try {
  auto options=PMReadOptions([[PMSettings shared] snapshot]);
  // Computes a draft without forging Coverage or touching any Unity object.
  phimod::Windows windows;
  if(options.judge)windows={options.perfectMs/1000.f,options.goodMs/1000.f,std::max(.22f,options.goodMs/1000.f+.04f)};
  NSDictionary *actual=[PMRuntime gameSnapshot];
  NSString *live=[actual[@"ok"] boolValue] ? [NSString stringWithFormat:@"Actual P %.0f/G %.0f/B %.0f ms (%@)",[actual[@"perfectMs"] doubleValue],[actual[@"goodMs"] doubleValue],[actual[@"badMs"] doubleValue],actual[@"judgeStatus"]] : actual[@"message"];
  return @{ @"actualJudge":actual,@"ok":@YES,@"backendReady":[PMHookBackend status][@"ok"],@"assisted":@(options.assisted()),
   @"perfectMs":@(windows.perfect*1000),@"goodMs":@(windows.good*1000),@"badMs":@(windows.bad*1000),
   @"hpMax":@(options.hpMax),@"holdGraceMs":@(options.holdGraceMs),@"holdFxMs":@(options.holdFxMs),
   @"message":[NSString stringWithFormat:@"Preview P %.0f/G %.0f/B %.0f ms (preview does not apply); %@",windows.perfect*1000,windows.good*1000,windows.bad*1000,live] };
 } catch(const std::exception &e){return errorResult(e);}
}
@end
