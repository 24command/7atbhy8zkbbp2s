#import "PMMetalShaders.h"
#import "PMDiagnostics.h"
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include "../Core/PMShaderSource.hpp"
#include "../Core/PMFullShaderCompiler.hpp"
#include <atomic>
#include <cstring>
#include <mutex>
#include <memory>
#include <map>
#include <fstream>
#include <array>
#include <set>
#include "../Vendor/phira-shaders/rpe_shader_presets.h"
namespace {
struct Effect {int index=0;double start=0,end=0;bool global=false,range=false;std::string name;pmshader::Source source;pmfullshader::Program full;bool fullCompiler=false;std::vector<uint8_t>defaultUniforms,uniformScratch;std::map<std::string,std::array<std::vector<pmshader::Key>,4>>tracks;id<MTLLibrary> library=nil;std::map<NSUInteger,id<MTLRenderPipelineState>>pipelines;};
struct Scratch {std::atomic<bool>busy{false};id<MTLTexture>a=nil,b=nil;std::map<int,id<MTLBuffer>>uniformBuffers;};
struct Session {NSMutableArray*compatibility=[NSMutableArray new];NSString*reportPath=nil;id<MTLSamplerState>sampler=nil;std::vector<Effect>effects;std::array<std::shared_ptr<Scratch>,3>scratch{std::make_shared<Scratch>(),std::make_shared<Scratch>(),std::make_shared<Scratch>()};};
std::mutex stateLock;
std::shared_ptr<Session> current;
std::atomic<double>chartTime{-1000};std::atomic<unsigned>generation{0};
CAMetalLayer*gameLayer=nil;BOOL savedFramebufferOnly=YES;
id<MTLDevice>device=nil;
std::atomic<bool>enabled{false};
std::set<std::string>logged;
void report(NSString*s){PMDiagnosticsWrite(s.UTF8String);}
#include "PMShaderRenderTrace.inc"
std::string unhex(const std::string&s){if(s=="-")return {};if(s.size()%2)throw std::runtime_error("Invalid shader hex");std::string out;auto digit=[](char c){if(c>='0'&&c<='9')return c-'0';if(c>='a'&&c<='f')return c-'a'+10;if(c>='A'&&c<='F')return c-'A'+10;throw std::runtime_error("Invalid shader hex digit");};for(size_t i=0;i<s.size();i+=2)out+=char(digit(s[i])*16+digit(s[i+1]));return out;}
CAMetalLayer*findMetal(CALayer*layer){if([layer isKindOfClass:CAMetalLayer.class])return (CAMetalLayer*)layer;for(CALayer*child in layer.sublayers){CAMetalLayer*result=findMetal(child);if(result)return result;}return nil;}
id<MTLRenderPipelineState>pipeline(Effect&e,MTLPixelFormat format){auto hit=e.pipelines.find(format);if(hit!=e.pipelines.end())return hit->second;MTLRenderPipelineDescriptor*d=[MTLRenderPipelineDescriptor new];d.vertexFunction=[e.library newFunctionWithName:@"pmVertex"];d.fragmentFunction=[e.library newFunctionWithName:e.fullCompiler?[NSString stringWithUTF8String:e.full.entry.c_str()]:@"pmFragment"];d.colorAttachments[0].pixelFormat=format;NSError*error=nil;id<MTLRenderPipelineState>p=[e.library.device newRenderPipelineStateWithDescriptor:d error:&error];e.pipelines[format]=p;if(!p)report([NSString stringWithFormat:@"Shader pipeline %@: %@",[NSString stringWithUTF8String:e.name.c_str()],error.localizedDescription]);return p;}
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
  std::shared_ptr<Scratch>scratch;
  for(auto&candidate:current->scratch){bool expected=false;if(candidate->busy.compare_exchange_strong(expected,true)){scratch=candidate;break;}}
  if(!scratch)return; // Never block the render thread waiting for the GPU.
  bool resized=!scratch->a||scratch->a.width!=target.width||scratch->a.height!=target.height||scratch->a.pixelFormat!=target.pixelFormat;
  if(resized||(active.size()>1&&!scratch->b)){
   MTLTextureDescriptor*d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:target.pixelFormat width:target.width height:target.height mipmapped:NO];d.storageMode=MTLStorageModePrivate;d.usage=MTLTextureUsageShaderRead|MTLTextureUsageRenderTarget;
   if(resized){scratch->a=[device newTextureWithDescriptor:d];scratch->b=nil;}
   if(active.size()>1&&!scratch->b)scratch->b=[device newTextureWithDescriptor:d];
  }
  id<MTLTexture>a=scratch->a,b=scratch->b;
  [buffer addCompletedHandler:^(id<MTLCommandBuffer>){scratch->busy=false;}];
  if(!a||(active.size()>1&&!b)){if(logged.insert("allocation").second)report(@"Shader skipped: Metal scratch texture allocation failed");return;}
  id<MTLBlitCommandEncoder>copy=[buffer blitCommandEncoder];if(!copy)return;
  [copy copyFromTexture:target sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(target.width,target.height,1) toTexture:a destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];[copy endEncoding];
  id<MTLTexture>input=a;
  for(size_t i=0;i<active.size();++i){Effect&e=*active[i].first;id<MTLTexture>output=i+1==active.size()?target:(input==a?b:a);
   Params params{};params.clock[0]=float(now);params.clock[1]=float(target.width);params.clock[2]=float(target.height);
   for(size_t u=0;u<e.source.uniforms.size();++u){const auto&uniform=e.source.uniforms[u];auto track=e.tracks.find(uniform.name);for(int c=0;c<uniform.size;++c)params.values[u][c]=track==e.tracks.end()?uniform.defaults[c]:pmshader::sample(track->second[c],now,uniform.defaults[c]);}
   if(e.fullCompiler){id<MTLBlitCommandEncoder>preserve=[buffer blitCommandEncoder];if(!preserve)return;[preserve copyFromTexture:input sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(target.width,target.height,1) toTexture:output destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];[preserve endEncoding];}
   MTLRenderPassDescriptor*pass=[MTLRenderPassDescriptor renderPassDescriptor];pass.colorAttachments[0].texture=output;pass.colorAttachments[0].loadAction=e.fullCompiler?MTLLoadActionLoad:MTLLoadActionDontCare;pass.colorAttachments[0].storeAction=MTLStoreActionStore;
   id<MTLRenderCommandEncoder>encoder=[buffer renderCommandEncoderWithDescriptor:pass];if(!encoder)return;
   [encoder setRenderPipelineState:active[i].second];[encoder setFragmentTexture:input atIndex:0];
   if(e.fullCompiler){
    auto&bytes=e.uniformScratch;bytes=e.defaultUniforms;
    for(const auto&uniform:e.full.uniforms){
     if(uniform.name=="time"){pmfullshader::put(bytes,uniform,0,now);continue;}
     if(uniform.name=="screenSize"||uniform.name=="pmRpeViewport"){pmfullshader::put(bytes,uniform,0,target.width);pmfullshader::put(bytes,uniform,1,target.height);continue;}
     if(uniform.name=="UVScale"){pmfullshader::put(bytes,uniform,0,1);pmfullshader::put(bytes,uniform,1,1);continue;}
     auto track=e.tracks.find(uniform.name);if(track==e.tracks.end())continue;
     for(unsigned channel=0;channel<std::min(4u,uniform.rows*uniform.columns*uniform.arrayCount);++channel)pmfullshader::put(bytes,uniform,channel,pmshader::sample(track->second[channel],now,channel<uniform.defaults.size()?uniform.defaults[channel]:0));
    }
    if(bytes.size()<=4096)[encoder setFragmentBytes:bytes.data() length:bytes.size() atIndex:0];
    else{auto&uniformBuffer=scratch->uniformBuffers[e.index];if(!uniformBuffer||uniformBuffer.length<bytes.size())uniformBuffer=[device newBufferWithLength:bytes.size() options:MTLResourceStorageModeShared];if(!uniformBuffer){[encoder endEncoding];return;}memcpy(uniformBuffer.contents,bytes.data(),bytes.size());[encoder setFragmentBuffer:uniformBuffer offset:0 atIndex:0];}
    [encoder setFragmentSamplerState:current->sampler atIndex:0];
   }else [encoder setFragmentBytes:&params length:sizeof(params) atIndex:0];[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[encoder endEncoding];input=output;
  }
  if(logged.insert("rendered").second)report(@"RPE Metal shader rendered on game drawable");
 }@catch(NSException*e){enabled=false;report([NSString stringWithFormat:@"Metal shader rendering disabled after exception: %@",e.reason]);}
}
void safeRender(id<MTLCommandBuffer>buffer,id<MTLDrawable>drawable){
 if(traceEnabled.load()){@try{tracePresent(buffer,drawable);}@catch(NSException*exception){(void)exception;traceEnabled=false;}}
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
 SEL encode=@selector(renderCommandEncoderWithDescriptor:);IMP originalEncode=class_getMethodImplementation(c,encode);
 if(originalEncode)installHook(c,encode,imp_implementationWithBlock(^id(id self,MTLRenderPassDescriptor*descriptor){tracePass(self,descriptor);return ((id(*)(id,SEL,MTLRenderPassDescriptor*))originalEncode)(self,encode,descriptor);}));
 SEL simple=@selector(presentDrawable:);IMP original=class_getMethodImplementation(c,simple);
 installHook(c,simple,imp_implementationWithBlock(^(id self,id drawable){safeRender(self,drawable);((void(*)(id,SEL,id))original)(self,simple,drawable);}));
 for(NSString*name in @[@"presentDrawable:atTime:",@"presentDrawable:afterMinimumDuration:"]){SEL selector=NSSelectorFromString(name);if(!class_getInstanceMethod(c,selector))continue;IMP orig=class_getMethodImplementation(c,selector);installHook(c,selector,imp_implementationWithBlock(^(id self,id drawable,double value){safeRender(self,drawable);((void(*)(id,SEL,id,double))orig)(self,selector,drawable,value);}));}
 report([NSString stringWithFormat:@"Metal presentation hook installed: %@",NSStringFromClass(c)]);
 done=true;
}
std::shared_ptr<Session>parse(NSString*folder,id<MTLDevice>compileDevice){
 auto session=std::make_shared<Session>();
 MTLSamplerDescriptor*sd=[MTLSamplerDescriptor new];sd.minFilter=MTLSamplerMinMagFilterLinear;sd.magFilter=MTLSamplerMinMagFilterLinear;sd.sAddressMode=MTLSamplerAddressModeClampToEdge;sd.tAddressMode=MTLSamplerAddressModeClampToEdge;session->sampler=[compileDevice newSamplerStateWithDescriptor:sd];if(!session->sampler)throw std::runtime_error("Shader sampler allocation failed");
 session->reportPath=[folder stringByAppendingPathComponent:@"shader-compatibility-ios.json"];std::map<int,Effect>effects;
 std::ifstream stream([[folder stringByAppendingPathComponent:@"effects.tsv"] fileSystemRepresentation]);std::string row;
 while(std::getline(stream,row)){std::istringstream in(row);char tag;int i;if(!(in>>tag))continue;
  if(tag=='F'){Effect e;int global;std::string name;if(!(in>>i>>global>>e.start>>e.end>>name)||i<0||i>=512||!std::isfinite(e.start)||!std::isfinite(e.end))continue;e.index=i;e.name=unhex(name);e.global=global!=0;effects[i]=e;}
  else if(tag=='R'){if(in>>i)effects[i].range=true;}
  else if(tag=='K'){char kind;std::string name;int c;pmshader::Key k;if((in>>kind>>i>>name>>c>>k.start>>k.end>>k.a>>k.b)&&kind=='F'&&i>=0&&i<512&&c>=0&&c<4&&std::isfinite(k.start)&&std::isfinite(k.end)&&std::isfinite(k.a)&&std::isfinite(k.b))effects[i].tracks[unhex(name)][c].push_back(k);}
 }
 for(auto&item:effects){auto&e=item.second;
  if(e.name.empty())continue;
  NSMutableDictionary*entry=[@{@"index":@(e.index),@"shader":[NSString stringWithUTF8String:e.name.c_str()]?:@"",@"scope":e.range?@"targetRange":e.global?@"global":@"chart-only",@"status":@"pending"}mutableCopy];[session->compatibility addObject:entry];
  // Present is the global boundary only. Do not misapply chart-only/ranged
  // effects to HUD/UI just to claim they are supported.
  if(!e.global||e.range){entry[@"status"]=@"unsupported-scope";entry[@"reason"]=@"Requires a verified pre-HUD/layer render target; the current hook receives the final drawable.";report([NSString stringWithFormat:@"Shader %d %@ skipped: %@ boundary not yet available",e.index,[NSString stringWithUTF8String:e.name.c_str()],e.range?@"targetRange":@"chart-only"]);continue;}
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
   // Keep the proven preset path; imported custom GLSL uses the real compiler.
   e.fullCompiler=e.name[0]=='/';
   if(e.fullCompiler){e.full=pmfullshader::compile(source);e.defaultUniforms=pmfullshader::defaults(e.full);e.uniformScratch=e.defaultUniforms;}else e.source=pmshader::translate(source);
   for(auto&track:e.tracks)for(auto&channel:track.second)std::stable_sort(channel.begin(),channel.end(),[](const auto&a,const auto&b){return a.start<b.start;});
   NSError*error=nil;MTLCompileOptions*options=[MTLCompileOptions new];options.fastMathEnabled=NO;
   std::string metalSource=e.fullCompiler?e.full.msl:e.source.msl;

   e.library=[compileDevice newLibraryWithSource:[NSString stringWithUTF8String:metalSource.c_str()] options:options error:&error];
   if(!e.library){entry[@"status"]=@"metal-compile-failed";entry[@"reason"]=error.localizedDescription?:@"No Metal library";report([NSString stringWithFormat:@"Shader %d %@ compile failed: %@",e.index,[NSString stringWithUTF8String:e.name.c_str()],error.localizedDescription]);continue;}
   entry[@"status"]=@"compiled";entry[@"uniforms"]=@(e.fullCompiler?e.full.uniforms.size():e.source.uniforms.size());entry[@"compiler"]=e.fullCompiler?@"glslang-SPIRV-Cross":@"preset-compatibility";session->effects.push_back(std::move(e));
  }catch(const std::exception&error){entry[@"status"]=@"unsupported-source";entry[@"reason"]=[NSString stringWithUTF8String:error.what()]?:@"Source conversion failed";report([NSString stringWithFormat:@"Shader %d %@ unsupported: %s",e.index,[NSString stringWithUTF8String:e.name.c_str()],error.what()]);}
 }
 return session;
}
}
void PMMetalShadersClear(){enabled=false;++generation;chartTime=-1000;std::lock_guard<std::mutex>guard(stateLock);current.reset();logged.clear();traceReset();if(gameLayer)gameLayer.framebufferOnly=savedFramebufferOnly;gameLayer=nil;}
void PMMetalShadersTick(double time){chartTime=time;}
void PMMetalShadersLoad(NSString*folder){
 PMMetalShadersClear();if(!folder.length)return;
 NSString*effects=[NSString stringWithContentsOfFile:[folder stringByAppendingPathComponent:@"effects.tsv"] encoding:NSUTF8StringEncoding error:nil];if(![effects hasPrefix:@"F "]&&![effects containsString:@"\nF "])return;
 try{
  device=MTLCreateSystemDefaultDevice();if(!device){report(@"Shader unavailable: Metal device missing");return;}
  for(UIScene*scene in UIApplication.sharedApplication.connectedScenes)if([scene isKindOfClass:UIWindowScene.class])for(UIWindow*window in ((UIWindowScene*)scene).windows){CAMetalLayer*layer=findMetal(window.layer);if(layer&&layer.device==device){gameLayer=layer;break;}}
  if(!gameLayer){report(@"Shader unavailable: game CAMetalLayer not found");return;}
  savedFramebufferOnly=gameLayer.framebufferOnly;gameLayer.framebufferOnly=NO;install();
  // Only request a trace for a package whose declared effects need unavailable stages.
  std::istringstream declarations(effects.UTF8String);std::string declaration;bool needsStages=false;
  while(std::getline(declarations,declaration)){std::istringstream row(declaration);char tag;int index,global;if(row>>tag){if(tag=='R')needsStages=true;else if(tag=='F'&&(row>>index>>global)&&!global)needsStages=true;}}
  if(needsStages)traceBegin(folder);
  unsigned token=generation.load();id<MTLDevice>compileDevice=device;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
   try{auto ready=parse(folder,compileDevice);std::lock_guard<std::mutex>guard(stateLock);if(token!=generation.load())return;
    // Compile pipelines off the render thread for the selected surface format.
    for(auto&e:ready->effects){bool ok=pipeline(e,gameLayer.pixelFormat)!=nil;for(NSMutableDictionary*entry in ready->compatibility)if([entry[@"index"]intValue]==e.index){entry[@"status"]=ok?@"pipeline-ready":@"pipeline-failed";break;}}
    // Emit only for the current session; do not overwrite the report from a newer load.
    NSError*reportError=nil;NSData*reportData=[NSJSONSerialization dataWithJSONObject:@{@"version":@1,@"backend":@"Metal final-drawable",@"deviceRenderVerified":@NO,@"effects":ready->compatibility} options:NSJSONWritingPrettyPrinted error:&reportError];
    if(!reportData||![reportData writeToFile:ready->reportPath options:NSDataWritingAtomic error:&reportError])report([NSString stringWithFormat:@"Shader compatibility report failed: %@",reportError.localizedDescription]);
    else report([@"Shader compatibility report: " stringByAppendingString:ready->reportPath]);
    current=ready;enabled=!ready->effects.empty();if(ready->effects.empty()&&!traceEnabled.load())dispatch_async(dispatch_get_main_queue(),^{if(token==generation.load())PMMetalShadersClear();});report([NSString stringWithFormat:@"RPE Metal global shaders ready: %lu",(unsigned long)ready->effects.size()]);
   }catch(const std::exception&e){report([NSString stringWithFormat:@"Shader session failed: %s",e.what()]);}
  }});
 }catch(const std::exception&e){report([NSString stringWithFormat:@"Shader attach failed: %s",e.what()]);PMMetalShadersClear();}
}
