#import "PMRuntime.h"
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
// Deliberately opaque. Never dereference MethodInfo/Il2CppClass or Android layouts.
using P = void *;
struct Runtime {
    const mach_header_64 *imageHeader = nullptr;
    P handle = nullptr;
    P ownedThread = nullptr;
    P domain = nullptr;
    P (*domain_get)() = nullptr;
    const P *(*domain_get_assemblies)(P, size_t *) = nullptr;
    P (*assembly_get_image)(P) = nullptr;
    const char *(*image_get_name)(P) = nullptr;
    P (*class_from_name)(P, const char *, const char *) = nullptr;
    P (*thread_current)() = nullptr;
    P (*thread_attach)(P) = nullptr;
    void (*thread_detach)(P) = nullptr;
    P (*class_get_field_from_name)(P, const char *) = nullptr;
    int (*field_get_flags)(P) = nullptr;
    P (*field_get_type)(P) = nullptr;
    void (*field_static_get_value)(P, P) = nullptr;
    void (*field_static_set_value)(P, P) = nullptr;
    void (*field_get_value)(P, P, P) = nullptr;
    char *(*type_get_name)(P) = nullptr;
    void (*free_memory)(P) = nullptr;
    P (*class_get_methods)(P, P *) = nullptr;
    const char *(*method_get_name)(P) = nullptr;
    uint32_t (*method_get_param_count)(P) = nullptr;
    uint32_t (*method_get_flags)(P, uint32_t *) = nullptr;
    P (*method_get_param)(P, uint32_t) = nullptr;
    P (*method_get_return_type)(P) = nullptr;
    P (*runtime_invoke)(P, P, P *, P *) = nullptr;
    P (*object_unbox)(P) = nullptr;
    void (*runtime_class_init)(P) = nullptr;

    Runtime() = default;
    Runtime(const Runtime &) = delete;
    ~Runtime() {
        if (ownedThread && thread_detach) thread_detach(ownedThread);
        if (handle) dlclose(handle);
    }
    template<class T> void load(T &slot, const char *name) {
        slot = reinterpret_cast<T>(dlsym(handle, name));
        if (!slot) throw std::runtime_error(std::string("Missing export: ") + name);
    }
    void open() {
        if (![NSThread isMainThread]) throw std::runtime_error("Main thread required");
        const char *path = nullptr;
        const mach_header_64 *header = nullptr;
        for (uint32_t i=0; i<_dyld_image_count(); ++i) {
            const char *candidate = _dyld_get_image_name(i);
            if (candidate && strstr(candidate, "/UnityFramework.framework/UnityFramework")) {
                path=candidate; header=reinterpret_cast<const mach_header_64 *>(_dyld_get_image_header(i)); break;
            }
        }
        if (!path || !header || header->magic != MH_MAGIC_64)
            throw std::runtime_error("UnityFramework is not loaded");
        // Build gate: the supplied iOS 4.0.1 binary, not an Android offset table.
        const uint8_t expected[16]={0x6e,0x18,0x1f,0x31,0x75,0x0a,0x30,0x44,0xa7,0x3a,0x14,0x98,0xdc,0x2d,0x56,0xd4};
        bool matched=false;
        auto cursor=reinterpret_cast<const uint8_t *>(header+1);
        const auto end=cursor+header->sizeofcmds;
        for (uint32_t i=0;i<header->ncmds;++i) {
            if (cursor+sizeof(load_command)>end) break;
            auto cmd=reinterpret_cast<const load_command *>(cursor);
            if (cmd->cmdsize<sizeof(load_command) || cmd->cmdsize>size_t(end-cursor)) break;
            if (cmd->cmd==LC_UUID && cmd->cmdsize>=sizeof(uuid_command))
                matched=memcmp(reinterpret_cast<const uuid_command *>(cmd)->uuid,expected,16)==0;
            cursor+=cmd->cmdsize;
        }
        if (!matched) throw std::runtime_error("Unsupported UnityFramework UUID (expected supplied iOS 4.0.1)");
        imageHeader=header;
        handle=dlopen(path,RTLD_LAZY|RTLD_NOLOAD);
        if (!handle) throw std::runtime_error("Cannot open loaded UnityFramework");
#define PM_API(name) load(name,"il2cpp_" #name)
        PM_API(domain_get); PM_API(domain_get_assemblies); PM_API(assembly_get_image);
        PM_API(image_get_name); PM_API(class_from_name);
        PM_API(thread_current); PM_API(thread_attach); PM_API(thread_detach);
        PM_API(class_get_field_from_name); PM_API(field_get_flags); PM_API(field_get_type);
        PM_API(field_static_get_value); PM_API(field_static_set_value); PM_API(field_get_value); PM_API(type_get_name);
        load(free_memory,"il2cpp_free");
        PM_API(class_get_methods); PM_API(method_get_name); PM_API(method_get_param_count);
        PM_API(method_get_flags); PM_API(method_get_param); PM_API(method_get_return_type);
        PM_API(runtime_invoke); PM_API(object_unbox); PM_API(runtime_class_init);
#undef PM_API
        domain=domain_get();
        if (!domain) throw std::runtime_error("IL2CPP domain not ready; retry after title screen");
        if (!thread_current()) {
            ownedThread=thread_attach(domain);
            if (!ownedThread) throw std::runtime_error("IL2CPP thread attach failed");
        }
    }
    P klass(const char *name) {
        size_t count=0; const P *assemblies=domain_get_assemblies(domain,&count);
        if (!assemblies || count>4096) throw std::runtime_error("Invalid assembly inventory");
        for (size_t i=0;i<count;++i) {
            P image=assembly_get_image(assemblies[i]);
            const char *imageName=image ? image_get_name(image) : nullptr;
            if (!imageName || strcmp(imageName,"Assembly-CSharp.dll")) continue;
            P c=class_from_name(image,"",name);
            if (c) return c;
        }
        throw std::runtime_error(std::string("Missing Assembly-CSharp type: ")+name);
    }
    phimod::judge::PatchState *judgePatch(bool required) {
        const section_64 *code=nullptr,*data=nullptr;
        auto cursor=reinterpret_cast<const uint8_t *>(imageHeader+1);
        const auto end=cursor+imageHeader->sizeofcmds;
        for (uint32_t i=0;i<imageHeader->ncmds;++i) {
            if (cursor+sizeof(load_command)>end) throw std::runtime_error("Invalid load commands");
            auto cmd=reinterpret_cast<const load_command *>(cursor);
            if (cmd->cmdsize<sizeof(load_command) || cmd->cmdsize>size_t(end-cursor))
                throw std::runtime_error("Invalid command size");
            if (cmd->cmd==LC_SEGMENT_64 && cmd->cmdsize>=sizeof(segment_command_64)) {
                auto seg=reinterpret_cast<const segment_command_64 *>(cmd);
                if (seg->nsects>(cmd->cmdsize-sizeof(*seg))/sizeof(section_64))
                    throw std::runtime_error("Invalid section table");
                auto sections=reinterpret_cast<const section_64 *>(seg+1);
                for(uint32_t k=0;k<seg->nsects;++k) {
                    auto sec=&sections[k];
                    if (!strncmp(sec->sectname,"__pmjhook",16) && !strncmp(seg->segname,"__TEXT",16)) code=sec;
                    if (!strncmp(sec->sectname,"__pmjudge",16) && !strncmp(seg->segname,"__DATA",16)) data=sec;
                    if ((code==sec || data==sec) && (sec->addr<seg->vmaddr || sec->size>seg->vmsize || sec->addr-seg->vmaddr>seg->vmsize-sec->size))
                        throw std::runtime_error("Judge patch section outside segment");
                }
            }
            cursor+=cmd->cmdsize;
        }
        if (!code && !data && !required) return nullptr;
        if (!code || !data || code->size<32 || data->size!=sizeof(phimod::judge::PatchState))
            throw std::runtime_error("Judge hook missing: rebuild framework AND repackage IPA with updated tools");
        // UUID-gated binary has __TEXT.vmaddr=0. Section addresses are RVAs.
        auto base=reinterpret_cast<const uint8_t *>(imageHeader);
        auto descriptor=base+code->addr;
        uint32_t version=0,size=0; uint64_t stateAddress=0;
        memcpy(&version,descriptor+16,4);memcpy(&size,descriptor+20,4);memcpy(&stateAddress,descriptor+24,8);
        if (memcmp(descriptor,PMJudgeProtocol,16) || version!=1 || size!=sizeof(phimod::judge::PatchState) || stateAddress!=data->addr)
            throw std::runtime_error("Incompatible judge hook protocol");
        return reinterpret_cast<phimod::judge::PatchState *>(const_cast<uint8_t *>(base)+data->addr);
    }
    bool typeIs(P type,const char *expected) {
        char *name=type ? type_get_name(type) : nullptr;
        bool same=name && strcmp(name,expected)==0;
        if (name) free_memory(name);
        return same;
    }
    P field(P c,const char *name,const char *type,bool isStatic) {
        P f=class_get_field_from_name(c,name);
        if (!f || bool(field_get_flags(f)&0x10)!=isStatic || !typeIs(field_get_type(f),type))
            throw std::runtime_error(std::string("Field contract mismatch: ")+name);
        return f;
    }
    template<class T> T staticValue(P c,const char *name,const char *type) {
        T v{}; field_static_get_value(field(c,name,type,true),&v); return v;
    }
    template<class T> void setStaticValue(P c,const char *name,const char *type,T value) {
        P f=field(c,name,type,true); field_static_set_value(f,&value);
    }
    P mainGame() {
        // The static field itself keeps this object alive. Do not retain across UI callbacks.
        P main=staticValue<P>(klass("GameInformation"),"_main","GameInformation");
        if (!main) throw std::runtime_error("GameInformation not ready; enter the game first");
        return main;
    }
    P method(P c,const char *name,const char *result,const char *parameter=nullptr) {
        P iterator=nullptr; P match=nullptr;
        while (P m=class_get_methods(c,&iterator)) {
            const char *n=method_get_name(m);
            if (!n || strcmp(n,name) || method_get_param_count(m)!=(parameter?1u:0u)) continue;
            uint32_t implementation=0;
            if (!(method_get_flags(m,&implementation)&0x10) || !typeIs(method_get_return_type(m),result)) continue;
            if (parameter && !typeIs(method_get_param(m,0),parameter)) continue;
            if (match) throw std::runtime_error("Ambiguous managed method");
            match=m;
        }
        if (!match) throw std::runtime_error(std::string("Method contract mismatch: ")+name);
        return match;
    }
    P invoke(P method,P *args=nullptr) {
        P exception=nullptr;
        P result=runtime_invoke(method,nullptr,args,&exception);
        // Do not call exception.ToString: it may throw or allocate again.
        if (exception) throw std::runtime_error("Managed invocation threw; no further calls performed");
        return result;
    }
    int32_t language(P getter) {
        P boxed=invoke(getter);
        if (!boxed) throw std::runtime_error("Language getter returned null");
        P value=object_unbox(boxed);
        if (!value) throw std::runtime_error("Language unbox failed");
        int32_t result; memcpy(&result,value,sizeof(result)); return result;
    }
};
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
        return @"iOS 4.0.1 UUID 匹配 · 6/6 类型 · IL2CPP 接口就绪；未安装 Hook";
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
        static phimod::judge::Controller controller;
        auto actual=controller.apply(*patch,enabled,perfectMs,goodMs,read,write);
        return @{ @"ok":@YES,@"enabled":@(enabled),@"hookReady":@YES,
                  @"perfectMs":@(actual.perfect*1000),@"goodMs":@(actual.good*1000),@"badMs":@(actual.bad*1000),
                  @"message":[NSString stringWithFormat:enabled ? @"Judge verified P %.0f/G %.0f/B %.0f ms (frame hook)" : @"Original judge restored P %.0f/G %.0f/B %.0f ms",
                              actual.perfect*1000,actual.good*1000,actual.bad*1000] };
    } catch (const std::exception &e) { if(activePatch) activePatch->enabled=0; return failure(e); }
}
@end
