#include "PMPracticePreview.hpp"
#include <algorithm>
#include <cmath>
#include <map>
#include <set>
#include <vector>
namespace pmpracticepreview {
using pmbridge::Runtime;using pmbridge::P;
namespace {
struct Original {P note;float time,duration,floor;int type;};
struct Candidate {P note;int index;bool above;float time,duration,floor;};
struct Line {P owner;int index;std::vector<Candidate> floors,holds;float longestHold=0;};
std::vector<Original> originals;std::vector<Line> tracks;std::map<P,P> controls;
P owner=nullptr;bool inCreate=false,dirty=true,previewOwned=false;float lastCursor=-1e9f;
int count(Runtime&r,P list,int max){int n=r.count(list);if(n<0||n>max)throw std::runtime_error("Practice preview collection outside limit");return n;}
const char*listFor(int type){return type==1?"clickControls":type==2?"dragControls":type==3?"holdControls":"flickControls";}
void capture(Runtime&r,P judge){
 if(owner==judge)return;clear();owner=judge;
 P notes=r.get<P>(judge,"chartNoteSortByTime");int n=count(r,notes,200000);
 for(int i=0;i<n;++i){P note=r.at(notes,i);originals.push_back({note,r.get<float>(note,"realTime"),r.get<float>(note,"holdTime"),r.get<float>(note,"floorPosition"),r.get<int>(note,"type")});}
 P lines=r.get<P>(judge,"judgeLineControls");int total=count(r,lines,2048);
 for(int i=0;i<total;++i){P line=r.at(lines,i);Line track{line,r.get<int>(line,"index")};
  for(bool above:{true,false}){P side=r.get<P>(line,above?"notesAbove":"notesBelow");int len=count(r,side,200000);for(int j=0;j<len;++j){P note=r.at(side,j);float duration=r.get<int>(note,"type")==3?r.get<float>(note,"holdTime"):0;
   Candidate candidate{note,j,above,r.get<float>(note,"realTime"),duration,r.get<float>(note,"floorPosition")};track.floors.push_back(candidate);if(duration>0){track.holds.push_back(candidate);track.longestHold=std::max(track.longestHold,duration);}}}
  std::sort(track.floors.begin(),track.floors.end(),[](auto&a,auto&b){return a.floor<b.floor;});std::sort(track.holds.begin(),track.holds.end(),[](auto&a,auto&b){return a.time<b.time;});tracks.push_back(std::move(track));
 }
}
void showRenderer(Runtime&r,P control,const char*field,bool visible){P renderer=r.get<P>(control,field);if(!r.alive(renderer))return;r.call(renderer,"set_enabled",{"System.Boolean"},{&visible});}
}
bool creating(){return inCreate;}
void discardControls(){controls.clear();dirty=true;lastCursor=-1e9f;previewOwned=false;}
void clear(){previewOwned=false;originals.clear();tracks.clear();controls.clear();owner=nullptr;inCreate=false;dirty=true;lastCursor=-1e9f;}
int reset(Runtime&r,P progress,float current){
 P judge=r.get<P>(progress,"judgeControl");capture(r,judge);controls.clear();dirty=true;lastCursor=-1e9f;int skippedCount=0;
 // Restore chart source before every rewind: trimming a crossing Hold must
 // never accumulate across repeats or corrupt a later seek to an earlier time.
 for(const auto&n:originals){r.put(n.note,"realTime",n.time);r.put(n.note,"holdTime",n.duration);r.put(n.note,"floorPosition",n.floor);
  // Match Android's boundary tolerance: a note within 0.1 ms of the cursor
  // belongs to the active segment; a Hold crossing the cursor is carried in.
  bool skipped=n.time<current-.0001f;
  if(skipped&&n.type==3&&n.time+n.duration>current+.0001f){
   int lineIndex=r.get<int>(n.note,"judgeLineIndex")/2;float floor=n.floor;
   for(const auto&line:tracks)if(line.index==lineIndex){P events=r.get<P>(line.owner,"speedEvents");for(int i=0,total=count(r,events,200000);i<total;++i){P e=r.at(events,i);float begin=r.get<float>(e,"startTime"),end=r.get<float>(e,"endTime");if(current>=begin&&current<=end){floor=r.get<float>(e,"floorPosition")+(current-begin)*r.get<float>(e,"value");break;}}break;}
   r.put(n.note,"realTime",current);r.put(n.note,"holdTime",n.time+n.duration-current);r.put(n.note,"floorPosition",floor);skipped=false;
  }
  if(skipped)++skippedCount;
  r.put(n.note,"isJudged",skipped);r.put(n.note,"isJudgedForFlick",skipped);
 }
 return skippedCount;
}
void render(Runtime&r,P manager,float current,bool countdown,float targetTime){
 P info=r.get<P>(manager,"levelInformation");if(!r.get<bool>(info,"chartLoaded"))return;
 P judge=r.get<P>(manager,"judgeControl");capture(r,judge);r.put(judge,"nowTime",current);
 if(!previewOwned){for(const char*name:{"clickControls","dragControls","holdControls","flickControls"}){P list=r.get<P>(manager,name);for(int i=0,n=count(r,list,100000);i<n;++i){P control=r.at(list,i);if(r.alive(control))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{r.call(control,"get_gameObject")});}r.call(list,"Clear");}controls.clear();dirty=true;previewOwned=true;}
 if(std::fabs(current-lastCursor)>.0001f){dirty=true;lastCursor=current;}
 if(!dirty&&!countdown)return;
 for(auto&line:tracks)r.call(line.owner,"UpdateInfo"); // CreateNote is gated by the preview hook.
 if(dirty){
  std::map<P,std::pair<Line*,Candidate>> wanted;P floors=r.get<P>(info,"floorPositions");float speed=std::max(.001f,std::fabs(r.staticValue<float>(r.klass("LevelInformation"),"Speed","System.Single"))),radius=30.f/speed;
  for(auto&line:tracks){float floor=floors&&line.index>=0&&uintptr_t(line.index)<r.array_length(floors)?r.unbox<float>(r.arrayAt(floors,line.index)):0;
   auto keep=[&](const Candidate&n){if(current<=n.time+n.duration+.001f)wanted[n.note]={&line,n};};
   auto first=std::lower_bound(line.floors.begin(),line.floors.end(),floor-radius,[](const Candidate&n,float f){return n.floor<f;});for(auto it=first;it!=line.floors.end()&&it->floor<=floor+radius;++it)keep(*it);
   auto hold=std::lower_bound(line.holds.begin(),line.holds.end(),current-line.longestHold,[](const Candidate&n,float t){return n.time<t;});for(;hold!=line.holds.end()&&hold->time<=current;++hold)if(hold->time+hold->duration>=current)keep(*hold);
  }
  for(auto it=controls.begin();it!=controls.end();){if(!wanted.count(it->first)){P control=it->second;P list=r.get<P>(manager,listFor(r.get<int>(it->first,"type")));r.call(list,"Remove",{r.get<int>(it->first,"type")==1?"ClickControl":r.get<int>(it->first,"type")==2?"DragControl":r.get<int>(it->first,"type")==3?"HoldControl":"FlickControl"},{control});if(r.alive(control))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{r.call(control,"get_gameObject")});it=controls.erase(it);}else ++it;}
  for(const auto&entry:wanted)if(!controls.count(entry.first)){
   const auto&n=entry.second.second;P list=r.get<P>(manager,listFor(r.get<int>(n.note,"type")));int before=r.count(list);bool above=n.above;int index=n.index;
   inCreate=true;try{r.call(entry.second.first->owner,"CreateNote",{"System.Int32","System.Boolean"},{&index,&above});}catch(...){inCreate=false;throw;}inCreate=false;
   if(r.count(list)>before){P control=r.at(list,before);bool disabled=false;r.call(control,"set_enabled",{"System.Boolean"},{&disabled});r.call(control,"Start");controls[n.note]=control;}
  }
  dirty=false;
 }
 for(const auto&entry:controls){P note=entry.first,control=entry.second;if(!r.alive(control))continue;bool hold=r.get<int>(note,"type")==3;
  bool beforeTarget=countdown&&r.get<float>(note,"realTime")<targetTime-.0001f;
  if(beforeTarget){
   // Android marks pre-start ChartNotes as Miss before the count-in. The
   // isJudgedForFlick flag belongs to ChartNote, not Click/Drag/Hold/Flick
   // controllers; writing it to a controller throws and aborts this render
   // pass, leaving old notes visible and their NoteMove effects running.
   // Never call NoteMove for notes before the countdown target.
   r.put(note,"isJudged",true);r.put(note,"isJudgedForFlick",true);
   r.put(control,"isVisible",false);r.put(control,"isJudged",true);
   if(hold){
    for(const char*field:{"missed","judged","judgeOver"})r.put(control,field,true);
    r.put(control,"timeOfJudge",0.f);
    showRenderer(r,control,"_holdHeadSpriteRenderer",false);
    showRenderer(r,control,"_holdSpriteRenderer",false);
    showRenderer(r,control,"_holdEndSpriteRenderer1",false);
   }else showRenderer(r,control,"_spriteRenderer",false);
   continue;
  }
  r.put(control,"isVisible",true);r.put(control,"isJudged",false);bool visible=!countdown||r.get<float>(note,"realTime")>=targetTime-.0001f;
  if(hold){for(const char*field:{"missed","judged","judgeOver","_holdHeadIsDestroyed"})r.put(control,field,false);bool crosses=r.get<float>(note,"realTime")+r.get<float>(note,"holdTime")>targetTime;
   showRenderer(r,control,"_holdHeadSpriteRenderer",visible);showRenderer(r,control,"_holdSpriteRenderer",visible||crosses);showRenderer(r,control,"_holdEndSpriteRenderer1",visible||crosses);
  }else showRenderer(r,control,"_spriteRenderer",visible);
  r.call(control,"NoteMove");
 }
}
void validate(Runtime&r){
 r.resolve(r.klass("JudgeLineControl"),"CreateNote",{"System.Int32","System.Boolean"});r.resolve(r.klass("JudgeLineControl"),"UpdateInfo");
 for(const char*name:{"ClickControl","DragControl","HoldControl","FlickControl"}){r.resolve(r.klass(name),"Start");r.resolve(r.klass(name),"NoteMove");}
 for(const char*name:{"endTime","floorPosition"})r.field(r.klass("SpeedEvent"),name,"System.Single",false);
 r.field(r.klass("ChartNote"),"judgeLineIndex","System.Int32",false);
}
}
