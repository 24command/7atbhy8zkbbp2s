#import "PMRuntime.h"
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <cstring>
#include <string>
@implementation PMRuntime
+ (NSString *)probe {
 const char *image=nullptr;
 for(uint32_t i=0;i<_dyld_image_count();i++){
 const char *name=_dyld_get_image_name(i);
 if(name && strstr(name,"/UnityFramework.framework/UnityFramework")){image=name;break;}
 }
 if(!image)return @"UnityFramework 尚未加载";
 void *handle=dlopen(image,RTLD_LAZY|RTLD_NOLOAD);
 if(!handle)return @"无法取得 UnityFramework 句柄";
 auto domain=(void*(*)())dlsym(handle,"il2cpp_domain_get");
 auto assemblies=(const void**(*)(void*,size_t*))dlsym(handle,"il2cpp_domain_get_assemblies");
 auto assemblyImage=(void*(*)(const void*))dlsym(handle,"il2cpp_assembly_get_image");
 auto className=(void*(*)(void*,const char*,const char*))dlsym(handle,"il2cpp_class_from_name");
 auto current=(void*(*)())dlsym(handle,"il2cpp_thread_current");
 auto attach=(void*(*)(void*))dlsym(handle,"il2cpp_thread_attach");
 auto detach=(void(*)(void*))dlsym(handle,"il2cpp_thread_detach");
 if(!domain||!assemblies||!assemblyImage||!className||!current||!attach||!detach){dlclose(handle);return @"IL2CPP 导出接口不完整；未使用 Android 偏移回退";}
 void *d=domain();if(!d){dlclose(handle);return @"IL2CPP domain 尚未初始化，请稍后重试";}
 void *owned=nullptr;
 if(!current()){owned=attach(d);if(!owned){dlclose(handle);return @"IL2CPP 线程附加失败";}}
 size_t count=0;const void **list=assemblies(d,&count);
 const char *targets[]={"GameInformation","LevelControl","JudgeControl","Chapter","LevelRecord"};
 NSUInteger found=0;
 if(list)for(const char *target:targets){for(size_t i=0;i<count;i++){if(className(assemblyImage(list[i]),"",target)){found++;break;}}}
 if(owned)detach(owned);
 dlclose(handle);
 return [NSString stringWithFormat:@"程序集 %zu · 目标类型 %lu/5 · 只读探测，未安装 Hook",count,(unsigned long)found];
}
@end
