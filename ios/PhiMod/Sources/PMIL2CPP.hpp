#pragma once
#import <Foundation/Foundation.h>
#include "../Core/PMJudgeCore.hpp"
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <cmath>
#include <cstring>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>
#include <map>
#include <initializer_list>
#include <type_traits>
#include <algorithm>
namespace pmbridge {
static constexpr char PMJudgeProtocol[16]="PMJudgeHook-v1";
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

    P (*class_from_type)(P)=nullptr;
    bool (*class_is_valuetype)(P)=nullptr;
    int32_t (*class_value_size)(P,uint32_t*)=nullptr;
    P (*object_get_class)(P)=nullptr;
    P (*class_get_parent)(P)=nullptr;
    P (*class_get_nested_types)(P,P*)=nullptr;
    const char *(*class_get_name)(P)=nullptr;
    P (*class_get_type)(P)=nullptr;
    P (*type_get_object)(P)=nullptr;
    P (*object_new)(P)=nullptr;
    P (*string_new)(const char*)=nullptr;
    uint32_t (*gchandle_new)(P,bool)=nullptr;
    P (*gchandle_get_target)(uint32_t)=nullptr;
    void (*gchandle_free)(uint32_t)=nullptr;
    void (*field_set_value)(P,P,P)=nullptr;
    P (*array_new)(P,uintptr_t)=nullptr;
    uintptr_t (*array_length)(P)=nullptr;
    std::map<std::pair<P,std::string>,P> fieldCache;
    std::map<std::string,P> typeCache;
    std::map<std::pair<P,std::string>,P> methodCache;
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
        PM_API(class_from_type); PM_API(class_is_valuetype); PM_API(class_value_size);
        PM_API(object_get_class); PM_API(class_get_parent); PM_API(class_get_nested_types);
        PM_API(class_get_name); PM_API(class_get_type); PM_API(type_get_object);
        PM_API(object_new); PM_API(string_new); PM_API(gchandle_new); PM_API(gchandle_get_target);
        PM_API(gchandle_free); PM_API(field_set_value); PM_API(array_new); PM_API(array_length);
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
        std::string actual=name?name:"",wanted=expected;
        for(char &c:actual)if(c=='/'||c=='+')c='.';
        for(char &c:wanted)if(c=='/'||c=='+')c='.';
        bool same=name && actual==wanted;
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
    P type(const char *ns,const char *name) {
        std::string key=std::string(ns)+"."+name;
        auto found=typeCache.find(key);if(found!=typeCache.end())return found->second;
        size_t count=0;const P *assemblies=domain_get_assemblies(domain,&count);P match=nullptr;
        if(count>4096)throw std::runtime_error("Invalid assembly count");
        for(size_t i=0;i<count;++i) {
            P image=assembly_get_image(assemblies[i]);P c=class_from_name(image,ns,name);
            if(c){if(match && match!=c)throw std::runtime_error("Ambiguous managed type: "+key);match=c;}
        }
        if(!match)throw std::runtime_error("Missing managed type: "+key);
        typeCache[key]=match;return match;
    }
    P nested(P parent,const char *name) {
        P it=nullptr;while(P c=class_get_nested_types(parent,&it))if(!strcmp(class_get_name(c),name))return c;
        throw std::runtime_error(std::string("Missing nested type: ")+name);
    }
    P objectField(P obj,const char *name) {
        if(!obj)throw std::runtime_error(std::string("Null owner: ")+name);
        P c=object_get_class(obj);auto key=std::make_pair(c,std::string(name));
        auto found=fieldCache.find(key);if(found!=fieldCache.end())return found->second;
        P f=class_get_field_from_name(c,name);
        if(!f || (field_get_flags(f)&0x10))throw std::runtime_error(std::string("Missing instance field: ")+name);
        fieldCache[key]=f;return f;
    }
    template<class T> void checkClass(P c) {
        if(!c)throw std::runtime_error("Missing field/value class");
        if constexpr(std::is_same_v<T,P>) {
            if(class_is_valuetype(c))throw std::runtime_error("Value type used as object reference");
        } else {
            uint32_t alignment=0;
            if(!class_is_valuetype(c)||class_value_size(c,&alignment)!=sizeof(T))throw std::runtime_error("Value size contract mismatch");
            const char *expected=nullptr;
            if constexpr(std::is_same_v<T,bool>)expected="System.Boolean";
            if constexpr(std::is_same_v<T,int>)expected="System.Int32";
            if constexpr(std::is_same_v<T,float>)expected="System.Single";
            if(expected&&!typeIs(class_get_type(c),expected))throw std::runtime_error("Primitive type contract mismatch");
        }
    }
    template<class T> T get(P obj,const char *name) {P f=objectField(obj,name);checkClass<T>(class_from_type(field_get_type(f)));T v{};field_get_value(obj,f,&v);return v;}
    template<class T> void put(P obj,const char *name,T value){P f=objectField(obj,name);checkClass<T>(class_from_type(field_get_type(f)));field_set_value(obj,f,&value);}
    P resolve(P c,const char *name,std::initializer_list<const char*> params={},bool isStatic=false) {
        std::string signature=std::string(isStatic?"static:":"instance:")+name;
        for(auto p:params)signature+=std::string("|")+p;
        auto key=std::make_pair(c,signature);auto found=methodCache.find(key);if(found!=methodCache.end())return found->second;
        for(P owner=c;owner;owner=class_get_parent(owner)) {
            P it=nullptr,match=nullptr;
            while(P m=class_get_methods(owner,&it)) {
                if(strcmp(method_get_name(m),name)||method_get_param_count(m)!=params.size())continue;
                uint32_t impl=0;if(bool(method_get_flags(m,&impl)&0x10)!=isStatic)continue;
                size_t i=0;bool good=true;for(auto p:params)good=good&&typeIs(method_get_param(m,uint32_t(i++)),p);
                if(!good)continue;if(match)throw std::runtime_error("Ambiguous overload: "+signature);match=m;
            }
            if(match){methodCache[key]=match;return match;}
        }
        throw std::runtime_error("Missing overload: "+signature);
    }
    P invokeOn(P method,P self,std::initializer_list<P> args={}) {
        std::vector<P> a(args);P ex=nullptr;
        P value=runtime_invoke(method,self,a.empty()?nullptr:a.data(),&ex);
        if(ex)throw std::runtime_error("Managed call failed");return value;
    }
    P call(P self,const char *name,std::initializer_list<const char*> params={},std::initializer_list<P> args={}) {
        if(!self)throw std::runtime_error(std::string("Null call: ")+name);
        return invokeOn(resolve(object_get_class(self),name,params),self,args);
    }
    P stat(P c,const char *name,std::initializer_list<const char*> params={},std::initializer_list<P> args={}) {
        return invokeOn(resolve(c,name,params,true),nullptr,args);
    }
    template<class T> T unbox(P obj) {if(!obj)throw std::runtime_error("Null boxed value");checkClass<T>(object_get_class(obj));T v{};P data=object_unbox(obj);if(!data)throw std::runtime_error("Unbox failed");memcpy(&v,data,sizeof(v));return v;}
    int count(P list){return list?unbox<int>(call(list,"get_Count")):0;}
    P at(P list,int index){return call(list,"get_Item",{"System.Int32"},{&index});}
    P arrayAt(P array,int index){return invokeOn(resolve(type("System","Array"),"GetValue",{"System.Int32"}),array,{&index});}
    P component(P obj,P c){return call(obj,"GetComponent",{"System.Type"},{type_get_object(class_get_type(c))});}
    P children(P obj,P c){bool all=true;return call(obj,"GetComponentsInChildren",{"System.Type","System.Boolean"},{type_get_object(class_get_type(c)),&all});}
    bool alive(P obj) {return obj && unbox<bool>(stat(type("UnityEngine","Object"),"op_Implicit",{"UnityEngine.Object"},{obj}));}
    void text(P obj,const char *value){call(obj,"set_text",{"System.String"},{string_new(value)});}
    int32_t language(P getter) {
        P boxed=invoke(getter);
        if (!boxed) throw std::runtime_error("Language getter returned null");
        P value=object_unbox(boxed);
        if (!value) throw std::runtime_error("Language unbox failed");
        int32_t result; memcpy(&result,value,sizeof(result)); return result;
    }
};
}
