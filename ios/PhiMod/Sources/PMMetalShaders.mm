#import "PMMetalShaders.h"
#import "PMDiagnostics.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include "../Core/PMShaderSource.hpp"
#include <atomic>
#include <mutex>
#include <memory>
#include <map>
#include <fstream>
#include <array>
#include <set>
#include "../Vendor/phira-shaders/rpe_shader_presets.h"
namespace {
struct Effect {int index=0;double start=0,end=0;bool global=false,range=false;std::string name;pmshader::Source source;std::map<std::string,std::array<std::vector<pmshader::Key>,4>>tracks;id<MTLLibrary> library=nil;std::map<NSUInteger,id<MTLRenderPipelineState>>pipelines;};
struct Scratch {std::atomic<bool>busy{false};id<MTLTexture>a=nil,b=nil;};
struct Session {std::vector<Effect>effects;std::array<std::shared_ptr<Scratch>,3>scratch{std::make_shared<Scratch>(),std::make_shared<Scratch>(),std::make_shared<Scratch>()};};
std::mutex stateLock;
std::shared_ptr<Session> current;
std::atomic<double>chartTime{-1000};std::atomic<unsigned>generation{0};
CAMetalLayer*gameLayer=nil;BOOL savedFramebufferOnly=YES;
id<MTLDevice>device=nil;
std::atomic<bool>enabled{false};
std::set<std::string>logged;
void report(NSString*s){PMDiagnosticsWrite(s.UTF8String);}
std::string unhex(const std::string&s){if(s=="-")return {};if(s.size()%2)throw std::runtime_error("Invalid shader hex");std::string out;auto digit=[](char c){if(c>='0'&&c<='9')return c-'0';if(c>='a'&&c<='f')return c-'a'+10;if(c>='A'&&c<='F')return c-'A'+10;throw std::runtime_error("Invalid shader hex digit");};for(size_t i=0;i<s.size();i+=2)out+=char(digit(s[i])*16+digit(s[i+1]));return out;}
CAMetalLayer*findMetal(CALayer*layer){if([layer isKindOfClass:CAMetalLayer.class])return (CAMetalLayer*)layer;for(CALayer*child in layer.sublayers){CAMetalLayer*result=findMetal(child);if(result)return result;}return nil;}
id<MTLRenderPipelineState>pipeline(Effect&e,MTLPixelFormat format){auto hit=e.pipelines.find(format);if(hit!=e.pipelines.end())return hit->second;MTLRenderPipelineDescriptor*d=[MTLRenderPipelineDescriptor new];d.vertexFunction=[e.library newFunctionWithName:@"pmVertex"];d.fragmentFunction=[e.library newFunctionWithName:@"pmFragment"];d.colorAttachments[0].pixelFormat=format;NSError*error=nil;id<MTLRenderPipelineState>p=[e.library.device newRenderPipelineStateWithDescriptor:d error:&error];e.pipelines[format]=p;if(!p)report([NSString stringWithFormat:@"Shader pipeline %@: %@",[NSString stringWithUTF8String:e.name.c_str()],error.localizedDescription]);return p;}
struct Params {float clock[4];float values[64][4];};
// Invoked on Unity's render thread on the SAME buffer immediately before its
// scheduled present. Retained command buffers retain temporary textures until
// GPU completion. Never wait for the GPU or read pixels back to the CPU.
void render(id<MTLCommandBuffer>buffer,id<MTLDrawable>drawable){
 if(!enabled.load()||!drawable||![drawable conformsToProtocol:@protocol(CAMetalDrawable)])return;
 std::lock_guard<std::mutex>guard(stateLock);
 id<CAMetalDrawable>metal=(id<CAMetalDrawable>)drawable;
 if(!current||metal.layer!=gameLayer||buffer.device!=device)return;
 // Buffers with unretained resources cannot own our temporary pass textures.
 if(!buffer.retainedReferences)return;
 double now=chartTime.load();if(!std::isfinite(now))return;
 std::vector<std::pair<Effect*,id<MTLRenderPipelineState>>>active;
 for(auto&e:current->effects)if(now>=e.start&&now<e.end){auto p=pipeline(e,metal.texture.pixelFormat);if(p)active.emplace_back(&e,p);}
 if(active.empty())return;
 id<MTLTexture>target=metal.texture;
 if(target.framebufferOnly){if(logged.insert("framebuffer").second)report(@"Shader deferred: drawable remains framebufferOnly");return;}
 @try {
  MTLTextureDescriptor*d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:target.pixelFormat width:target.width height:target.height mipmapped:NO];d.storageMode=MTLStorageModePrivate;d.usage=MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget;
  std::shared_ptr<Scratch>scratch;
  for(auto&candidate:current->scratch){bool expected=false;if(candidate->busy.compare_exchange_strong(expected,true)){scratch=candidate;break;}}
  if(!scratch)return; // Never block the render thread waiting for the GPU.
  if(!scratch->a||scratch->a.width!=target.width||scratch->a.height!=target.height||scratch->a.pixelFormat!=target.pixelFormat){scratch->a=[device newTextureWithDescriptor:d];scratch->b=nil;}
  if(active.size()>1&&!scratch->b)scratch->b=[device newTextureWithDescriptor:d];
  id<MTLTexture>a=scratch->a,b=scratch->b;
  [buffer addCompletedHandler:^(id<MTLCommandBuffer>){scratch->busy=false;}];
  if(!a||(active.size()>1&&!b)){if(logged.insert("allocation").second)report(@"Shader skipped: Metal scratch texture allocation failed");return;}
  id<MTLBlitCommandEncoder>copy=[buffer blitCommandEncoder];if(!copy)return;
  [copy copyFromTexture:target sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(target.width,target.height,1) toTexture:a destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];[copy endEncoding];
  id<MTLTexture>input=a;
  for(size_t i=0;i<active.size();++i){Effect&e=*active[i].first;id<MTLTexture>output=i+1==active.size()?target:(input==a?b:a);
   Params params{};params.clock[0]=float(now);params.clock[1]=float(target.width);params.clock[2]=float(target.height);
   for(size_t u=0;u<e.source.uniforms.size();++u){const auto&uniform=e.source.uniforms[u];auto track=e.tracks.find(uniform.name);for(int c=0;c<uniform.size;++c)params.values[u][c]=track==e.tracks.end()?uniform.defaults[c]:pmshader::sample(track->second[c],now,uniform.defaults[c]);}
   MTLRenderPassDescriptor*pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=output;pass.colorAttachments[0].loadAction=MTLLoadActionDontCare;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
   id<MTLRenderCommandEncoder>encoder=[buffer renderCommandEncoderWithDescriptor:pass];if(!encoder)return;
   [encoder setRenderPipelineState:active[i].second];[encoder setFragmentTexture:input atIndex:0];[encoder setFragmentBytes:&params length:sizeof(params) atIndex:0];[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[encoder endEncoding];input=output;
  }
  if(logged.insert("rendered").second)report(@"RPE Metal shader rendered on game drawable");
 }@catch(NSException*e){enabled=false;report([NSString stringWithFormat:@"Metal shader rendering disabled after exception: %@",e.reason]);}
}
void safeRender(id<MTLCommandBuffer>buffer,id<MTLDrawable>drawable){
 if(!enabled.load())return;
 static char stampKey;
 @autoreleasepool { @try {
  NSNumber*stamp=objc_getAssociatedObject(buffer,&stampKey);unsigned token=generation.load();
  if(stamp&&stamp.unsignedIntValue==token)return;
  objc_setAssociatedObject(buffer,&stampKey,@(token),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  try{render(buffer,drawable);}catch(const std::exception&e){enabled=false;report([NSString stringWithFormat:@"Shader rendering stopped: %s",e.what()]);}
 }@catch(NSException*e){enabled=false;report([NSString stringWithFormat:@"Shader presentation exception: %@",e.reason]);} }
}
void installHook(Class c,SEL selector,IMP replacement){Method m=class_getInstanceMethod(c,selector);if(!m)throw std::runtime_error("Metal presentation method missing");if(!class_addMethod(c,selector,replacement,method_getTypeEncoding(m)))method_setImplementation(class_getInstanceMethod(c,selector),replacement);}
void install(){
 static bool done=false;if(done)return;
 id<MTLCommandQueue>queue=[device newCommandQueue];id<MTLCommandBuffer>probe=[queue commandBuffer];Class c=object_getClass(probe);
 if(!c)throw std::runtime_error("Metal command buffer unavailable");
 SEL simple=@selector(presentDrawable:);IMP original=class_getMethodImplementation(c,simple);
 installHook(c,simple,imp_implementationWithBlock(^(id self,id drawable){safeRender(self,drawable);((void(*)(id,SEL,id))original)(self,simple,drawable);}));
 for(NSString*name in @[@"presentDrawable:atTime:",@"presentDrawable:afterMinimumDuration:"]){SEL selector=NSSelectorFromString(name);if(!class_getInstanceMethod(c,selector))continue;IMP orig=class_getMethodImplementation(c,selector);installHook(c,selector,imp_implementationWithBlock(^(id self,id drawable,double value){safeRender(self,drawable);((void(*)(id,SEL,id,double))orig)(self,selector,drawable,value);}));}
 report([NSString stringWithFormat:@"Metal presentation hook installed: %@",NSStringFromClass(c)]);
 done=true;
}
std::shared_ptr<Session>parse(NSString*folder,id<MTLDevice>compileDevice){
 auto session=std::make_shared<Session>();std::map<int,Effect>effects;
 std::ifstream stream([[folder stringByAppendingPathComponent:@"effects.tsv"] fileSystemRepresentation]);std::string row;
 while(std::getline(stream,row)){std::istringstream in(row);char tag;int i;if(!(in>>tag))continue;
  if(tag=='F'){Effect e;int global;std::string name;if(!(in>>i>>global>>e.start>>e.end>>name)||i<0||i>=512||!std::isfinite(e.start)||!std::isfinite(e.end))continue;e.index=i;e.name=unhex(name);e.global=global!=0;effects[i]=e;}
  else if(tag=='R'){if(in>>i)effects[i].range=true;}
  else if(tag=='K'){char kind;std::string name;int c;pmshader::Key k;if((in>>kind>>i>>name>>c>>k.start>>k.end>>k.a>>k.b)&&kind=='F'&&i>=0&&i<512&&c>=0&&c<4&&std::isfinite(k.start)&&std::isfinite(k.end)&&std::isfinite(k.a)&&std::isfinite(k.b))effects[i].tracks[unhex(name)][c].push_back(k);}
 }
 for(auto&item:effects){auto&e=item.second;
  if(e.name.empty())continue;
  // Present is the global boundary only. Do not misapply chart-only/ranged
  // effects to HUD/UI just to claim they are supported.
  if(!e.global||e.range){report([NSString stringWithFormat:@"Shader %d %@ skipped: %@ boundary not yet available",e.index,[NSString stringWithUTF8String:e.name.c_str()],e.range?@"targetRange":@"chart-only"]);continue;}
  try{
   std::string source;
   if(e.name[0]=='/'){
    NSString*root=[[folder stringByAppendingPathComponent:@"extensions"] stringByResolvingSymlinksInPath];NSString*rel=[NSString stringWithUTF8String:e.name.substr(1).c_str()];
    NSString*path=[[[root stringByAppendingPathComponent:rel]stringByStandardizingPath]stringByResolvingSymlinksInPath];
    if(![path hasPrefix:[root stringByAppendingString:@"/"]])throw std::runtime_error("Shader source path escapes extensions");
    NSDictionary*attr=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];if(!attr||[attr[NSFileSize] unsignedLongLongValue]>1024*1024)throw std::runtime_error("Shader source missing or exceeds 1 MiB");
    NSString*t=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];if(!t)throw std::runtime_error("Shader source is not UTF-8");source=t.UTF8String;
   }else source=rpeShaderPreset(e.name);
   if(source.empty())throw std::runtime_error("Unknown shader preset");
   e.source=pmshader::translate(source);
   for(auto&track:e.tracks)for(auto&channel:track.second)std::stable_sort(channel.begin(),channel.end(),[](const auto&a,const auto&b){return a.start<b.start;});
   NSError*error=nil;MTLCompileOptions*options=[MTLCompileOptions new];options.fastMathEnabled=NO;
   e.library=[compileDevice newLibraryWithSource:[NSString stringWithUTF8String:e.source.msl.c_str()] options:options error:&error];
   if(!e.library){report([NSString stringWithFormat:@"Shader %d %@ compile failed: %@",e.index,[NSString stringWithUTF8String:e.name.c_str()],error.localizedDescription]);continue;}
   session->effects.push_back(std::move(e));
  }catch(const std::exception&error){report([NSString stringWithFormat:@"Shader %d %@ unsupported: %s",e.index,[NSString stringWithUTF8String:e.name.c_str()],error.what()]);}
 }
 return session;
}
}
void PMMetalShadersClear(){enabled=false;++generation;chartTime=-1000;std::lock_guard<std::mutex>guard(stateLock);current.reset();logged.clear();if(gameLayer)gameLayer.framebufferOnly=savedFramebufferOnly;gameLayer=nil;}
void PMMetalShadersTick(double time){chartTime=time;}
void PMMetalShadersLoad(NSString*folder){
 PMMetalShadersClear();if(!folder.length)return;
 NSString*effects=[NSString stringWithContentsOfFile:[folder stringByAppendingPathComponent:@"effects.tsv"] encoding:NSUTF8StringEncoding error:nil];if(![effects hasPrefix:@"F "]&&![effects containsString:@"\nF "])return;
 try{
  device=MTLCreateSystemDefaultDevice();if(!device){report(@"Shader unavailable: Metal device missing");return;}
  for(UIScene*scene in UIApplication.sharedApplication.connectedScenes)if([scene isKindOfClass:UIWindowScene.class])for(UIWindow*window in ((UIWindowScene*)scene).windows){CAMetalLayer*layer=findMetal(window.layer);if(layer&&layer.device==device){gameLayer=layer;break;}}
  if(!gameLayer){report(@"Shader unavailable: game CAMetalLayer not found");return;}
  savedFramebufferOnly=gameLayer.framebufferOnly;gameLayer.framebufferOnly=NO;install();
  unsigned token=generation.load();id<MTLDevice>compileDevice=device;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
   try{auto ready=parse(folder,compileDevice);std::lock_guard<std::mutex>guard(stateLock);if(token!=generation.load())return;
    // Compile pipelines off the render thread for the selected surface format.
    for(auto&e:ready->effects)pipeline(e,gameLayer.pixelFormat);
    current=ready;enabled=!ready->effects.empty();if(ready->effects.empty())dispatch_async(dispatch_get_main_queue(),^{if(token==generation.load())PMMetalShadersClear();});report([NSString stringWithFormat:@"RPE Metal global shaders ready: %lu",(unsigned long)ready->effects.size()]);
   }catch(const std::exception&e){report([NSString stringWithFormat:@"Shader session failed: %s",e.what()]);}
  }});
 }catch(const std::exception&e){report([NSString stringWithFormat:@"Shader attach failed: %s",e.what()]);PMMetalShadersClear();}
}
