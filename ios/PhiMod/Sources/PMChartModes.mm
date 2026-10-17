#include "PMChartModes.hpp"
#include <limits>
#include <exception>
namespace pmmodes {
namespace {
struct V3{float x,y,z;};struct Color{float r,g,b,a;};
struct NoteBackup{P note=nullptr;int type=0;float speed=0,hold=0;};
phimod::Options options;
phimod::NoiseHoles holes;
phimod::HoldGrace holdGrace;
phimod::HoldFxClock fxClock;
uint32_t levelRoot=0,originalRoot=0,originalBlocksRoot=0,fullRoot=0,materialRoot=0;
std::vector<NoteBackup> noteBackups;
std::vector<phimod::Rect> cachedMasks;
std::uint64_t cachedGeometryRevision=~std::uint64_t(0);
float cachedWidth=0,cachedHeight=0;
bool cachedGeometry=false;
Color originalFill{},originalEdge{};float originalFloats[3]{};
constexpr const char*properties[]={"_FillStrength","_FillOpacity","_DisplaceBlendIntensity"};
P target(Runtime&r,uint32_t root){return root?r.gchandle_get_target(root):nullptr;}
void release(Runtime&r,uint32_t&root){if(root){r.gchandle_free(root);root=0;}}
int boundedCount(Runtime&r,P list,int limit=200000){int n=r.count(list);if(n<0||n>limit)throw std::runtime_error("Chart list count exceeds limit");return n;}
void overwrite(Runtime&r,P chart,const std::string&json){
 P text=r.string_new(json.c_str());uint32_t root=r.gchandle_new(text,false);
 try{r.stat(r.type("UnityEngine","JsonUtility"),"FromJsonOverwrite",{"System.String","System.Object"},{text,chart});}
 catch(...){r.gchandle_free(root);throw;}r.gchandle_free(root);
}
void captureChart(Runtime&r,P level){
 if(originalRoot)return;
 P original=r.get<P>(level,"chart");if(!original)throw std::runtime_error("Chart not loaded");
 originalRoot=r.gchandle_new(original,false);
 P blocks=r.get<P>(original,"blockAreaList");
 if(blocks)originalBlocksRoot=r.gchandle_new(blocks,false);
}
void restoreMaterial(Runtime&r){
 P mat=target(r,materialRoot);
 if(r.alive(mat)){
  r.call(mat,"SetColor",{"System.String","UnityEngine.Color"},{r.string_new("_FillColor"),&originalFill});
  r.call(mat,"SetColor",{"System.String","UnityEngine.Color"},{r.string_new("_EdgeColor"),&originalEdge});
  for(int i=0;i<3;++i)r.call(mat,"SetFloat",{"System.String","System.Single"},{r.string_new(properties[i]),&originalFloats[i]});
 }
}
void tint(Runtime&r,P render){
 P mat=r.get<P>(render,"activeBlockMaterial");if(!r.alive(mat)||mat==target(r,materialRoot))return;
 restoreMaterial(r);release(r,materialRoot);
 // Snapshot every property BEFORE any mutation; rollback can then be complete.
 originalFill=r.unbox<Color>(r.call(mat,"GetColor",{"System.String"},{r.string_new("_FillColor")}));
 originalEdge=r.unbox<Color>(r.call(mat,"GetColor",{"System.String"},{r.string_new("_EdgeColor")}));
 for(int i=0;i<3;++i)originalFloats[i]=r.unbox<float>(r.call(mat,"GetFloat",{"System.String"},{r.string_new(properties[i])}));
 materialRoot=r.gchandle_new(mat,false);
 Color fill{.22f,.008f,.016f,1},edge{.95f,.16f,.2f,1};float values[]={.12f,.94f,.08f};
 r.call(mat,"SetColor",{"System.String","UnityEngine.Color"},{r.string_new("_FillColor"),&fill});
 r.call(mat,"SetColor",{"System.String","UnityEngine.Color"},{r.string_new("_EdgeColor"),&edge});
 for(int i=0;i<3;++i)r.call(mat,"SetFloat",{"System.String","System.Single"},{r.string_new(properties[i]),&values[i]});
}
}
void prepare(Runtime&r,P level,const phimod::Options&o){clear(r);options=o;levelRoot=r.gchandle_new(level,false);}
void clear(Runtime&r){
 try{restoreMaterial(r);}catch(const std::exception&e){NSLog(@"[PhiMod] Noise material cleanup: %s",e.what());}
 try{
  // ChartNote and Chart are managed serializable objects, not UnityEngine.Object
  // instances; Runtime::alive is only valid for UnityEngine.Object-derived values.
  for(const auto& backup:noteBackups)if(backup.note){
   r.put(backup.note,"type",backup.type);r.put(backup.note,"speed",backup.speed);r.put(backup.note,"holdTime",backup.hold);
  }
  P chart=target(r,originalRoot),blocks=target(r,originalBlocksRoot);
  if(chart&&blocks)r.put(chart,"blockAreaList",blocks);
 }catch(const std::exception&e){NSLog(@"[PhiMod] Practice chart cleanup: %s",e.what());}
 for(auto root:{&levelRoot,&originalRoot,&originalBlocksRoot,&fullRoot,&materialRoot})release(r,*root);
 noteBackups.clear();cachedMasks.clear();cachedGeometryRevision=~std::uint64_t(0);cachedWidth=cachedHeight=0;cachedGeometry=false;
 options=phimod::Options{};holes.clear();holdGrace.clear();fxClock.clear();
}
void beforeCodes(Runtime&r,P self){
 if(self!=target(r,levelRoot)||(!options.noise&&!options.unified&&!options.clearNoise))return;
 captureChart(r,self);if(!options.unified)return;
 P lines=r.get<P>(target(r,originalRoot),"judgeLineList");int n=boundedCount(r,lines,2048);
 for(int i=0;i<n;++i){P line=r.at(lines,i),events=r.get<P>(line,"speedEvents");float bpm=r.get<float>(line,"bpm");int ne=boundedCount(r,events);
  for(const char*side:{"notesAbove","notesBelow"}){P notes=r.get<P>(line,side);int nn=boundedCount(r,notes);
   for(int j=0;j<nn;++j){P note=r.at(notes,j);int old=r.get<int>(note,"type");if(old==options.unified)continue;
    noteBackups.push_back({note,old,r.get<float>(note,"speed"),r.get<float>(note,"holdTime")});
    float tick=float(r.get<int>(note,"time")),speed=1;
    for(int k=0;k<ne;++k){P event=r.at(events,k);if(tick>=r.get<float>(event,"startTime"))speed=r.get<float>(event,"value");else break;}
    auto converted=phimod::unifiedNote(old,options.unified,r.get<float>(note,"speed"),r.get<float>(note,"holdTime"),speed,bpm);
    r.put(note,"speed",converted.speed);r.put(note,"holdTime",converted.holdTicks);r.put(note,"type",converted.type);
   }
  }
 }
}
void afterInformation(Runtime&r,P self){
 if(self!=target(r,levelRoot)||!originalRoot)return;
 P chart=target(r,originalRoot);
 // Match Android SetInformation: No Noise removes the chart's original
 // blocking areas after the game has finished deriving chart information.
 // Noise takes precedence when both switches are enabled.
 if(options.clearNoise&&!options.noise){
  overwrite(r,chart,"{\"blockAreaList\":[]}");
  if(boundedCount(r,r.get<P>(chart,"blockAreaList"))!=0)throw std::runtime_error("Original noise removal incomplete");
  return;
 }
 if(!options.noise)return;
 std::string json="{\"blockAreaList\":[";
 for(int i=0;i<=256;++i){if(i)json+=',';
  json+="{\"topRightPercentage\":{\"x\":"+std::string(i?"-9":"1.5")+",\"y\":"+std::string(i?"-9":"1.5")+"},\"bottomLeftPercentage\":{\"x\":"+std::string(i?"-10":"-0.5")+",\"y\":"+std::string(i?"-10":"-0.5")+"},\"appearTime\":-100,\"enableTime\":-100,\"disableTime\":1000000,\"disappearTime\":1000001,\"isSubtract\":"+(i?"true":"false")+",\"rotateEvents\":[],\"moveEvents\":[],\"scaleEvents\":[]}";
 }json+="]}";overwrite(r,chart,json);
 if(boundedCount(r,r.get<P>(chart,"blockAreaList"),257)!=257)throw std::runtime_error("Noise block allocation incomplete");
}
void beginFrame(Runtime&r,P manager){
 if(options.noise&&levelRoot)holes.begin(r.get<float>(r.get<P>(manager,"progressControl"),"nowTime"));
}
void moved(Runtime&r,P control,bool hold){
 if(!options.noise||!levelRoot||!r.get<bool>(control,"isVisible"))return;
 P note=r.get<P>(control,"noteInfor");V3 pos=r.unbox<V3>(r.call(r.call(control,"get_transform"),"get_position"));
 holes.visible(r.get<float>(note,"noteCode"),{pos.x,pos.y,2*options.radius,2*options.radius},hold,options.holdGraceMs/1000.f);
}
void frame(Runtime&r,P manager){
 if(!options.noise||!levelRoot)return;
 (void)manager;holes.end();P level=target(r,levelRoot);
 P preview=r.get<P>(level,"previewElementUpdateControl"),blocks=r.get<P>(preview,"previewBlocks");int count=boundedCount(r,blocks,257);
 if(!count)return; // Preview assets have not been instantiated yet.
 if(count!=257)throw std::runtime_error("Noise preview block count mismatch");
 P first=r.at(blocks,0);if(first!=target(r,fullRoot)){release(r,fullRoot);fullRoot=r.gchandle_new(first,false);}
 float width=r.get<float>(preview,"screenWidth"),height=r.get<float>(preview,"screenHeight");
 bool geometryChanged=!cachedGeometry||cachedGeometryRevision!=holes.geometryRevision()||cachedWidth!=width||cachedHeight!=height;
 if(geometryChanged){cachedMasks=holes.masks(width,height);cachedGeometryRevision=holes.geometryRevision();cachedWidth=width;cachedHeight=height;cachedGeometry=true;}
 const auto&masks=cachedMasks;
 // Never allow more touches than are actually represented by subtract blocks.
 // Refuse pathological geometry instead of silently truncating holes.
 if(masks.size()>256)throw std::runtime_error("Noise union exceeds 256 native masks");
 if(geometryChanged)for(int i=1;i<count;++i){P block=r.at(blocks,i),info=r.get<P>(block,"blockInfo");Point low{-10,-10},high{-9,-9};
  if(size_t(i-1)<masks.size()){auto m=masks[size_t(i-1)];low={m.left/width+.5f,m.bottom/height+.5f};high={m.right/width+.5f,m.top/height+.5f};}
  Point oldLow=r.get<Point>(info,"bottomLeftPercentage"),oldHigh=r.get<Point>(info,"topRightPercentage");
  if(oldLow.x!=low.x||oldLow.y!=low.y||oldHigh.x!=high.x||oldHigh.y!=high.y){r.put(info,"bottomLeftPercentage",low);r.put(info,"topRightPercentage",high);r.call(block,"UpdateBlocksTransform");}
 }
  P render=r.get<P>(preview,"<BlockRender>k__BackingField");if(options.noiseVisual&&r.alive(render))tint(r,render);
}
void late(Runtime&r,P render){
 (void)r;
 (void)render;
}
bool blocking(Runtime&r,Point point,P*out,bool&handled){
 if(options.clearNoise&&!options.noise){handled=true;if(out)*out=nullptr;return false;}
 handled=options.noise&&fullRoot; if(!handled)return false;
 bool blocked=!holes.allows(point.x,point.y);if(out)*out=blocked?target(r,fullRoot):nullptr;return blocked;
}
void completed(Runtime&r,P self){
 P note=r.get<P>(self,"noteInfor");float code=r.get<float>(note,"noteCode");
 if(options.noise){float now=r.get<float>(r.get<P>(self,"progressControl"),"nowTime");holes.completed(code,now,options.noiseGraceMs/1000.f);}
 holdGrace.retire(code);fxClock.retire(code);
}
void holdMove(Runtime&r,P self){
 if(!options.autoplay||!levelRoot||!r.get<bool>(self,"judged"))return;
 P note=r.get<P>(self,"noteInfor");float now=r.get<float>(r.get<P>(self,"progressControl"),"nowTime");
 r.put(self,"missed",false);bool pulse=fxClock.pulse(r.get<float>(note,"noteCode"),now,r.get<float>(note,"realTime"),options.holdFxMs/1000.f);
 r.put(self,"timeOfJudge",pulse?1000000.f:0.f);
}
void HoldScope::restore(){
 // Restore independently: a failed array restore must not leave numOfFingers=1.
 std::exception_ptr error;
 try{if(arrayChanged_){r_.arrayPutFloat(array_,0,first_);arrayChanged_=false;}}catch(...){error=std::current_exception();}
 try{if(countChanged_){r_.put(line_,"numOfFingers",count_);countChanged_=false;}}catch(...){if(!error)error=std::current_exception();}
 if(error)std::rethrow_exception(error);
}
HoldScope::HoldScope(Runtime&r,P self):r_(r){
 if(!options.noise||options.autoplay||options.holdGraceMs<=0||!levelRoot)return;
 try{
  P note=r.get<P>(self,"noteInfor");line_=r.get<P>(self,"judgeLine");array_=r.get<P>(line_,"fingerPositionX");count_=r.get<int>(line_,"numOfFingers");
  if(count_<0||count_>1024||!array_||r.array_length(array_)>1024)throw std::runtime_error("Invalid Hold finger buffer");
  auto capacity=r.array_length(array_);std::vector<float> fingers;
  for(int i=0;i<count_&&uintptr_t(i)<capacity;++i)fingers.push_back(r.unbox<float>(r.arrayAt(array_,i)));
  // HoldGrace uses the vector's non-emptiness as writable-slot availability.
  if(fingers.empty()&&capacity)fingers.push_back(std::numeric_limits<float>::quiet_NaN());
  float now=r.get<float>(r.get<P>(self,"progressControl"),"nowTime"),code=r.get<float>(note,"noteCode"),x=r.get<float>(note,"positionX");
  bool inject=holdGrace.inject(code,now,x,fingers,options.holdGraceMs/1000.f,options.fullscreen);
  if(inject&&r.get<bool>(self,"judged")&&capacity){
   first_=r.unbox<float>(r.arrayAt(array_,0));arrayChanged_=true;r.arrayPutFloat(array_,0,x);
   countChanged_=true;r.put(line_,"numOfFingers",1);
  }
 }catch(...){try{restore();}catch(const std::exception&e){NSLog(@"[PhiMod] Hold rollback: %s",e.what());}throw;}
}
HoldScope::~HoldScope()noexcept{try{restore();}catch(const std::exception&e){NSLog(@"[PhiMod] Hold rollback: %s",e.what());}}
void validate(Runtime&r){
 P json=r.type("UnityEngine","JsonUtility");r.resolve(json,"FromJsonOverwrite",{"System.String","System.Object"},true);
 r.resolve(r.type("System","Array"),"SetValue",{"System.Object","System.Int32"});
  r.resolve(r.type("ProjectEditor.PreviewScripts","PreviewBlockControl"),"UpdateBlocksTransform");
 for(auto field:{"judgeLineList","blockAreaList"})r.field(r.klass("Chart"),field,field==std::string("judgeLineList")?"System.Collections.Generic.List<JudgeLine>":"System.Collections.Generic.List<GameInformation.BlockArea>",false);
 r.field(r.klass("LevelControl"),"chart","Chart",false);r.field(r.klass("LevelControl"),"previewElementUpdateControl","Phigros2.Level.Scripts.PreviewElementUpdateControl",false);
 for(auto c:{"ClickControl","DragControl","HoldControl","FlickControl"}){r.field(r.klass(c),"noteInfor","ChartNote",false);r.field(r.klass(c),"isVisible","System.Boolean",false);}
 r.field(r.type("Phigros2.Level.Scripts","PreviewElementUpdateControl"),"previewBlocks","System.Collections.Generic.List<ProjectEditor.PreviewScripts.PreviewBlockControl>",false);
 r.field(r.type("Phigros2.Level.Scripts","PreviewElementUpdateControl"),"<BlockRender>k__BackingField","BlockRender",false);
 r.field(r.type("Phigros2.Level.Scripts","PreviewElementUpdateControl"),"screenWidth","System.Single",false);r.field(r.type("Phigros2.Level.Scripts","PreviewElementUpdateControl"),"screenHeight","System.Single",false);
 r.field(r.type("ProjectEditor.PreviewScripts","PreviewBlockControl"),"blockInfo","GameInformation.BlockArea",false);
 P area=r.nested(r.klass("GameInformation"),"BlockArea");r.field(area,"bottomLeftPercentage","UnityEngine.Vector2",false);r.field(area,"topRightPercentage","UnityEngine.Vector2",false);
 r.field(r.klass("BlockRender"),"activeBlockMaterial","UnityEngine.Material",false);
 for(auto name:{"clickControls","dragControls","holdControls","flickControls"}){std::string t="System.Collections.Generic.List<";t+=!strcmp(name,"clickControls")?"ClickControl":!strcmp(name,"dragControls")?"DragControl":!strcmp(name,"holdControls")?"HoldControl":"FlickControl";t+='>';r.field(r.klass("NoteUpdateManager"),name,t.c_str(),false);}
 r.field(r.klass("JudgeLineControl"),"numOfFingers","System.Int32",false);r.field(r.klass("JudgeLineControl"),"fingerPositionX","System.Single[]",false);
 for(auto name:{"type","time"})r.field(r.klass("ChartNote"),name,"System.Int32",false);
 for(auto name:{"speed","holdTime","positionX","realTime","noteCode"})r.field(r.klass("ChartNote"),name,"System.Single",false);
 r.field(r.klass("JudgeLine"),"bpm","System.Single",false);r.field(r.klass("JudgeLine"),"speedEvents","System.Collections.Generic.List<SpeedEvent>",false);
 for(auto name:{"notesAbove","notesBelow"})r.field(r.klass("JudgeLine"),name,"System.Collections.Generic.List<ChartNote>",false);
 for(auto name:{"startTime","value"})r.field(r.klass("SpeedEvent"),name,"System.Single",false);
}
}
