#include "PMHPLife.hpp"
#import "PMContentStore.h"
#include "../Core/PMFlowCore.hpp"
#include <cmath>
#include <cstdio>
#include <chrono>
#import "PMDiagnostics.h"
namespace pmhp {
using pmbridge::P;using pmbridge::Runtime;
namespace {
constexpr const char *ns="Phigros2.Level.Mods.SecretChallengeLife";
struct Color{float r,g,b,a;};
phimod::Options options;
phimod::FailureDelay failure;
uint32_t levelRoot=0,barRoot=0,modRoot=0,flashRoot=0,scoreRoot=0;
struct VisualLoad {const char*key;uint32_t handle=0;bool settled=false;};
VisualLoad visualLoads[]={{"LevelMod/SecretChallengeLifeMod"},{"LevelMod/HPDisplay"}};
std::chrono::steady_clock::time_point nextVisualPoll{};
bool enabled=false,finished=false,backgroundOwned=false,textOwned=false;
float life=0,originalOpacity=0,originalGlow=0,hitFlashAt=-1;
bool hitPending=false;
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
 PMDiagnosticsWrite(enabled?"HP prepare: enabled; optional native visuals deferred until chart ready":"HP prepare: disabled");
 if(enabled)levelRoot=r.gchandle_new(level,false);
 // iOS LevelControl.Start waits for EVERY entry in LevelStartInfo.levelMods.
 // Keep that list owned by the game; optional MOD effects must not gate chart loading.
}
P valueCall(Runtime&r,P boxed,const char*method){
 if(!boxed)throw std::runtime_error("HP asset operation missing");
 return r.invokeOn(r.resolve(r.object_get_class(boxed),method),r.object_unbox(boxed));
}
void loadVisuals(Runtime&r,P progress){
 if(!enabled||finished)return;
 if(visualLoads[0].settled&&visualLoads[1].settled)return;
 auto now=std::chrono::steady_clock::now();if(now<nextVisualPoll)return;nextVisualPoll=now+std::chrono::milliseconds(100);
 P level=target(r,levelRoot),info=r.get<P>(progress,"levelInformation");
 if(!r.alive(level)||!info||!r.get<bool>(info,"chartLoaded"))return;
 for(auto&load:visualLoads){
  if(load.settled)continue;
  try{
   if(!load.handle){
    P start=r.get<P>(r.mainGame(),"levelStartInfo"),mods=start?r.get<P>(start,"levelMods"):nullptr;
    P code=r.string_new(load.key);
    if(mods&&r.unbox<bool>(r.call(mods,"Contains",{"System.String"},{code}))){load.settled=true;continue;}
    bool no=false,yes=true;P parent=r.call(level,"get_transform");
    P operation=r.stat(r.type("UnityEngine.AddressableAssets","Addressables"),"InstantiateAsync",{"System.Object","UnityEngine.Transform","System.Boolean","System.Boolean"},{code,parent,&no,&yes});
    if(!operation)throw std::runtime_error("HP InstantiateAsync returned null");
    load.handle=r.gchandle_new(operation,false);
    PMDiagnosticsWrite((std::string("HP visual requested: ")+load.key).c_str());
   }
   P operation=target(r,load.handle);
   if(!r.unbox<bool>(valueCall(r,operation,"get_IsDone")))continue;
   P instance=valueCall(r,operation,"get_Result");load.settled=true;
   if(!r.alive(instance)){
    PMDiagnosticsWrite((std::string("HP visual failed; gameplay continues: ")+load.key).c_str());
   }else PMDiagnosticsWrite((std::string("HP visual loaded: ")+load.key).c_str());
  }catch(const std::exception&e){load.settled=true;PMDiagnosticsWrite((std::string("HP visual error; gameplay continues: ")+load.key+": "+e.what()).c_str());}
 }
}
std::string loadingStatus(Runtime&r){
 std::string out;P level=target(r,levelRoot);
 if(level&&enabled){out="nativeModCount="+std::to_string(r.get<int>(level,"levelModCount"));for(const auto&load:visualLoads)out+=std::string(" ")+load.key+"="+(load.settled?"settled":load.handle?"pending":"deferred");}
 return out;
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
 if(!enabled)return;if(hp!=life)hitPending=true;life=hp;P bar=target(r,barRoot);
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
 if(hitPending){hitPending=false;hitFlashAt=time(r);PMDiagnosticsWrite("HP hit feedback applied outside judgement callback");}
 float elapsed=hitFlashAt<0?1:std::max(0.f,time(r)-hitFlashAt);float intensity=std::clamp(1.f-elapsed/.15f,0.f,1.f);
 Color black{intensity,intensity,intensity,1};int i=0;
 for(const char*name:{"combo","comboText"}){
  P text=r.get<P>(score,name);if(!textOwned)originalText[i]=r.unbox<Color>(r.call(text,"get_color"));
  r.call(text,"set_color",{"UnityEngine.Color"},{&black});++i;
 }
 textOwned=true;
}
void flash(Runtime&r){if(!enabled||finished)return;hitFlashAt=time(r);PMDiagnosticsWrite("HP hit feedback queued (MOD color animation)");}
bool failing(){return failure.started();}
void finish(Runtime&);
// Cache the engine's actual count once per official difficulty and app build.
static NSString *observedCountKey(NSString *identifier,NSString *level){
 static NSString *prefix;
 static dispatch_once_t once;
 dispatch_once(&once,^{
  NSDictionary *info=NSBundle.mainBundle.infoDictionary;
  prefix=[NSString stringWithFormat:@"PhiMod.NoteCount.%@.%@/",info[@"CFBundleShortVersionString"],info[@"CFBundleVersion"]];
 });
 return [NSString stringWithFormat:@"%@%@|%@",prefix,identifier,level];
}
void rememberChartCount(Runtime &r,P level){
 P start=r.get<P>(r.mainGame(),"levelStartInfo");
 if(!start)return;
 NSString *identifier=r.string(r.get<P>(start,"songsId")),*difficulty=r.string(r.get<P>(start,"songsLevel"));
 if(!identifier.length || !difficulty.length || [identifier hasPrefix:@"pm_"])return;
 int count=r.get<int>(r.get<P>(level,"levelInformation"),"numOfNotes");
 if(count<=0)return;
 NSString *key=observedCountKey(identifier,difficulty);
 if([NSUserDefaults.standardUserDefaults integerForKey:key]!=count)
  [NSUserDefaults.standardUserDefaults setInteger:count forKey:key];
}
static int courseNoteCount(Runtime &r,P entry){
 P item=r.get<P>(entry,"songInfo"),song=r.get<P>(item,"songInfo");
 NSString *identifier=r.string(r.get<P>(song,"songsId"));
 NSString *folder=[PMContentStore.shared asset:identifier];
 if(folder){
  auto loadJSON=[&](NSString *file)->NSDictionary*{
   NSData *data=[NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:file] options:NSDataReadingMappedIfSafe error:nil];
   id doc=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
   return [doc isKindOfClass:NSDictionary.class]?doc:nil;
  };
  NSNumber *real=loadJSON(@"conversion.json")[@"realNotes"];
  if([real isKindOfClass:NSNumber.class])return std::max(0,real.intValue);
  // Legacy imports may predate conversion metadata. The native chart excludes fake notes.
  NSDictionary *chart=loadJSON(@"chart-native.json");
  if(chart){int count=0;for(NSDictionary *line in chart[@"judgeLineList"])for(NSString *side in @[@"notesAbove",@"notesBelow"])count += [line[side] count];return count;}
 }
 static NSDictionary *const stock=@{
#include "PMCourseNoteCounts.inc"
 };
 int slot=r.get<int>(entry,"levelIndex");
 if(slot>=0 && slot<4){
  NSString *level=@[@"EZ",@"HD",@"IN",@"AT"][slot];
  NSNumber *observed=[NSUserDefaults.standardUserDefaults objectForKey:observedCountKey(identifier,level)];
  if(observed.intValue>0)return observed.intValue;
  for(NSString *idValue in @[identifier?:@"",r.string(r.get<P>(song,"songsKey"))?:@""]){
   for(NSString *suffix in @[@"",@".0"]){
    NSNumber *value=stock[[NSString stringWithFormat:@"%@%@|%@",idValue,suffix,level]];
    if(value)return value.intValue;
   }
  }
 }
 PMDiagnosticsWrite([[NSString stringWithFormat:@"Missing course note count for %@ slot %d",identifier,slot] UTF8String]);return 0;
}
void finishChallenge(Runtime&r,P progress){
 P gi=r.mainGame(),score=r.get<P>(progress,"scoreControl"),info=r.get<P>(progress,"levelInformation");
 P items=r.get<P>(gi,"challengeSongItems");int index=r.get<int>(gi,"nowChallengeIndex")-1;
 if(index<0 || index>=r.count(items))throw std::runtime_error("HP challenge result index invalid");
 // The native end-of-song accessor also indexes the ghost-note history by
 // difficulty. A partial run only needs the live scoreboard and judgment counts.
 P result=r.object_new(r.klass("LevelResultInfo"));r.call(result,".ctor");
 float points=r.get<float>(score,"_score"),percent=r.get<float>(score,"_percent");
 if(options.noComboScore){
  int total=r.get<int>(info,"numOfNotes");
  if(total>0)points=std::clamp((r.get<int>(score,"perfect")+.65f*r.get<int>(score,"good"))*1000000.f/total,0.f,1000000.f);
 }
 r.call(result,"set_Score",{"System.Single"},{&points});
 r.call(result,"set_Percent",{"System.Single"},{&percent});
 for(const char *field:{"perfect","good","bad","miss","early","late"})r.put(result,field,r.get<int>(score,field));
 r.put(result,"maxCombo",r.get<int>(score,"maxcombo"));
 r.put(gi,"levelResultInfo",result);
 P item=r.at(items,index);r.put(item,"result",result);
 P codes=r.get<P>(score,"_noteCodes");r.put(item,"noteCodes",codes);
 for(int i=index+1,n=r.count(items);i<n;++i){@autoreleasepool{
  P entry=r.at(items,i),empty=r.object_new(r.klass("LevelResultInfo"));
  r.call(empty,".ctor");r.put(entry,"result",empty);
  r.put(empty,"miss",courseNoteCount(r,entry));
  if(codes){P emptyCodes=r.object_new(r.object_get_class(codes));r.call(emptyCodes,".ctor");r.put(entry,"noteCodes",emptyCodes);}
 }}
 // LevelBreak schedules the change on ProgressControl.Update. Match the normal HP exit ordering.
 r.call(progress,"LevelBreak",{"System.String"},{r.string_new("ChallengeModeOver")});
 r.put(info,"levelOver",true);r.put(info,"canPause",false);
 r.call(r.get<P>(progress,"audioSource"),"Stop");finish(r);
 PMDiagnosticsWrite("HP challenge failure: ChallengeModeOver requested");
}
bool failureReady(Runtime&r,P progress){
 if(!failure.started()){
  PMDiagnosticsWrite("HP failureReady: begin freeze/fade");
  P info=r.get<P>(progress,"levelInformation");r.put(info,"canPause",false);r.put(info,"canLevelOver",false);
  r.put(r.get<P>(progress,"judgeControl"),"stopJudge",true);try{r.call(r.get<P>(progress,"scoreControl"),"FreezeScore");}catch(const std::exception&e){PMDiagnosticsWrite(e.what());}
  failure.begin(r.unbox<float>(r.stat(r.type("UnityEngine","Time"),"get_unscaledTime"))); // Only start the delay after critical operations succeed.
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
  bool readyNow=failure.ready(r.unbox<float>(r.stat(r.type("UnityEngine","Time"),"get_unscaledTime")));
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
 for(auto&load:visualLoads){cleanup("release optional visual",[&]{P operation=target(r,load.handle);if(operation)r.stat(r.type("UnityEngine.AddressableAssets","Addressables"),"ReleaseInstance",{"UnityEngine.ResourceManagement.AsyncOperations.AsyncOperationHandle<UnityEngine.GameObject>"},{r.object_unbox(operation)});});release(r,load.handle);load.settled=false;}
 nextVisualPoll={};
 cleanup("restore background",[&]{if(backgroundOwned){P c=r.klass("HPDisplayControl");
  r.stat(c,"set_MainColor",{"UnityEngine.Color"},{&originalMain});r.stat(c,"set_CoverColor",{"UnityEngine.Color"},{&originalCover});
  r.stat(c,"set_Opacity",{"System.Single"},{&originalOpacity});r.stat(c,"set_GlowOpacity",{"System.Single"},{&originalGlow});}});
 cleanup("restore text",[&]{P score=target(r,scoreRoot);if(textOwned&&r.alive(score)){int i=0;for(const char*name:{"combo","comboText"}){P text=r.get<P>(score,name);if(r.alive(text))r.call(text,"set_color",{"UnityEngine.Color"},{&originalText[i]});++i;}}});
 for(uint32_t*p:{&levelRoot,&barRoot,&modRoot,&flashRoot,&scoreRoot})release(r,*p);
 enabled=finished=backgroundOwned=textOwned=false;failure.reset();life=0;hitFlashAt=-1;hitPending=false;
}
void validate(Runtime&r){
 P addressables=r.type("UnityEngine.AddressableAssets","Addressables");
 r.resolve(addressables,"InstantiateAsync",{"System.Object","UnityEngine.Transform","System.Boolean","System.Boolean"},true);
 r.resolve(addressables,"ReleaseInstance",{"UnityEngine.ResourceManagement.AsyncOperations.AsyncOperationHandle<UnityEngine.GameObject>"},true);
 P bar=r.type(ns,"SecretChallengeLifeBar"),mod=r.type(ns,"SecretChallengeLifeMod");
 r.resolve(r.type("UnityEngine","Mathf"),"SmoothDamp",{"System.Single","System.Single","System.Single&","System.Single","System.Single","System.Single"},true);
 r.resolve(bar,"ConfigureCanvas");r.resolve(bar,"ApplyShaderParameters");
 r.resolve(mod,"AudioFadeOut",{"AddressableAudioSource","System.Single"});r.resolve(mod,"EnableTrueShadow",{"UnityEngine.Component"},true);
 for(const char*name:{"get_MainColor","get_CoverColor","get_Opacity","get_GlowOpacity"})r.resolve(r.klass("HPDisplayControl"),name,{},true);
}
}
