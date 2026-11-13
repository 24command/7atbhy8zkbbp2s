#include "../PhiMod/Core/PMFullShaderCompiler.hpp"
#include "../PhiMod/Vendor/phira-shaders/rpe_shader_presets.h"
#include <iostream>
#include <fstream>
#include <cassert>
#include <cstring>
#include <stdexcept>
#include <limits>
#ifdef NDEBUG
#error Shader tests must retain assertions
#endif
int main(int argc,char**argv){
 for(const char*name:{"chromatic","circleBlur","fisheye","glitch","grayscale","noise","pixel","radialBlur","shockwave","vignette"}){auto p=pmfullshader::compile(rpeShaderPreset(name));assert(!p.msl.empty());std::cout<<name<<" "<<p.uniformBytes<<" bytes\n";if(argc>1){std::ofstream out(std::string(argv[1])+"/"+name+".metal");out<<p.msl;}}
 auto p=pmfullshader::compile("uniform float time; uniform mat3 transform; uniform vec4 colors[2]; uniform sampler2D screenTexture; varying vec2 uv; vec4 sampleIt(vec2 p){return texture2D(screenTexture,p)*colors[1];} void main(){vec3 p=transform*vec3(uv,1.);gl_FragColor=sampleIt(p.xy+sin(time)*.01);}");assert(p.uniforms.size()>=3);auto bytes=pmfullshader::defaults(p);for(auto&u:p.uniforms)for(unsigned i=0;i<u.defaults.size();++i)pmfullshader::put(bytes,u,i,1);
 if(argc>1){std::ofstream out(std::string(argv[1])+"/matrix-helper-array.metal");out<<p.msl;}
 // Check actual reflected offsets/strides, not just successful compilation.
 for(auto&u:p.uniforms){
  if(u.name=="transform"){assert(u.rows==3&&u.columns==3&&u.matrixStride>=12);for(unsigned i=0;i<9;++i)pmfullshader::put(bytes,u,i,10+i);for(unsigned i=0;i<9;++i){float v=0;std::memcpy(&v,bytes.data()+u.offset+(i/3)*u.matrixStride+(i%3)*4,4);assert(v==float(10+i));}}
  if(u.name=="colors"){assert(u.arrayCount==2&&u.arrayStride>=16);pmfullshader::put(bytes,u,7,.125);float v;std::memcpy(&v,bytes.data()+u.offset+u.arrayStride+12,4);assert(v==.125f);}
 }
 auto fixture=[&](const char*name,const std::string&source){auto program=pmfullshader::compile(source);assert(program.msl.find("vertex PMFullVertex pmVertex")!=std::string::npos);if(argc>1){std::ofstream out(std::string(argv[1])+"/"+name+".metal");out<<program.msl;}return program;};
 auto coords=fixture("coordinates","uniform sampler2D screenTexture; varying vec2 uv; void main(){gl_FragColor=texture2D(screenTexture,uv)+vec4(uv,gl_FragCoord.y*0.001,0.0);}");
 assert(coords.msl.find("pmRpeViewport")!=std::string::npos);assert(!coords.discards);
 auto values=fixture("scalar-types","uniform int i; uniform uint u; uniform bool b; uniform vec3 tint; // %0.1,0.2,0.3%\nvoid main(){gl_FragColor=vec4(tint*(b?float(i+int(u)):1.),1.);}");
 auto packed=pmfullshader::defaults(values);bool sawDefault=false;
 for(auto&u:values.uniforms){if(u.name=="tint"){sawDefault=true;assert(u.defaults.size()==3&&u.defaults[2]>.29f);}if(u.name=="b"){pmfullshader::put(packed,u,0,-1);uint32_t value;std::memcpy(&value,packed.data()+u.offset,4);assert(value==1);}
 if(u.name=="i"){pmfullshader::put(packed,u,0,-3);int value;std::memcpy(&value,packed.data()+u.offset,4);assert(value==-3);}}
 assert(sawDefault);
 auto discard=fixture("discard-helper","uniform float time; uniform sampler2D screenTexture; varying vec2 uv; vec4 helper(vec2 p){if(p.x<0.25)discard;return texture2D(screenTexture,p+vec2(sin(time)*.01,0));}void main(){gl_FragColor=helper(uv);}");
 assert(discard.discards);
 fixture("macro-loop","uniform sampler2D screenTexture; varying vec2 uv;\n#define N 3\nvec4 sampleLater(vec2 p);void main(){vec4 c=vec4(0);for(int i=0;i<N;++i)c+=sampleLater(uv);gl_FragColor=c/float(N);}vec4 sampleLater(vec2 p){return textureLod(screenTexture,p,0.0);}");
 bool rejectedSampler=false;try{pmfullshader::compile("uniform sampler2D extra;varying vec2 uv;void main(){gl_FragColor=texture2D(extra,uv);}");}catch(const std::exception&){rejectedSampler=true;}assert(rejectedSampler);
 bool failed=false;try{pmfullshader::compile("void main(){ BAD SYNTAX }");}catch(...){failed=true;}assert(failed);
 std::cout<<"PASS 10 presets + reflected matrix/array/scalar packing + UV/fragment inputs + helper/loop/discard fixtures + invalid source rejection (assertions enabled)\n";
}
