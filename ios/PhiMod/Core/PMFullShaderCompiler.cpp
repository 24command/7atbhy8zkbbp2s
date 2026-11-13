#include "PMFullShaderCompiler.hpp"
#include "glslang/Public/ShaderLang.h"
#include "glslang/Public/ResourceLimits.h"
#include "SPIRV/GlslangToSpv.h"
#include "spirv_msl.hpp"
#include <mutex>
#include <regex>
#include <sstream>
#include <cstring>
#include <stdexcept>
#include <cmath>
#include <algorithm>
namespace pmfullshader {
namespace {
std::string modernize(std::string source){
 // Comments are metadata, not GLSL declarations; keep originals for default extraction.
 source=std::regex_replace(source,std::regex(R"(/\*[\s\S]*?\*/|//[^\n]*)"),"");
 if(std::regex_search(source,std::regex(R"(\bpmRpe\w*\b)")))throw std::runtime_error("Shader uses reserved pmRpe prefix");
 source=std::regex_replace(source,std::regex(R"(#\s*version[^\n]*)"),"");
 source=std::regex_replace(source,std::regex(R"(\bprecision\s+\w+\s+\w+\s*;)"),"");
 source=std::regex_replace(source,std::regex(R"(\b(lowp|mediump|highp)\b)"),"");
 // One canonical UV input, matching the pre-existing RPE OpenGL coordinates.
 source=std::regex_replace(source,std::regex(R"((?:layout\s*\([^)]*\)\s*)?\b(?:varying|in)\s+vec2\s+uv\s*;)"),"");
 source=std::regex_replace(source,std::regex(R"(\btexture2D\b)"),"texture");
 source=std::regex_replace(source,std::regex(R"(\bgl_FragColor\b)"),"pmOutput");
 return R"GLSL(#version 450
layout(location=0) in vec2 pmRpeRawUV;
layout(location=0) out vec4 pmOutput;
uniform vec2 pmRpeViewport;
vec4 pmRpeSample(sampler2D s,vec2 p){return texture(s,vec2(p.x,1.0-p.y));}
vec4 pmRpeSample(sampler2D s,vec2 p,float bias){return texture(s,vec2(p.x,1.0-p.y),bias);}
vec4 pmRpeSampleLod(sampler2D s,vec2 p,float lod){return textureLod(s,vec2(p.x,1.0-p.y),lod);}
vec4 pmRpeSampleGrad(sampler2D s,vec2 p,vec2 dx,vec2 dy){return textureGrad(s,vec2(p.x,1.0-p.y),vec2(dx.x,-dx.y),vec2(dy.x,-dy.y));}
#define uv vec2(pmRpeRawUV.x,1.0-pmRpeRawUV.y)
#define gl_FragCoord vec4(gl_FragCoord.x,pmRpeViewport.y-gl_FragCoord.y,gl_FragCoord.zw)
#define texture pmRpeSample
#define textureLod pmRpeSampleLod
#define textureGrad pmRpeSampleGrad
)GLSL"+source;
}
}
std::string vertexSource(){return R"MSL(
struct PMFullVertex {float4 position [[position]];float2 uv [[user(locn0)]];};
vertex PMFullVertex pmVertex(uint index [[vertex_id]]){float2 p=index==0?float2(-1,-1):index==1?float2(3,-1):float2(-1,3);return {float4(p,0,1),float2(p.x*.5f+.5f,.5f-p.y*.5f)};}
)MSL";}
Program compile(const std::string&source){
 if(source.size()>1024*1024)throw std::runtime_error("Shader source exceeds 1 MiB");
 static std::once_flag once;std::call_once(once,[]{if(!glslang::InitializeProcess())throw std::runtime_error("glslang initialization failed");});
 // Serialize compiler front-end use; compilation runs off Unity's render thread.
 static std::mutex mutex;std::lock_guard<std::mutex>guard(mutex);
 std::string text=modernize(source);const char*input=text.c_str();
 glslang::TShader shader(EShLangFragment);shader.setStrings(&input,1);
 shader.setEnvInput(glslang::EShSourceGlsl,EShLangFragment,glslang::EShClientVulkan,100);
 shader.setEnvClient(glslang::EShClientVulkan,glslang::EShTargetVulkan_1_0);
 shader.setEnvTarget(glslang::EShTargetSpv,glslang::EShTargetSpv_1_0);
 shader.setEnvInputVulkanRulesRelaxed();shader.setAutoMapBindings(true);shader.setAutoMapLocations(true);
 shader.setGlobalUniformBlockName("PMUniforms");shader.setGlobalUniformSet(0);shader.setGlobalUniformBinding(0);
 EShMessages messages=EShMessages(EShMsgSpvRules|EShMsgVulkanRules|EShMsgRelaxedErrors);
 if(!shader.parse(GetDefaultResources(),450,false,messages))throw std::runtime_error(std::string("GLSL: ")+shader.getInfoLog());
 glslang::TProgram linked;linked.addShader(&shader);
 if(!linked.link(messages)||!linked.mapIO())throw std::runtime_error(std::string("GLSL link: ")+linked.getInfoLog());
 std::vector<unsigned>spirv;glslang::SpvOptions options;options.disableOptimizer=true;
 glslang::GlslangToSpv(*linked.getIntermediate(EShLangFragment),spirv,&options);
 spirv_cross::CompilerMSL compiler(std::move(spirv));auto resources=compiler.get_shader_resources();
 if(!resources.storage_buffers.empty()||!resources.storage_images.empty()||!resources.push_constant_buffers.empty())throw std::runtime_error("Shader storage resources are not provided by RPE");
 Program result;result.entry="pmFullFragment";
 for(auto&r:resources.uniform_buffers){
  if(result.uniformBytes)throw std::runtime_error("Multiple uniform blocks are not supported by the RPE input ABI");
  auto&type=compiler.get_type(r.base_type_id);result.uniformBytes=compiler.get_declared_struct_size(type);
  if(result.uniformBytes>65536)throw std::runtime_error("Shader uniforms exceed 64 KiB");
  spirv_cross::MSLResourceBinding binding{};binding.stage=spv::ExecutionModelFragment;binding.desc_set=compiler.get_decoration(r.id,spv::DecorationDescriptorSet);binding.binding=compiler.get_decoration(r.id,spv::DecorationBinding);binding.msl_buffer=0;compiler.add_msl_resource_binding(binding);
  for(unsigned i=0;i<type.member_types.size();++i){auto&t=compiler.get_type(type.member_types[i]);Uniform u;u.name=compiler.get_member_name(type.self,i);u.offset=compiler.type_struct_member_offset(type,i);u.rows=t.vecsize;u.columns=t.columns;
   if(t.width!=32||t.basetype==spirv_cross::SPIRType::Struct)throw std::runtime_error("Uniform requires unsupported scalar width or nested struct packing");
   if(t.columns>1&&compiler.has_member_decoration(type.self,i,spv::DecorationRowMajor))throw std::runtime_error("Row-major uniform matrix packing is not enabled");
   if(t.basetype==spirv_cross::SPIRType::Int)u.scalar=Uniform::Int;else if(t.basetype==spirv_cross::SPIRType::UInt)u.scalar=Uniform::UInt;else if(t.basetype==spirv_cross::SPIRType::Boolean)u.scalar=Uniform::Bool;else if(t.basetype!=spirv_cross::SPIRType::Float)throw std::runtime_error("Unsupported reflected uniform scalar type");
   if(!t.array.empty()){if(t.array.size()!=1||!t.array_size_literal[0])throw std::runtime_error("Unsupported uniform array shape");u.arrayCount=t.array[0];u.arrayStride=compiler.type_struct_member_array_stride(type,i);}
   if(t.columns>1)u.matrixStride=compiler.type_struct_member_matrix_stride(type,i);
   if(u.arrayCount>4096||u.rows*u.columns*u.arrayCount>16384)throw std::runtime_error("Uniform array exceeds packing limit");
   if(std::regex_search(source,std::regex("\\buniform\\s+(?:(?:lowp|mediump|highp)\\s+)?bool\\s+"+u.name+"\\b")))u.scalar=Uniform::Bool;
   u.defaults.resize(u.rows*u.columns*u.arrayCount,0);
   std::regex declaration("\\b"+u.name+R"(\s*(?:\[[^\]]*\])?\s*;[ \t]*(?://[^\n]*)?)");std::smatch match;
   if(std::regex_search(source,match,declaration)){std::string row=match.str();size_t a=row.find('%'),b=a==std::string::npos?a:row.find('%',a+1);if(b!=std::string::npos){row=row.substr(a+1,b-a-1);std::replace(row.begin(),row.end(),',',' ');std::istringstream values(row);for(auto&v:u.defaults)values>>v;}}
   result.uniforms.push_back(std::move(u));
  }
 }
 for(auto&r:resources.sampled_images){if(compiler.get_name(r.id)!="screenTexture")throw std::runtime_error("RPE has no binding for sampler: "+compiler.get_name(r.id));spirv_cross::MSLResourceBinding binding{};binding.stage=spv::ExecutionModelFragment;binding.desc_set=compiler.get_decoration(r.id,spv::DecorationDescriptorSet);binding.binding=compiler.get_decoration(r.id,spv::DecorationBinding);binding.msl_texture=0;binding.msl_sampler=0;compiler.add_msl_resource_binding(binding);}
 auto msl=compiler.get_msl_options();msl.platform=spirv_cross::CompilerMSL::Options::iOS;msl.set_msl_version(2,3);compiler.set_msl_options(msl);
 compiler.rename_entry_point("main",result.entry,spv::ExecutionModelFragment);result.msl=compiler.compile()+vertexSource();
 // Inspect generated MSL (after macros/helpers), not raw GLSL substring guesses.
 // Only shaders able to discard fragments require copying old output pixels.
 result.discards=result.msl.find("discard_fragment")!=std::string::npos||result.msl.find("demote_to_helper")!=std::string::npos;
 return result;
}
void put(std::vector<uint8_t>&bytes,const Uniform&u,unsigned index,double value){
 if(index>=u.rows*u.columns*u.arrayCount||!std::isfinite(value))return;
 unsigned per=u.rows*u.columns,array=index/per,within=index%per,column=within/u.rows,row=within%u.rows;
 size_t offset=size_t(u.offset)+size_t(array)*u.arrayStride+(u.columns>1?size_t(column)*u.matrixStride:0)+size_t(row)*4;
 if(offset+4>bytes.size())throw std::runtime_error("Reflected uniform write outside buffer");
 uint32_t bits=0;if(u.scalar==Uniform::Float){float v=float(value);if(!std::isfinite(v))throw std::runtime_error("Uniform exceeds float range");std::memcpy(&bits,&v,4);}else if(u.scalar==Uniform::Bool)bits=value!=0;else if(u.scalar==Uniform::Int){int32_t v=int32_t(std::clamp(value,-2147483648.,2147483647.));std::memcpy(&bits,&v,4);}else bits=uint32_t(std::clamp(value,0.,4294967295.));std::memcpy(bytes.data()+offset,&bits,4);
}
std::vector<uint8_t> defaults(const Program&p){std::vector<uint8_t>bytes(std::max(size_t(16),p.uniformBytes));for(auto&u:p.uniforms)for(unsigned i=0;i<u.defaults.size();++i)put(bytes,u,i,u.defaults[i]);return bytes;}
}
