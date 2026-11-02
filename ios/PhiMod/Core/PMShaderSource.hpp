#pragma once
#include <string>
#include <vector>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <algorithm>
#include <cmath>
namespace pmshader {
struct Uniform {std::string name;int size=1;float defaults[4]{};};
struct Source {std::string msl;std::vector<Uniform> uniforms;};
inline Source translate(std::string glsl){
 Source out;
 std::regex declaration(R"(uniform\s+(?:(?:lowp|mediump|highp)\s+)?(float|vec2|vec3|vec4)\s+(\w+)\s*;[ \t]*(?://[^\n]*)?)");
 for(std::sregex_iterator i(glsl.begin(),glsl.end(),declaration),end;i!=end;++i){
  Uniform u;u.name=(*i)[2];u.size=(*i)[1]=="float"?1:(*i)[1]=="vec2"?2:(*i)[1]=="vec3"?3:4;
  if(u.name=="time"||u.name=="screenSize"||u.name=="UVScale")continue;
  std::string row=(*i)[0];auto a=row.find('%'),b=a==std::string::npos?a:row.find('%',a+1);
  if(b!=std::string::npos){row=row.substr(a+1,b-a-1);std::replace(row.begin(),row.end(),',',' ');std::istringstream values(row);for(int c=0;c<u.size;++c)values>>u.defaults[c];}
  if(out.uniforms.size()>=64)throw std::runtime_error("Shader exceeds 64 uniforms");
  out.uniforms.push_back(u);
 }
 glsl=std::regex_replace(glsl,std::regex(R"(/\*[\s\S]*?\*/|//[^\n]*)"),"");
 glsl=std::regex_replace(glsl,std::regex(R"(#\s*version[^\n]*)"),"");
 glsl=std::regex_replace(glsl,std::regex(R"(precision\s+\w+\s+\w+\s*;)"),"");
 glsl=std::regex_replace(glsl,std::regex(R"(uniform\s+(?:(?:lowp|mediump|highp)\s+)?(?:float|vec2|vec3|vec4)\s+\w+\s*;)"),"");
 glsl=std::regex_replace(glsl,std::regex(R"(uniform\s+(?:(?:lowp|mediump|highp)\s+)?sampler2D\s+screenTexture\s*;)"),"");
 glsl=std::regex_replace(glsl,std::regex(R"(varying\s+(?:(?:lowp|mediump|highp)\s+)?vec2\s+uv\s*;)"),"");
 if(std::regex_search(glsl,std::regex(R"(\b(uniform|varying|attribute|sampler2D|textureCube)\b)")))throw std::runtime_error("Unsupported GLSL declaration or operation (supported: float/vec2/vec3/vec4 uniforms and screenTexture)");
 std::regex main(R"(void\s+main\s*\(\s*(?:void)?\s*\)\s*\{)");std::smatch match;
 if(!std::regex_search(glsl,match,main))throw std::runtime_error("GLSL main function missing");
 size_t start=match.position(),body=start+match.length(),last=body;int depth=1;
 for(;last<glsl.size();++last){if(glsl[last]=='{')++depth;else if(glsl[last]=='}'&&!--depth)break;}
 if(depth||last>=glsl.size())throw std::runtime_error("GLSL main is incomplete");
 // Helpers may legally follow main; do not swallow them into the fragment body.
 std::string helpers=glsl.substr(0,start)+"\n"+glsl.substr(last+1),code=glsl.substr(body,last-body);
 for(const auto&u:out.uniforms)if(std::regex_search(helpers,std::regex("\\b"+u.name+"\\b")))throw std::runtime_error("Uniform used in global helper; requires full GLSL compiler");
 for(const char*name:{"time","screenSize","UVScale","screenTexture","uv"})if(std::regex_search(helpers,std::regex(std::string("\\b")+name+"\\b")))throw std::runtime_error("Global shader input used outside main");
 auto convert=[](std::string s,bool fragment=false){
  // GLSL scalar matrix construction means a diagonal matrix, not a vector splat.
  for(int n=2;n<=4;++n){std::string name="mat"+std::to_string(n);s=std::regex_replace(s,std::regex("\\b"+name+"\\s*\\("),"pmMat"+std::to_string(n)+"(");s=std::regex_replace(s,std::regex("\\b"+name+"\\b"),"float"+std::to_string(n)+"x"+std::to_string(n));}

  for(const auto&pair:std::vector<std::pair<std::string,std::string>>{{"vec2","float2"},{"vec3","float3"},{"vec4","float4"},{"ivec2","int2"},{"ivec3","int3"},{"ivec4","int4"},{"gl_FragColor","pmColor"},{"mod","pmMod"},{"inversesqrt","rsqrt"},{"dFdx","dfdx"},{"dFdy","pmDFdy"}})s=std::regex_replace(s,std::regex("\\b"+pair.first+"\\b"),pair.second);
  s=std::regex_replace(s,std::regex(R"((?:texture2D|texture)\s*\(\s*screenTexture\s*,)"),"pmSample(source,");
  if(fragment)s=std::regex_replace(s,std::regex(R"(\breturn\s*;)"),"return pmColor;");
  if(fragment)s=std::regex_replace(s,std::regex(R"(\bdiscard\s*;)"),"return pmSample(source,uv);");
  else if(std::regex_search(s,std::regex(R"(\bdiscard\b)")))throw std::runtime_error("discard in a helper is unsupported");
  // Metal doesn't support double literals. GLSL floating literals are float.
  s=std::regex_replace(s,std::regex(R"(\b([0-9]+\.[0-9]*(?:[eE][+-]?[0-9]+)?)(?![\w.]))"),"$1f");
  return s;
 };
 std::ostringstream text;
 text<<R"MSL(#include <metal_stdlib>
using namespace metal;
struct PMVertex {float4 position [[position]];float2 uv;};
struct PMUniforms {float4 clock;float4 values[64];};
vertex PMVertex pmVertex(uint index [[vertex_id]]){float2 p=index==0?float2(-1,-1):index==1?float2(3,-1):float2(-1,3);return {float4(p,0,1),float2(p.x*.5f+.5f,.5f-p.y*.5f)};}
inline float4 pmSample(texture2d<float> image,float2 uv){constexpr sampler s(coord::normalized,address::clamp_to_edge,filter::linear);return image.sample(s,float2(uv.x,1.f-uv.y));}
// GLSL window Y runs upwards while Metal fragment Y runs downwards.
inline float pmDFdy(float x){return -dfdy(x);}
inline float2 pmDFdy(float2 x){return -dfdy(x);}
inline float3 pmDFdy(float3 x){return -dfdy(x);}
inline float4 pmDFdy(float4 x){return -dfdy(x);}
inline float pmMod(float x,float y){return x-y*floor(x/y);}
inline float2 pmMod(float2 x,float2 y){return x-y*floor(x/y);}
inline float2 pmMod(float2 x,float y){return x-y*floor(x/y);}
inline float3 pmMod(float3 x,float3 y){return x-y*floor(x/y);}
inline float3 pmMod(float3 x,float y){return x-y*floor(x/y);}
inline float4 pmMod(float4 x,float4 y){return x-y*floor(x/y);}
inline float4 pmMod(float4 x,float y){return x-y*floor(x/y);}
)MSL";
 // Explicit constructors retain GLSL column-major scalar/column semantics.
 for(int n=2;n<=4;++n){std::string type="float"+std::to_string(n)+"x"+std::to_string(n),column="float"+std::to_string(n),name="pmMat"+std::to_string(n);
  text<<"inline "<<type<<" "<<name<<"(float d){return "<<type<<"(";
  for(int c=0;c<n;++c){if(c)text<<",";text<<column<<"(";for(int r=0;r<n;++r){if(r)text<<",";text<<(c==r?"d":"0.f");}text<<")";}text<<");}\n";
  text<<"inline "<<type<<" "<<name<<"("<<type<<" m){return m;}\n";
  text<<"inline "<<type<<" "<<name<<"(";for(int c=0;c<n;++c){if(c)text<<",";text<<column<<" c"<<c;}text<<"){return "<<type<<"(";for(int c=0;c<n;++c){if(c)text<<",";text<<"c"<<c;}text<<");}\n";
  text<<"inline "<<type<<" "<<name<<"(";for(int v=0;v<n*n;++v){if(v)text<<",";text<<"float v"<<v;}text<<"){return "<<type<<"(";for(int c=0;c<n;++c){if(c)text<<",";text<<column<<"(";for(int r=0;r<n;++r){if(r)text<<",";text<<"v"<<c*n+r;}text<<")";}text<<");}\n";
 }
 text<<convert(helpers)<<"\nfragment float4 pmFragment(PMVertex in [[stage_in]],texture2d<float> source [[texture(0)]],constant PMUniforms& params [[buffer(0)]]) {\nfloat4 gl_FragCoord=float4(in.position.x,params.clock.z-in.position.y,in.position.z,in.position.w);float2 uv=float2(in.uv.x,1.f-in.uv.y);float time=params.clock.x;float2 screenSize=params.clock.yz;float2 UVScale=float2(1);float4 pmColor=float4(0,0,0,1);\n";
 for(size_t i=0;i<out.uniforms.size();++i){const auto&u=out.uniforms[i];text<<(u.size==1?"float":u.size==2?"float2":u.size==3?"float3":"float4")<<" "<<u.name<<"=params.values["<<i<<"]"<<(u.size==1?".x":u.size==2?".xy":u.size==3?".xyz":"")<<";\n";}
 text<<convert(code,true)<<"\nreturn float4(pmColor.rgb,1.f);\n}\n";out.msl=text.str();return out;
}
struct Key {double start,end,a,b;};
inline float sample(const std::vector<Key>&keys,double now,float fallback){auto it=std::upper_bound(keys.begin(),keys.end(),now,[](double n,const Key&k){return n<k.start;});if(it==keys.begin())return fallback;const auto&k=*--it;double q=k.end>k.start?std::clamp((now-k.start)/(k.end-k.start),0.,1.):1;return float(k.a+(k.b-k.a)*q);}
}
