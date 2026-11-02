#include "../PhiMod/Core/PMShaderSource.hpp"
#include "../PhiMod/Vendor/phira-shaders/rpe_shader_presets.h"
#include <cassert>
#include <fstream>
#include <iostream>
int main(int argc,char**argv){
 for(const char*name:{"chromatic","circleBlur","fisheye","glitch","grayscale","noise","pixel","radialBlur","shockwave","vignette"}){
  auto result=pmshader::translate(rpeShaderPreset(name));
  assert(result.msl.find("fragment float4 pmFragment")!=std::string::npos);
  assert(result.msl.find("gl_FragColor")==std::string::npos);
  assert(result.msl.find("texture2D")==std::string::npos);
  if(argc>1){std::ofstream out(std::string(argv[1])+"/"+name+".metal");out<<result.msl;}
  std::cout<<name<<": "<<result.uniforms.size()<<" uniforms\n";
 }
 auto gray=pmshader::translate(rpeShaderPreset("grayscale"));assert(gray.uniforms[0].defaults[0]==1);
 bool failed=false;try{pmshader::translate("uniform mat4 matrix; void main(){gl_FragColor=vec4(1.0);}");}catch(const std::exception&){failed=true;}assert(failed);
 auto sameLine=pmshader::translate("uniform float a; uniform vec3 b; void main(){gl_FragColor=vec4(b*a,1.0);}");assert(sameLine.uniforms.size()==2&&sameLine.uniforms[1].size==3);
 auto extended=pmshader::translate("uniform vec3 tint; // %1,0.5,0.25%\nvoid helper(){return;}\nvoid main(){vec2 p=gl_FragCoord.xy/screenSize;vec3 c=mod(tint,1.0);if(p.x<0.0){discard;}gl_FragColor=texture(screenTexture,p)*vec4(c,1.0);return;}");
 assert(extended.uniforms.size()==1&&extended.uniforms[0].size==3&&extended.uniforms[0].defaults[2]==.25f);
 assert(extended.msl.find("void helper(){return;}")!=std::string::npos);
 assert(extended.msl.find("float3 tint=params.values[0].xyz")!=std::string::npos);
 assert(extended.msl.find("return pmSample(source,uv);")!=std::string::npos);
 if(argc>1){std::ofstream out(std::string(argv[1])+"/extended.metal");out<<extended.msl;}
 auto matrices=pmshader::translate("void main(){mat2 r=mat2(1.0,0.0,0.0,1.0);vec2 p=r*uv;mat3 identity=mat3(1.0);vec3 c=identity*vec3(p,1.0);gl_FragColor=vec4(c,1.0);}");
 assert(matrices.msl.find("float2x2 r=pmMat2(")!=std::string::npos);assert(matrices.msl.find("float3(d,0.f,0.f)")!=std::string::npos);
 auto trailing=pmshader::translate("float tone(float v); void main(){if(uv.x>0.0){gl_FragColor=vec4(tone(uv.x));}else{gl_FragColor=vec4(0.0);}} float tone(float v){return inversesqrt(v+1.0);}");
 assert(trailing.msl.find("float tone(float v){return rsqrt(v+1.0f);}")<trailing.msl.find("fragment float4 pmFragment"));
 auto derivative=pmshader::translate("void main(){vec2 p=dFdx(uv)+dFdy(uv);gl_FragColor=vec4(p,0.0,1.0);}");
 assert(derivative.msl.find("dfdx(uv)+pmDFdy(uv)")!=std::string::npos);
 bool incomplete=false;try{pmshader::translate("void main(){ if(true){gl_FragColor=vec4(1.0);}");}catch(const std::exception&){incomplete=true;}assert(incomplete);
 if(argc>1){for(auto&entry:std::vector<std::pair<std::string,std::string>>{{"matrices",matrices.msl},{"trailing-helper",trailing.msl},{"derivatives",derivative.msl}}){std::ofstream out(std::string(argv[1])+"/"+entry.first+".metal");out<<entry.second;}}
 std::vector<pmshader::Key>keys{{1,3,0,1},{4,5,1,0}};
 assert(pmshader::sample(keys,0,7)==7);assert(pmshader::sample(keys,2,7)==.5f);assert(pmshader::sample(keys,3.5,7)==1);assert(pmshader::sample(keys,4.5,7)==.5f);assert(pmshader::sample(keys,1,7)==0);
 std::cout<<"PASS 10 preset translations, defaults, rejection and time/seek interpolation\n";
}
