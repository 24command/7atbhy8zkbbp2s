#include "PMIL2CPP.hpp"
#import "PMRuntime.h"
#import "PMHookBackend.h"
#include "../Core/PMJudgeCore.hpp"
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <cmath>
#include <cstring>
#include <cstdint>
#include <stdexcept>
#include <string>

namespace {
__attribute__((used)) static const char PMJudgeProtocol[16]="PMJudgeHook-v1";
using pmbridge::Runtime;
using pmbridge::P;

NSString *errorText(const std::exception &e) {
    return [NSString stringWithUTF8String:e.what()] ?: @"Runtime error";
}
NSDictionary *failure(const std::exception &e) {return @{ @"ok":@NO, @"message":errorText(e) };}
}

@implementation PMRuntime
+ (NSString *)probe {
    try {
        Runtime r; r.open();
        const char *targets[]={"GameInformation","LevelControl","JudgeControl","Chapter","LevelRecord","MultiLanguageManager"};
        for (auto name:targets) r.klass(name);
        return [NSString stringWithFormat:@"iOS 4.0.1 UUID matched; 6/6 types; IL2CPP ready. %@", [PMHookBackend status][@"message"]];
    } catch (const std::exception &e) { return errorText(e); }
}
+ (NSDictionary<NSString *,id> *)gameSnapshot {
    try {
        Runtime r; r.open(); P main=r.mainGame();
        P languageClass=r.klass("MultiLanguageManager");
        int32_t language=r.language(r.method(languageClass,"GetCurrentLanguage","UnityEngine.SystemLanguage"));
        P judge=r.klass("JudgeControl");
        r.runtime_class_init(judge);
        float p=r.staticValue<float>(judge,"PerfectTimeRange","System.Single");
        float g=r.staticValue<float>(judge,"GoodTimeRange","System.Single");
        float b=r.staticValue<float>(judge,"BadTimeRange","System.Single");
        bool challenge=r.staticValue<bool>(judge,"InChallengeMode","System.Boolean");
        float rks=0;
        r.field_get_value(main,r.field(r.klass("GameInformation"),"<RankingScore>k__BackingField","System.Single",false),&rks);
        if (!std::isfinite(p)||!std::isfinite(g)||!std::isfinite(b)||!std::isfinite(rks))
            throw std::runtime_error("Game returned non-finite values");
        auto patch=r.judgePatch(false);
        bool active=patch && patch->enabled;
        bool verified=active && phimod::judge::matches({p,g,b},phimod::judge::configured(*patch));
        return @{ @"judgeHookReady":@(patch!=nullptr),@"judgeEnabled":@(active),@"judgeVerified":@(verified),
                  @"judgeStatus": active ? (verified ? @"Custom judge verified" : @"Judge readback mismatch") : @"Original judge",
                  @"ok":@YES,@"language":@(language),@"perfectMs":@(p*1000),@"goodMs":@(g*1000),
                  @"badMs":@(b*1000),@"challenge":@(challenge),@"rks":@(rks),
                  @"message":@"读取成功（瞬时快照；不代表草案已经应用）" };
    } catch (const std::exception &e) { return failure(e); }
}
+ (NSDictionary<NSString *,id> *)setGameLanguage:(NSInteger)language {
    if (language!=6 && language!=10 && language!=22 && language!=40 && language!=41)
        return @{ @"ok":@NO,@"message":@"不支持的语言编号" };
    bool invoked=false;
    try {
        Runtime r; r.open(); r.mainGame();
        P c=r.klass("MultiLanguageManager");
        // Resolve both contracts before any state-changing invocation.
        P setter=r.method(c,"SetLanguage","System.Void","UnityEngine.SystemLanguage");
        P getter=r.method(c,"GetCurrentLanguage","UnityEngine.SystemLanguage");
        int32_t before=r.language(getter), requested=static_cast<int32_t>(language);
        if (before!=requested) { P args[]={&requested}; invoked=true; r.invoke(setter,args); }
        int32_t after=r.language(getter);
        return @{ @"ok":@(after==requested),@"language":@(after),@"previousLanguage":@(before),
                  @"message":after==requested ? @"游戏语言已切换并读回确认；由游戏处理语言设置" : @"调用后读回不一致；未宣称生效，也未自动回滚" };
    } catch (const std::exception &e) {
        if (invoked) return @{ @"ok":@NO,@"message":[@"切换已尝试，当前状态未知；请刷新读取。" stringByAppendingString:errorText(e)] };
        return failure(e);
    }
}
+ (NSDictionary<NSString *,id> *)applyJudgeSettings:(BOOL)enabled perfectMs:(double)perfectMs goodMs:(double)goodMs {
    phimod::judge::PatchState *activePatch=nullptr;
    try {
        // Validate before any managed call or modification. Disabled edits do
        // not initialize/capture a baseline (Bootstrap doesn't call us for them).
        if (enabled) (void)phimod::judge::target(perfectMs,goodMs);
        Runtime r; r.open();
        auto patch=r.judgePatch(true); activePatch=patch;
        r.mainGame(); // never pretend an old IPA supports this
        P judge=r.klass("JudgeControl");
        r.runtime_class_init(judge); // .cctor must run BEFORE any window write
        P pf=r.field(judge,"PerfectTimeRange","System.Single",true);
        P gf=r.field(judge,"GoodTimeRange","System.Single",true);
        P bf=r.field(judge,"BadTimeRange","System.Single",true);
        auto read=[&]() {
            phimod::judge::Windows w{};
            r.field_static_get_value(pf,&w.perfect); r.field_static_get_value(gf,&w.good); r.field_static_get_value(bf,&w.bad);
            return w;
        };
        auto write=[&](phimod::judge::Windows w) {
            r.field_static_set_value(pf,&w.perfect); r.field_static_set_value(gf,&w.good); r.field_static_set_value(bf,&w.bad);
        };
        if(enabled && ![PMHookBackend protectJudgeChange]) throw std::runtime_error("Gameplay save protection not ready; judge was not enabled");
        static phimod::judge::Controller controller;
        auto actual=controller.apply(*patch,enabled,perfectMs,goodMs,read,write);
        return @{ @"ok":@YES,@"enabled":@(enabled),@"hookReady":@YES,
                  @"perfectMs":@(actual.perfect*1000),@"goodMs":@(actual.good*1000),@"badMs":@(actual.bad*1000),
                  @"message":[NSString stringWithFormat:enabled ? @"Judge verified P %.0f/G %.0f/B %.0f ms (frame hook)" : @"Original judge restored P %.0f/G %.0f/B %.0f ms",
                              actual.perfect*1000,actual.good*1000,actual.bad*1000] };
    } catch (const std::exception &e) { if(activePatch) activePatch->enabled=0; return failure(e); }
}
@end
