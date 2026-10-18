#include "PMHPLife.hpp"
#include "../Core/PMFlowCore.hpp"
#include <cmath>
#include <cstdio>
#import "PMDiagnostics.h"
namespace pmhp {
using pmbridge::P;using pmbridge::Runtime;
namespace {
constexpr const char *ns="Phigros2.Level.Mods.SecretChallengeLife";
struct Color{float r,g,b,a;};
phimod::Options options;
phimod::FailureDelay failure;
uint32_t levelRoot=0,barRoot=0,modRoot=0,flashRoot=0,infoRoot=0,originalModsRoot=0,ownedModsRoot=0,scoreRoot=0;
bool enabled=false,finished=false,backgroundOwned=false,textOwned=false;
float life=0,originalOpacity=0,originalGlow=0;
Color originalMain{},originalCover{},originalText[2]{};
P target(Runtime&r,uint32_t h){return h?r.gchandle_get_target(h):nullptr;}
void release(Runtime&r,uint32_t &h){if(h){r.gchandle_free(h);h=0;}}
void setEnabled(Runtime&r,P p,bool value){if(r.alive(p))r.call(p,"set_enabled",{"System.Boolean"},{&value});}
void activeObject(Runtime&r,P p,bool value){if(r.alive(p))r.call(p,"SetActive",{"System.Boolean"},{&value});}
void destroy(Runtime&r,uint32_t &h){P p=target(r,h);if(r.alive(p))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{p});release(r,h);}
float time(Runtime&r){return r.unbox<float>(r.stat(r.type("UnityEngine","Time"),"get_time"));}
}
bool active(){return enabled;}
float normalized(){return options.hpMax>0?std::clamp(life/options.hpMax,0.f,1.f):0;}
void prepare(Runtime&r,P level,const phimod::Options&o){
 clear(r);options=o;enabled=o.hpEnabled;life=std::max(1.f,o.hpMax);failure.reset();finished=false;
 PMDiagnosticsWrite(enabled?"HP prepare: enabled":"HP prepare: disabled");
 if(!enabled)return;
 try{
 levelRoot=r.gchandle_new(level,false);
 P info=r.get<P>(r.mainGame(),"levelStartInfo");infoRoot=r.gchandle_new(info,false);
 P mods=r.get<P>(info,"levelMods");if(!mods)throw std::runtime_error("HP: missing LevelStartInfo.levelMods");
 originalModsRoot=r.gchandle_new(mods,false);
 P copy=r.object_new(r.object_get_class(mods));ownedModsRoot=r.gchandle_new(copy,false);r.call(copy,".ctor");
 for(int i=0;i<r.count(mods);++i)r.call(copy,"Add",{"System.String"},{r.at(mods,i)});
 // Exactly the Android loader path. Never enable GameInformation's official
 // secret-challenge state: that would award lives/promote tiers/write progress.
 for(const char*key:{"LevelMod/SecretChallengeLifeMod","LevelMod/HPDisplay"}){
  P code=r.string_new(key);if(!r.unbox<bool>(r.call(copy,"Contains",{"System.String"},{code})))r.call(copy,"Add",{"System.String"},{code});
 }
 r.put(info,"levelMods",copy);
  char message[128];snprintf(message,sizeof(message),"HP levelMods replaced count=%d",r.count(copy));PMDiagnosticsWrite(message);
  }catch(const std::exception&e){PMDiagnosticsWrite((std::string("HP prepare failed: ")+e.what()).c_str());clear(r);throw;}
}
void beginAttempt(float hp){
 life=std::max(0.f,std::isfinite(hp)?hp:options.hpMax);
 if(enabled&&life<=0)life=std::max(1.f,options.hpMax);
 failure.reset();finished=false;
 char message[128];snprintf(message,sizeof(message),"HP attempt initialized life=%.2f max=%.2f",life,options.hpMax);PMDiagnosticsWrite(message);
}
void barStart(Runtime&r,P self){
 if(!enabled)return;
 PMDiagnosticsWrite("HP bar Start enter");
 release(r,barRoot);barRoot=r.gchandle_new(self,false);
 P image=r.get<P>(self,"target"),materialTemplate=r.get<P>(self,"materialTemplate");
 if(!r.alive(image)||!r.alive(materialTemplate))throw std::runtime_error("HP: native life material missing");
 r.call(self,"ConfigureCanvas");r.put(self,"maximumLife",int(std::ceil(options.hpMax)));
 r.put(self,"displayedLife",1.f);r.put(self,"lifeVelocity",0.f);
 P material=r.object_new(r.type("UnityEngine","Material"));uint32_t root=r.gchandle_new(material,false);
 try{r.call(material,".ctor",{"UnityEngine.Material"},{materialTemplate});r.put(self,"runtimeMaterial",material);r.call(image,"set_material",{"UnityEngine.Material"},{material});}
 catch(...){r.gchandle_free(root);throw;}r.gchandle_free(root);
 P score=r.get<P>(target(r,levelRoot),"scoreControl");
 for(const char*name:{"combo","comboText"})r.stat(r.type(ns,"SecretChallengeLifeMod"),"EnableTrueShadow",{"UnityEngine.Component"},{r.get<P>(score,name)});
 setEnabled(r,image,options.hpTop);r.call(self,"ApplyShaderParameters");
 PMDiagnosticsWrite("HP bar Start configured");
}
// GetNormalizedLife can also run on another official bar; never hijack it.
bool ownsBar(Runtime&r,P self){return enabled&&target(r,barRoot)==self;}
void barUpdate(Runtime&r,P self){
 if(finished)return;
 P material=r.get<P>(self,"runtimeMaterial");if(!r.alive(material))return;
 // iOS inlines GetNormalizedLife in Update; its standalone hook alone has
 // no effect here. Reuse the exact native smoothing and shader function.
 float current=r.get<float>(self,"displayedLife"),targetLife=normalized();
 float velocity=r.get<float>(self,"lifeVelocity"),smooth=r.get<float>(self,"shrinkSmoothTime"),maximum=INFINITY;
 float dt=r.unbox<float>(r.stat(r.type("UnityEngine","Time"),"get_unscaledDeltaTime"));
 float next=r.unbox<float>(r.stat(r.type("UnityEngine","Mathf"),"SmoothDamp",{"System.Single","System.Single","System.Single&","System.Single","System.Single","System.Single"},{&current,&targetLife,&velocity,&smooth,&maximum,&dt}));
 if(next<.001f&&targetLife<=0)next=0;r.put(self,"displayedLife",next);r.put(self,"lifeVelocity",velocity);r.call(self,"ApplyShaderParameters");
}
void modStart(Runtime&r,P self){
 PMDiagnosticsWrite("HP mod Start enter");
 release(r,modRoot);modRoot=r.gchandle_new(self,false);
 P level=target(r,levelRoot);r.put(self,"levelControl",level);r.put(self,"scoreControl",r.get<P>(level,"scoreControl"));
 r.put<P>(self,"lifeHitFlash",nullptr);r.put(self,"subscribed",false);r.put(self,"failed",false);
 activeObject(r,r.get<P>(self,"redFlash"),false);
 // No stock Start: do not subscribe official challenge events or promotion.
  PMDiagnosticsWrite("HP mod Start configured");
}
void backgroundBefore(Runtime&r){
 if(!enabled||backgroundOwned)return;
 PMDiagnosticsWrite("HP background capture enter");P c=r.klass("HPDisplayControl");r.runtime_class_init(c);
 originalMain=r.unbox<Color>(r.stat(c,"get_MainColor"));originalCover=r.unbox<Color>(r.stat(c,"get_CoverColor"));
 originalOpacity=r.unbox<float>(r.stat(c,"get_Opacity"));originalGlow=r.unbox<float>(r.stat(c,"get_GlowOpacity"));backgroundOwned=true;
 PMDiagnosticsWrite("HP background captured");
}
void frame(Runtime&r,float hp){
 if(!enabled)return;life=hp;P bar=target(r,barRoot);
 if(r.alive(bar))setEnabled(r,r.get<P>(bar,"target"),options.hpTop&&!finished);
 if(!backgroundOwned)return;
 P c=r.klass("HPDisplayControl");float ratio=normalized(),opacity=options.hpBackground&&!finished?.1f:0.f,glow=0;
 Color color=ratio<=options.hpRed?Color{1,.12f,.18f,1}:ratio<=options.hpBlue?Color{.2f,.65f,1,1}:Color{1,1,1,1},clear{0,0,0,0};
 r.stat(c,"set_HP",{"System.Single"},{&ratio});r.stat(c,"set_Opacity",{"System.Single"},{&opacity});r.stat(c,"set_GlowOpacity",{"System.Single"},{&glow});
 r.stat(c,"set_MainColor",{"UnityEngine.Color"},{&color});r.stat(c,"set_CoverColor",{"UnityEngine.Color"},{&clear});
}
void scoreFrame(Runtime&r,P score){
 if(!enabled||finished)return;
 if(!scoreRoot)scoreRoot=r.gchandle_new(score,false);
 P mod=target(r,modRoot);
 if(textOwned&&r.alive(mod)&&r.get<P>(mod,"lifeHitFlash"))return;
 Color black{0,0,0,1};int i=0;
 for(const char*name:{"combo","comboText"}){
  P text=r.get<P>(score,name);if(!textOwned)originalText[i]=r.unbox<Color>(r.call(text,"get_color"));
  r.call(text,"set_color",{"UnityEngine.Color"},{&black});++i;
 }
 textOwned=true;
}
void flash(Runtime&r){P mod=target(r,modRoot);if(enabled&&!finished&&r.alive(mod))r.call(mod,"FlashLifeText");}
bool failing(){return failure.started();}
void finish(Runtime&);
void finishChallenge(Runtime&r,P progress){
 PMDiagnosticsWrite("HP challenge failure: preparing ChallengeModeOver");
 P gi=r.mainGame(),score=r.get<P>(progress,"scoreControl"),info=r.get<P>(progress,"levelInformation");
 r.call(score,"FreezeScore");
 P result=r.call(score,"GetLevelResultInfo");
 r.put(gi,"levelResultInfo",result);
 P items=r.get<P>(gi,"challengeSongItems");
 int index=r.get<int>(gi,"nowChallengeIndex")-1;
 if(!items||index<0||index>=r.count(items))throw std::runtime_error("HP challenge result index invalid");
 P codes=r.get<P>(gi,"noteCodes");
 P item=r.at(items,index);r.put(item,"result",result);r.put(item,"noteCodes",codes);
 for(int i=index+1;i<r.count(items);++i){
  P empty=r.object_new(r.klass("LevelResultInfo"));r.call(empty,".ctor");r.put(r.at(items,i),"result",empty);
  P emptyCodes=r.object_new(r.object_get_class(codes));r.call(emptyCodes,".ctor");r.put(r.at(items,i),"noteCodes",emptyCodes);
 }
 r.put(progress,"isPlaying",false);r.put(info,"levelOver",true);r.put(info,"canLevelOver",true);r.put(info,"canPause",false);
 finish(r);r.put(progress,"levelBreak",false);r.call(progress,"LevelBreak",{"System.String"},{r.string_new("ChallengeModeOver")});
 PMDiagnosticsWrite("HP challenge failure: ChallengeModeOver requested");
}
bool failureReady(Runtime&r,P progress){
 if(!failure.started()){
  PMDiagnosticsWrite("HP failureReady: begin freeze/fade");
  P info=r.get<P>(progress,"levelInformation");r.put(info,"canPause",false);r.put(info,"canLevelOver",false);
  r.put(r.get<P>(progress,"judgeControl"),"stopJudge",true);r.call(r.get<P>(progress,"scoreControl"),"FreezeScore");
  failure.begin(time(r)); // Only start the delay after critical operations succeed.
  P mod=target(r,modRoot);
  if(r.alive(mod)){
   r.put(mod,"failed",true);P prefab=r.get<P>(mod,"redFlash");
   if(r.alive(prefab)){
    P flash=r.stat(r.type("UnityEngine","Object"),"Instantiate",{"UnityEngine.Object"},{prefab});flashRoot=r.gchandle_new(flash,false);activeObject(r,flash,true);
   }
   float seconds=1;P audio=r.get<P>(progress,"audioSource");P fade=r.call(mod,"AudioFadeOut",{"AddressableAudioSource","System.Single"},{audio,&seconds});
   r.call(mod,"StartCoroutine",{"System.Collections.IEnumerator"},{fade});
  }
 }
  bool readyNow=failure.ready(time(r));
  if(readyNow)PMDiagnosticsWrite("HP failureReady: delay complete");
  return readyNow;
}
// Scene destruction may invalidate one native object while others remain alive.
// Each cleanup stage is best-effort; always release roots and reset ownership.
template<class F>void cleanup(const char*stage,F fn){try{fn();}catch(const std::exception&e){NSLog(@"[PhiMod] HP cleanup %s: %s",stage,e.what());}}
void finish(Runtime&r){
 if(!enabled||finished)return;finished=true;
 PMDiagnosticsWrite("HP finish: hide visuals");
 cleanup("bar",[&]{P bar=target(r,barRoot);if(r.alive(bar)){setEnabled(r,r.get<P>(bar,"target"),false);setEnabled(r,r.get<P>(bar,"lifeCanvas"),false);}});
 cleanup("flash coroutine",[&]{P mod=target(r,modRoot);if(r.alive(mod)){r.call(mod,"StopAllCoroutines");r.put<P>(mod,"lifeHitFlash",nullptr);activeObject(r,r.get<P>(mod,"redFlash"),false);}});
 cleanup("background",[&]{if(backgroundOwned){float zero=0;P c=r.klass("HPDisplayControl");r.stat(c,"set_Opacity",{"System.Single"},{&zero});r.stat(c,"set_GlowOpacity",{"System.Single"},{&zero});}});
 cleanup("failure flash",[&]{destroy(r,flashRoot);});
}
void clear(Runtime&r){
 finish(r);
 cleanup("level mods",[&]{P info=target(r,infoRoot);if(info&&r.get<P>(info,"levelMods")==target(r,ownedModsRoot))r.put(info,"levelMods",target(r,originalModsRoot));});
 cleanup("restore background",[&]{if(backgroundOwned){P c=r.klass("HPDisplayControl");
  r.stat(c,"set_MainColor",{"UnityEngine.Color"},{&originalMain});r.stat(c,"set_CoverColor",{"UnityEngine.Color"},{&originalCover});
  r.stat(c,"set_Opacity",{"System.Single"},{&originalOpacity});r.stat(c,"set_GlowOpacity",{"System.Single"},{&originalGlow});}});
 cleanup("restore text",[&]{P score=target(r,scoreRoot);if(textOwned&&r.alive(score)){int i=0;for(const char*name:{"combo","comboText"}){P text=r.get<P>(score,name);if(r.alive(text))r.call(text,"set_color",{"UnityEngine.Color"},{&originalText[i]});++i;}}});
 for(uint32_t*p:{&levelRoot,&barRoot,&modRoot,&flashRoot,&infoRoot,&originalModsRoot,&ownedModsRoot,&scoreRoot})release(r,*p);
 enabled=finished=backgroundOwned=textOwned=false;failure.reset();life=0;
}
void validate(Runtime&r){
 P bar=r.type(ns,"SecretChallengeLifeBar"),mod=r.type(ns,"SecretChallengeLifeMod");
 r.resolve(r.type("UnityEngine","Mathf"),"SmoothDamp",{"System.Single","System.Single","System.Single&","System.Single","System.Single","System.Single"},true);
 r.resolve(bar,"ConfigureCanvas");r.resolve(bar,"ApplyShaderParameters");r.resolve(mod,"FlashLifeText");
 r.resolve(mod,"AudioFadeOut",{"AddressableAudioSource","System.Single"});r.resolve(mod,"EnableTrueShadow",{"UnityEngine.Component"},true);
 for(const char*name:{"get_MainColor","get_CoverColor","get_Opacity","get_GlowOpacity"})r.resolve(r.klass("HPDisplayControl"),name,{},true);
}
}
