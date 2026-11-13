#include "PMUnlockRuntime.hpp"
#include "../Core/PMUIInteraction.hpp"
#import "PMContentStore.h"
#import "PMUnlockRules.h"
#import "PMUnlockProgress.h"
#import "PMUnlockMedia.h"
#include "PMContentRuntime.hpp"
#import "PMSettings.h"
#import "PMDiagnostics.h"
#import <UIKit/UIKit.h>
#include <algorithm>
#include <cstdarg>
#include <cstdio>
#include <cmath>
#include <map>
#include <set>
#include <string>
#include <vector>
#include <chrono>
namespace pmunlock {
using pmbridge::P;using pmbridge::Runtime;

namespace { PMUnlockProgress*progress=nil; Runtime*runtime=nullptr; NSMutableSet*newlyOpened=nil; NSMutableArray*pending=nil; NSTimer*menuTimer=nil; bool menuActive=false; double lastScan=0;
uint32_t resultOwner=0;void(^resultResume)(BOOL)=nil;
bool mediaAudioOwned=false,previousAudioPause=false;float previousAudioVolume=1;
void restoreMediaAudio(){if(!mediaAudioOwned||!runtime)return;mediaAudioOwned=false;auto&r=*runtime;P listener=r.type("UnityEngine","AudioListener");r.stat(listener,"set_pause",{"System.Boolean"},{&previousAudioPause});r.stat(listener,"set_volume",{"System.Single"},{&previousAudioVolume});}
BOOL presentMedia(NSString*path,NSString*cover,NSString*title,void(^done)(BOOL)){
 if(!runtime||PMUnlockMediaBusy())return NO;
 auto&r=*runtime;P listener=r.type("UnityEngine","AudioListener");
 bool wasOwned=mediaAudioOwned;if(!wasOwned){previousAudioPause=r.unbox<bool>(r.stat(listener,"get_pause"));previousAudioVolume=r.unbox<float>(r.stat(listener,"get_volume"));mediaAudioOwned=true;}
 bool paused=true;float muted=0;r.stat(listener,"set_pause",{"System.Boolean"},{&paused});r.stat(listener,"set_volume",{"System.Single"},{&muted});
 BOOL shown=PMPresentUnlockMedia(path,cover,title,^(BOOL completed){@try{if(done)done(completed);}@finally{if(!completed||!pending.count||(!menuActive&&!resultResume))restoreMediaAudio();}});
 if(!shown&&!wasOwned)restoreMediaAudio();return shown;
}
void logf(const char*fmt,...){char b[768];va_list a;va_start(a,fmt);vsnprintf(b,sizeof(b),fmt,a);va_end(a);PMDiagnosticsWrite(b);}
P target(Runtime&r,uint32_t h){return h?r.gchandle_get_target(h):nullptr;}
NSString*slotName(int slot){return @[@"EZ",@"HD",@"IN",@"AT"][std::clamp(slot,0,3)];}
// snapshot() serializes the entire library. Reuse it for read-only unlock
// queries until an import/edit commits a new revision.
NSDictionary*unlockLibrary(){static NSDictionary*db=nil;static NSUInteger revision=NSUIntegerMax;NSUInteger current=PMContentStore.shared.revision;if(!db||revision!=current){db=[PMContentStore.shared snapshot];revision=current;}return db;}
NSDictionary*entity(NSString*id){NSDictionary*db=unlockLibrary();for(NSDictionary*s in db[@"songs"])if([s[@"id"] isEqualToString:id])return s;for(NSDictionary*c in db[@"chapters"])if([c[@"id"] isEqualToString:id])return c;return nil;}
NSDictionary*songEntity(NSString*id,int slot){NSDictionary*db=unlockLibrary();NSString*selected=db[@"chartSelections"][[NSString stringWithFormat:@"%@@%d",id,slot]];NSDictionary*fallback=nil;for(NSDictionary*s in db[@"songs"]){if(![s[@"id"] isEqualToString:id]&&![s[@"groupId"] isEqualToString:id])continue;if(![[s[@"level"] uppercaseString] isEqualToString:slotName(slot)])continue;if([s[@"id"] isEqualToString:selected])return s;if(!fallback)fallback=s;}return fallback;}
NSDictionary*ruleFor(NSString*id){return PMNormalizeUnlockRule(entity(id)[@"unlock"]);}
P record(Runtime&r,NSString*id,int slot){try{return r.call(r.mainGame(),"GetSongRecord",{"System.String","System.String"},{r.managedString(id),r.managedString(slotName(slot))});}catch(...){return nullptr;}}
double rksValue(Runtime&r){try{P gi=r.mainGame();P boxed=r.call(gi,"get_RankingScore");return r.unbox<float>(boxed);}catch(...){return -1;}}
bool recordPass(Runtime&r,NSDictionary*c){
 NSString*type=c[@"type"],*ref=c[@"ref"];
 int slot=c[@"slot"]?[c[@"slot"] intValue]:-1;
 if([type isEqualToString:@"rks"]){double value=rksValue(r);return std::isfinite(value)&&value+1e-6>=[c[@"value"] doubleValue];}
 if(!ref.length)return false;
 NSDictionary*db=unlockLibrary();
 if([type isEqualToString:@"chapter"]){
  NSArray*members=entity(ref)[@"songs"];
  if(!members){for(NSDictionary*chapter in pmcontent::cachedOfficialSnapshot()[@"chapters"])if([chapter[@"chapterCode"] isEqualToString:ref]){NSMutableArray*ids=[NSMutableArray new];for(NSDictionary*song in chapter[@"songInfo"][@"songs"])if([song[@"songsId"] isKindOfClass:NSString.class])[ids addObject:song[@"songsId"]];members=ids;break;}}
  if(![members isKindOfClass:NSArray.class]||!members.count)return false;
  for(NSString*sid in members)if(!recordPass(r,@{@"type":@"score",@"ref":sid,@"slot":@(slot),@"value":@700000}))return false;
  return true;
 }
 NSMutableArray*candidates=[PMUnlockReferenceSongs(db[@"songs"],ref) mutableCopy];
 if(!candidates.count)[candidates addObject:@{@"id":ref}];
 double threshold=[c[@"value"] doubleValue];
 for(NSDictionary*song in candidates)for(int s=slot<0?0:slot;s<=(slot<0?3:slot);++s){
  if([song[@"level"] isKindOfClass:NSString.class]&&![[song[@"level"] uppercaseString] isEqualToString:slotName(s)])continue;
  P rec=record(r,song[@"id"],s);if(!rec)continue;
  int score=r.get<int>(rec,"s");if(score<=0)continue;
  if([type isEqualToString:@"score"]&&score>=threshold)return true;
  if([type isEqualToString:@"acc"]){float acc=r.get<float>(rec,"a");if(std::isfinite(acc)&&acc+1e-6>=threshold)return true;}
  if([type isEqualToString:@"fc"]&&(r.get<int>(rec,"c")==1||score==1000000))return true;
  if([type isEqualToString:@"phi"]&&score==1000000)return true;
 }
 return false;
}
bool passes(Runtime&r,NSDictionary*rule){
 if(PMUnlockValidationError(rule))return false;
 if(![rule[@"enabled"] boolValue])return true;
 BOOL any=[rule[@"mode"] isEqualToString:@"any"];
 for(NSDictionary*c in rule[@"conditions"]){bool pass=recordPass(r,c);if(any&&pass)return true;if(!any&&!pass)return false;}
 return !any;
}
bool opened(Runtime&r,NSString*id){
 NSDictionary*rule=ruleFor(id);if(PMUnlockValidationError(rule))return false;
 if(![rule[@"enabled"] boolValue])return true;
 if(!progress)progress=[[PMUnlockProgress alloc]initWithRoot:PMContentStore.shared.root];
 if([progress isOpen:id rule:rule])return true;
 if(!passes(r,rule))return false;
 NSError*error=nil;if(![progress open:id rule:rule error:&error]){logf("Unlock progress save failed: %s",error.localizedDescription.UTF8String);return false;}if(!newlyOpened)newlyOpened=[NSMutableSet new];[newlyOpened addObject:id];
 return true;
}
// A chapter requirement applies to its members in every aggregate selector.
bool chapterBlocked(Runtime&r,NSString*group,NSDictionary*subject){
 NSString*chapter=subject[@"targetChapter"];
 if(chapter.length&&entity(chapter)&&!opened(r,chapter))return true;
 for(NSDictionary*c in unlockLibrary()[@"chapters"]){
  if(![c[@"unlock"][@"enabled"]boolValue])continue;
  NSArray*members=c[@"songs"];if([members containsObject:group]||(subject&&[members containsObject:subject[@"id"]]))if(!opened(r,c[@"id"]))return true;
 }
 return false;
}
bool chartBlocked(Runtime&r,P item,int slot){
 if(!item||slot<0||slot>3)return true;
 P song=r.get<P>(item,"songInfo");NSString*group=r.string(r.get<P>(song,"songsId"));NSDictionary*subject=songEntity(group,slot);
 return chapterBlocked(r,group,subject)||(subject&&!opened(r,subject[@"id"]));
}
bool hiddenByChapter(Runtime&r,P item){
 P song=r.get<P>(item,"songInfo");NSString*group=r.string(r.get<P>(song,"songsId"));bool custom=false;
 for(int slot=0;slot<4;++slot){NSDictionary*subject=songEntity(group,slot);if(!subject)continue;custom=true;if(!chapterBlocked(r,group,subject))return false;}
 return custom||chapterBlocked(r,group,nil);
}
uint32_t aggregateOwner=0;double aggregateScan=0;NSUInteger aggregateRevision=NSUIntegerMax;
std::map<P,std::pair<uint32_t,bool>>challengeButtonStates;
void restoreChallengeButtons(Runtime&r){for(auto&entry:challengeButtonStates){P button=target(r,entry.second.first);bool enabled=entry.second.second;if(r.alive(button))r.call(button,"set_interactable",{"System.Boolean"},{&enabled});r.gchandle_free(entry.second.first);}challengeButtonStates.clear();}
void disableChallengeButton(Runtime&r,P button){if(!r.alive(button))return;if(!challengeButtonStates.count(button))challengeButtonStates[button]={r.gchandle_new(button,false),r.unbox<bool>(r.call(button,"get_interactable"))};bool no=false;r.call(button,"set_interactable",{"System.Boolean"},{&no});}
struct HiddenItem{uint32_t root;};std::vector<HiddenItem>chapterHiddenItems;
void clearAggregate(Runtime&r){restoreChallengeButtons(r);for(auto&item:chapterHiddenItems)r.gchandle_free(item.root);chapterHiddenItems.clear();if(aggregateOwner)r.gchandle_free(aggregateOwner);aggregateOwner=0;aggregateScan=0;aggregateRevision=NSUIntegerMax;}
void itemDisplay(Runtime&r,P item,bool visible){
 r.put(item,"visible",visible);
 for(const char*field:{"selectorItemUpside","selectorItemDownside","cover","backgroundImage","previewClipPlayer"}){P component=r.get<P>(item,field);if(r.alive(component)){P go=r.call(component,"get_gameObject");r.call(go,"SetActive",{"System.Boolean"},{&visible});}}
 P mask=r.get<P>(item,"lockMask");if(!visible&&r.alive(mask))r.call(mask,"SetActive",{"System.Boolean"},{&visible});
}
void clearList(Runtime&r,P list){if(list)try{r.call(list,"Clear");}catch(...){} }
void unlockSong(Runtime&r,P value,NSString*id,int slot){
 if(!value)return;
 bool mainline=PMSettingBool("mainlineUnlock")&&pmcontent::isMainlineSong(id);
 if(!mainline&&!(entity(id)&&opened(r,id)))return;
 P unlocks=r.get<P>(value,"unlockInfo"),difficulty=r.get<P>(value,"difficulty");int n=unlocks?int(r.array_length(unlocks)):0;
 for(int i=0;i<n;++i){if(entity(id)&&i!=slot)continue;if(mainline&&(!difficulty||i>=int(r.array_length(difficulty))||r.unbox<float>(r.arrayAt(difficulty,i))<=0))continue;P u=r.arrayAt(unlocks,i);r.put(u,"unlockType",-1);clearList(r,r.get<P>(u,"unlockInfo"));}
}
void continueChain(NSString*id){
 if(![newlyOpened containsObject:id]||!runtime)return;
 [newlyOpened removeObject:id];NSDictionary*source=entity(id),*chain=source[@"unlock"][@"chain"];
 if(![chain[@"enabled"] boolValue])return;
 NSString*songID=chain[@"song"];int slot=[chain[@"slot"] intValue];NSDictionary*song=songEntity(songID,slot);
 if(!song||!opened(*runtime,song[@"id"])||(entity(song[@"targetChapter"])&&!opened(*runtime,song[@"targetChapter"])))return;
 NSMutableDictionary*db=[[PMContentStore.shared snapshot] mutableCopy],*selection=[db[@"chartSelections"] mutableCopy];if(!selection)selection=[NSMutableDictionary new];
 NSString*group=song[@"groupId"]?:song[@"id"];selection[[NSString stringWithFormat:@"%@@%d",group,slot]]=song[@"id"];db[@"chartSelections"]=selection;
 NSError*error=nil;if(![PMContentStore.shared commit:db error:&error]){logf("Unlock chain selection save failed: %s",error.localizedDescription.UTF8String);return;}
 NSDictionary*result=pmcontent::command(@"play",song[@"id"],slot);if(![result[@"ok"] boolValue])logf("Unlock chain navigation failed: %s",[result[@"message"] UTF8String]);
}
void pumpAnimations(){
 if((!menuActive&&!resultResume)||PMUnlockMediaBusy())return;
 if(!pending.count){restoreMediaAudio();if(resultResume){void(^done)(BOOL)=resultResume;resultResume=nil;menuActive=false;done(YES);}return;}
 NSDictionary*event=pending.firstObject;NSString*id=event[@"id"],*signature=event[@"signature"];
 NSDictionary*subject=entity(id),*rule=subject[@"unlock"];
 if(!subject||![rule[@"enabled"] boolValue]||![PMUnlockSignature(rule) isEqualToString:signature]||[progress isSeen:id rule:rule]){[pending removeObjectAtIndex:0];return;}
 // Intro-only rules are not consumed by a menu reveal.
 
 NSString*folder=[PMContentStore.shared asset:id],*name=rule[@"animation"];
 NSString*path=name.length?[folder stringByAppendingPathComponent:name]:@"";
 NSString*cover=[folder stringByAppendingPathComponent:@"image-after.png"];
 if(![NSFileManager.defaultManager fileExistsAtPath:cover])cover=[folder stringByAppendingPathComponent:@"image.png"];
 if(presentMedia(path,cover,subject[@"title"]?:subject[@"name"],^(BOOL completed){
  if(!completed){if(resultResume){void(^cancelled)(BOOL)=resultResume;resultResume=nil;cancelled(NO);}return;}
  if(completed){NSError*error=nil;if(![progress seen:id signature:signature error:&error])logf("Unlock seen save failed: %s",error.localizedDescription.UTF8String?:"rule changed");}
  if(pending.count&&[pending.firstObject isEqual:event])[pending removeObjectAtIndex:0];if(completed&&!resultResume){if([rule[@"chain"][@"enabled"]boolValue])restoreMediaAudio();continueChain(id);}
 }))logf("Unlock reveal started: %s",id.UTF8String);
}
void enqueueReveals(Runtime&r,bool activateMenu=true){
 if(!pending)pending=[NSMutableArray new];
 NSDictionary*db=unlockLibrary();NSMutableArray*subjects=[db[@"songs"] mutableCopy];[subjects addObjectsFromArray:db[@"chapters"]];
 for(NSDictionary*subject in subjects){NSString*id=subject[@"id"];NSDictionary*rule=subject[@"unlock"];
  if(![rule[@"enabled"] boolValue]||PMUnlockValidationError(rule)||[rule[@"playTiming"] intValue]==1||!opened(r,id)||[progress isSeen:id rule:rule])continue;
  // A difficulty with no assigned media must not replay a sibling's reveal.
  // Keep its unlock and chain state; an empty animation is a silent unlock.
  if(![rule[@"animation"]length]){NSError*error=nil;[progress seen:id signature:PMUnlockSignature(rule) error:&error];if(activateMenu)continueChain(id);continue;}
  NSDictionary*event=@{@"id":id,@"signature":PMUnlockSignature(rule)};if(![pending containsObject:event])[pending addObject:event];
 }
 if(activateMenu)menuActive=true;
 if(!menuTimer)menuTimer=[NSTimer scheduledTimerWithTimeInterval:.25 repeats:YES block:^(NSTimer*t){try{pumpAnimations();}catch(const std::exception&e){logf("Unlock queue failed: %s",e.what());}}];
}
}
NSString*coverPath(Runtime&r,NSString*identifier){
 NSString*folder=[PMContentStore.shared coverFolder:identifier];NSDictionary*subject=entity(identifier);NSString*variant=@"image";
 if(subject){BOOL locked=!opened(r,identifier),special=NO;NSDictionary*config=subject[@"coverSwitch"];NSString*mode=config[@"mode"]?:@"none";
  if(![@[@"none",@"unlock"] containsObject:mode]){NSMutableDictionary*c=[config mutableCopy];[c removeObjectForKey:@"mode"];c[@"type"]=mode;NSDictionary*rule=@{@"enabled":@YES,@"conditions":@[c]};
   if(!PMUnlockValidationError(rule)){if(!progress)progress=[[PMUnlockProgress alloc]initWithRoot:PMContentStore.shared.root];NSString*key=[@"cover:" stringByAppendingString:identifier];special=[progress isOpen:key rule:rule];if(!special&&passes(r,rule)){NSError*error=nil;special=[progress open:key rule:rule error:&error];if(error)logf("Cover progress save failed: %s",error.localizedDescription.UTF8String);}}
  }
  variant=special?@"image-special":locked?@"image-before":@"image-after";
 }
 NSString*path=[folder stringByAppendingPathComponent:[variant stringByAppendingString:@".png"]];return [NSFileManager.defaultManager fileExistsAtPath:path]?path:[folder stringByAppendingPathComponent:@"image.png"];
}
bool beforeStart(Runtime&r,void*selector,void(^resume)(void)){
 if(PMUnlockMediaBusy())return true;
 P owner=(P)selector;int index=r.get<int>(owner,"nowSong"),slot=r.get<int>(owner,"nowLevel");
 P items=r.call(owner,"get_SongItems");if(index<0||index>=r.count(items)||slot<0||slot>3)return true;
 P item=r.at(items,index),song=r.get<P>(item,"songInfo");NSString*group=r.string(r.get<P>(song,"songsId"));
 NSDictionary*subject=songEntity(group,slot);if(chapterBlocked(r,group,subject)){logf("Unlock start blocked by parent chapter");return true;}if(!subject)return false;
 NSString*id=subject[@"id"],*chapter=subject[@"targetChapter"];if(!opened(r,id)||(entity(chapter)&&!opened(r,chapter))){logf("Unlock start blocked: %s",id.UTF8String);return true;}
 NSDictionary*rule=subject[@"unlock"];if(![rule[@"enabled"] boolValue]||[rule[@"playTiming"] intValue]==0||![rule[@"animation"]length])return false;
 NSString*name=rule[@"animation"],*folder=[PMContentStore.shared asset:id],*signature=PMUnlockSignature(rule);
 uint32_t handle=r.gchandle_new(owner,false);Runtime*rt=&r;menuActive=false;
 BOOL presented=presentMedia(name.length?[folder stringByAppendingPathComponent:name]:@"",coverPath(r,id),subject[@"title"]?:subject[@"name"],^(BOOL completed){
  restoreMediaAudio(); // Release our audio state before native navigation changes it.
  P current=rt->gchandle_get_target(handle);bool valid=rt->alive(current);rt->gchandle_free(handle);menuActive=true;
  if(!completed||!valid)return;
  NSDictionary*latest=ruleFor(id);if(![PMUnlockSignature(latest) isEqualToString:signature])return;
  NSError*error=nil;[progress seen:id signature:signature error:&error];if(error)logf("Intro progress save failed: %s",error.localizedDescription.UTF8String);continueChain(id);
  resume();
 });
 if(!presented){r.gchandle_free(handle);menuActive=true;logf("Unlock intro deferred: menu is busy");return false;}
 return true;
}
void resultStarted(Runtime&r,void*owner){if(resultOwner)r.gchandle_free(resultOwner);resultOwner=r.gchandle_new(owner,false);}
bool beforeResultContinue(Runtime&r,void*button){
 if(!resultOwner)return false;P owner=target(r,resultOwner);if(!r.alive(owner))return false;
 P event=r.call(button,"get_onClick"),group=r.get<P>(event,"m_PersistentCalls"),calls=group?r.get<P>(group,"m_Calls"):nullptr;bool back=false;
 for(int i=0,n=calls?r.count(calls):0;i<n;++i){P call=r.at(calls,i);if(r.call(call,"get_target")==owner&&[r.string(r.get<P>(call,"m_MethodName"))isEqualToString:@"Back"]){back=true;break;}}
 if(!back)return false;if(resultResume||PMUnlockMediaBusy())return true;
 if(!r.unbox<bool>(r.call(button,"IsActive"))||!r.unbox<bool>(r.call(button,"IsInteractable")))return true;
 enqueueReveals(r,false);if(!pending.count)return false;
 // Chained unlocks own their next-song navigation; retain their menu path.
 for(NSDictionary*entry in pending)if([entity(entry[@"id"])[@"unlock"][@"chain"][@"enabled"]boolValue])return false;
 uint32_t handle=r.gchandle_new(event,false);Runtime*rt=&r;
 resultResume=^(BOOL completed){P saved=target(*rt,handle);try{if(completed&&resultOwner&&rt->alive(target(*rt,resultOwner)))rt->call(saved,"Invoke");}catch(...){rt->gchandle_free(handle);throw;}rt->gchandle_free(handle);};
 menuActive=false;logf("Unlock result Continue held: %lu reveals",(unsigned long)pending.count);return true;
}
void validate(Runtime&r){
 r.resolve(r.type("UnityEngine.Events","UnityEvent"),"Invoke");
 P listener=r.type("UnityEngine","AudioListener");r.resolve(listener,"get_pause",{},true);r.resolve(listener,"set_pause",{"System.Boolean"},true);r.resolve(listener,"get_volume",{},true);r.resolve(listener,"set_volume",{"System.Single"},true);
 r.field(r.type("UnityEngine.Events","UnityEventBase"),"m_PersistentCalls","UnityEngine.Events.PersistentCallGroup",false);
 r.field(r.type("UnityEngine.Events","PersistentCallGroup"),"m_Calls","System.Collections.Generic.List<UnityEngine.Events.PersistentCall>",false);
 r.resolve(r.type("UnityEngine.Events","PersistentCall"),"get_target");r.field(r.type("UnityEngine.Events","PersistentCall"),"m_MethodName","System.String",false);

 r.resolve(r.klass("PhigrosUI"),"CreateMessageBox",{"System.String","System.String","System.Boolean"},true);
 P message=r.type("Phigros.UI","MsgBox");r.field(message,"content","UnityEngine.UI.Text",false);r.field(message,"isShowing","System.Boolean",false);r.resolve(message,"Show");r.resolve(message,"Cancel");r.resolve(message,"RefreshElements");

 P challenge=r.type("Phigros2.SongSelector.Scripts","ChallengeSongSelectorControl");
 for(const char*field:{"selectButton","playButton"})r.field(challenge,field,"UnityEngine.UI.Button",false);
 r.field(challenge,"challengeSongItems","System.Collections.Generic.List<Phigros2.SongSelector.Scripts.ChallengeSongItem>",false);
 P queued=r.type("Phigros2.SongSelector.Scripts","ChallengeSongItem");r.field(queued,"songInfo","SongSelectorItem",false);r.field(queued,"levelIndex","System.Int32",false);
 r.resolve(r.klass("SongSelector"),"SortSong",{"System.Boolean"});

 P c9=r.type("Phigros2.Chapter9","Chapter9Phase1Control");
 r.field(c9,"upButton","UnityEngine.UI.Button",false);
 r.field(c9,"cameraUpTween","TweenInfo",false);
 r.field(c9,"isCameraEntering","System.Boolean",false);
 r.field(c9,"isTransitioningToPhase2","System.Boolean",false);
 r.resolve(c9,"FadeOutBgm");
 r.resolve(c9,"StartBgmTransition",{"System.Collections.IEnumerator"});
 r.resolve(c9,"<ToPhase2>g__CreateBlackScreenTransition|164_0");
 r.resolve(r.klass("BlackScreenTransition"),"TransitionTo",{"System.String"});
 P c9p2=r.type("Phigros2.Chapter9.Scripts","Chapter9Phase2Control");
 r.field(c9p2,"mapCover","UnityEngine.RectTransform",false);
 r.resolve(r.klass("GameInformation"),"GetSongInformation",{"System.String"});
 r.resolve(r.klass("TweenInfo"),"Play");
}
void mainlinePhase1Start(Runtime&r,void*value){
 if(!PMSettingBool("mainlineUnlock")||!value)return;
 P button=r.get<P>((P)value,"upButton");
 if(!button||!r.alive(button))return;
 P go=r.call(button,"get_gameObject");bool yes=true;
 r.call(go,"SetActive",{"System.Boolean"},{&yes});
 r.call(button,"set_interactable",{"System.Boolean"},{&yes});
}
bool mainlinePhase1ToPhase2(Runtime&r,void*value){
 if(!PMSettingBool("mainlineUnlock")||!value)return false;
 bool transitioning=false;
 try{
  if(r.get<bool>((P)value,"isTransitioningToPhase2")||r.get<bool>((P)value,"isCameraEntering"))return true;
  r.put((P)value,"isTransitioningToPhase2",true);transitioning=true;
  P fade=r.call((P)value,"FadeOutBgm");
  if(fade)r.call((P)value,"StartBgmTransition",{"System.Collections.IEnumerator"},{fade});
  P tween=r.get<P>((P)value,"cameraUpTween");if(tween&&r.alive(tween))r.call(tween,"Play");
  P transition=r.call((P)value,"<ToPhase2>g__CreateBlackScreenTransition|164_0");
  if(!transition){r.put((P)value,"isTransitioningToPhase2",false);return true;}
  r.call(transition,"TransitionTo",{"System.String"},{r.managedString(@"Chapter9Phase2")});
  return true;
 }catch(const std::exception&e){
  if(transitioning)try{r.put((P)value,"isTransitioningToPhase2",false);}catch(...){}
  logf("Mainline Chapter9 transition fallback: %s",e.what());
  return false;
 }
}
bool mainlineApplyMapCover(Runtime&r,void*value){
 if(!PMSettingBool("mainlineUnlock")||!value)return false;
 P cover=r.get<P>((P)value,"mapCover");
 if(cover&&r.alive(cover)){P go=r.call(cover,"get_gameObject");bool no=false;r.call(go,"SetActive",{"System.Boolean"},{&no});}
 return true;
}
void attach(Runtime&r){runtime=&r;}
void songInfo(Runtime&r,void*song,int slot,void*value){if(!runtime||!song)return;try{NSString*id=r.string(r.get<P>((P)song,"songsId"));NSDictionary*custom=songEntity(id,slot);if(custom)id=custom[@"id"];else if(entity(id))return;if(id.length&&entity(id))opened(r,id);}catch(const std::exception&e){logf("Unlock song info failed: %s",e.what());}(void)slot;(void)value;}
void itemInfo(Runtime&r,void*item,int slot,void*value){if(!runtime||!item)return;try{P info=r.get<P>((P)item,"songInfo");NSString*id=info?r.string(r.get<P>(info,"songsId")):nil;NSDictionary*selected=songEntity(id,slot);if(selected)id=selected[@"id"];else if(entity(id))return;unlockSong(r,info,id,slot);NSDictionary*custom=entity(id);if(custom){bool open=opened(r,id);BOOL hidden=[custom[@"hidden"] boolValue]&&!open;BOOL secret=[custom[@"secret"] boolValue]&&!open&&!hidden;r.put((P)item,"<Unlocked>k__BackingField",true);r.put((P)item,"visible",!hidden);r.put((P)item,"<InfoHidden>k__BackingField",secret);}else if(PMSettingBool("mainlineUnlock")&&pmcontent::isMainlineSong(id)){P difficulty=r.get<P>(info,"difficulty");bool any=false;for(uintptr_t i=0;difficulty&&i<r.array_length(difficulty);++i)if(r.unbox<float>(r.arrayAt(difficulty,(int)i))>0)any=true;r.put((P)item,"<Unlocked>k__BackingField",any);r.put((P)item,"unlockType",any?-1:0);r.put((P)item,"unlockInfo",r.managedString(@""));r.put((P)item,"visible",true);r.put((P)item,"<InfoHidden>k__BackingField",false);}if(id.length&&entity(id))opened(r,id);}catch(const std::exception&e){logf("Unlock item info failed: %s",e.what());}}
NSString*requirementName(NSString*ref,bool chapter){
 NSDictionary*db=unlockLibrary();
 for(NSDictionary*entry in db[chapter?@"chapters":@"songs"])if([entry[@"id"] isEqualToString:ref]||(!chapter&&[entry[@"groupId"] isEqualToString:ref]))return entry[chapter?@"name":@"title"]?:ref;
 NSDictionary*official=pmcontent::cachedOfficialSnapshot();
 if(chapter){for(NSDictionary*entry in official[@"chapters"])if([entry[@"chapterCode"] isEqualToString:ref])return entry[@"songInfo"][@"title"]?:ref;}
 else for(NSString*k in @[@"mainSongs",@"extraSongs",@"sideStorySongs",@"otherSongs"])for(NSDictionary*entry in official[@"songBase"][k])if([entry[@"songsId"] isEqualToString:ref])return entry[@"songsName"]?:ref;
 return ref?:@"?";
}
NSString*chapterRequirements(NSDictionary*rule){
 NSString*invalid=PMUnlockValidationError(rule);if(invalid)return invalid;
 NSMutableArray*rows=[NSMutableArray new];
 [rows addObject:[rule[@"mode"] isEqualToString:@"any"]?@"\u89e3\u9501\u8981\u6c42\uff08\u6ee1\u8db3\u4efb\u4e00\u9879\uff09":@"\u89e3\u9501\u8981\u6c42\uff08\u5168\u90e8\u6ee1\u8db3\uff09"];
 for(NSDictionary*c in rule[@"conditions"]){
  NSString*type=c[@"type"];double value=[c[@"value"] doubleValue];
  if([type isEqualToString:@"rks"]){[rows addObject:[NSString stringWithFormat:@"RKS \u2265 %g",value]];continue;}
  int slot=c[@"slot"]?[c[@"slot"] intValue]:-1;
  NSString*difficulty=slot<0?@"\u4efb\u610f\u96be\u5ea6":slotName(slot);
  NSString*name=requirementName(c[@"ref"],[type isEqualToString:@"chapter"]),*condition=nil;
  if([type isEqualToString:@"score"])condition=[NSString stringWithFormat:@"\u5206\u6570 \u2265 %.0f",value];
  else if([type isEqualToString:@"acc"])condition=[NSString stringWithFormat:@"ACC \u2265 %g%%",value];
  else if([type isEqualToString:@"fc"])condition=@"Full Combo";
  else if([type isEqualToString:@"phi"])condition=@"Phi (1000000)";
  else condition=@"\u7ae0\u8282\u5185\u6bcf\u9996\u6b4c\u5206\u6570 \u2265 700000";
  [rows addObject:[NSString stringWithFormat:@"%@ [%@] %@",name,difficulty,condition]];
 }
 return [rows componentsJoinedByString:@"\n"];
}
void chapterReady(Runtime&r,void*selector){
 try{P cards=r.get<P>((P)selector,"_chapterInfos");for(uintptr_t i=0;cards&&i<r.array_length(cards);++i){
  P card=r.arrayAt(cards,(int)i);NSString*id=r.string(r.get<P>(card,"chapterCode"));NSDictionary*custom=entity(id);
  bool mainline=!custom&&pmcontent::isMainlineChapter(id);if(!custom&&!(mainline&&PMSettingBool("mainlineUnlock")))continue;
  bool open=custom?opened(r,id):true;
  P locked=r.get<P>(card,"locked"),play=r.get<P>(card,"play");
  if(r.alive(locked)){bool lock=!open;r.call(locked,"SetActive",{"System.Boolean"},{&lock});}
  if(custom){P tip=r.get<P>(card,"unlockTip");if(r.alive(tip)){
   NSString*requirements=open?@"":chapterRequirements(ruleFor(id));
   // Use the game's central lock label, not a separate overlay.
   r.call(tip,"set_text",{"System.String"},{r.managedString(requirements)});
   bool show=!open;P labelObject=r.call(tip,"get_gameObject");r.call(labelObject,"SetActive",{"System.Boolean"},{&show});
  }}
  if(custom&&![(NSArray*)custom[@"songs"] count])open=false;
  if(r.alive(play))r.call(play,"set_interactable",{"System.Boolean"},{&open});
 }enqueueReveals(r);}catch(const std::exception&e){logf("Chapter unlock evaluation failed: %s",e.what());}
}
namespace {
uint32_t lockUIOwner=0;P lockUIItem=nullptr;int lockUISlot=-1;NSUInteger lockUIRevision=0;
bool lockUIManaged=false,lockUIBlocked=false;NSString*lockUIRequirement=nil,*lockUIDetails=nil;double lockUIEvaluate=0;
void lockActive(Runtime&r,P object,bool active){if(r.alive(object)&&r.unbox<bool>(r.call(object,"get_activeSelf"))!=active)r.call(object,"SetActive",{"System.Boolean"},{&active});}
void lockComponent(Runtime&r,P component,bool active){if(r.alive(component))lockActive(r,r.call(component,"get_gameObject"),active);}
struct TipSize{float x,y;};struct TipColor{float r,g,b,a;};
uint32_t lockTipRoot=0;bool lockTipFit=false,lockTipEnabled=true;int lockTipMin=0,lockTipMax=0,lockTipFont=0,lockTipWrap=0,lockTipVertical=0;TipSize lockTipSize{};TipColor lockTipColor{};
void restoreLockTip(Runtime&r){
 if(!lockTipRoot)return;P tip=target(r,lockTipRoot);
 if(r.alive(tip)){
  r.call(tip,"set_resizeTextForBestFit",{"System.Boolean"},{&lockTipFit});
  r.call(tip,"set_resizeTextMinSize",{"System.Int32"},{&lockTipMin});r.call(tip,"set_resizeTextMaxSize",{"System.Int32"},{&lockTipMax});
  r.call(tip,"set_fontSize",{"System.Int32"},{&lockTipFont});r.call(tip,"set_horizontalOverflow",{"UnityEngine.HorizontalWrapMode"},{&lockTipWrap});
  r.call(tip,"set_verticalOverflow",{"UnityEngine.VerticalWrapMode"},{&lockTipVertical});
  r.call(tip,"set_enabled",{"System.Boolean"},{&lockTipEnabled});r.call(tip,"set_color",{"UnityEngine.Color"},{&lockTipColor});
  P rect=r.call(tip,"get_rectTransform");r.call(rect,"set_sizeDelta",{"UnityEngine.Vector2"},{&lockTipSize});
 }
 r.gchandle_free(lockTipRoot);lockTipRoot=0;
}
void fitLockTip(Runtime&r,P tip,bool blocked){
 static NSString*measuredText=nil;static float measuredWidth=-1,measuredHeight=-1;static int fittedFont=24;
 if(!blocked){restoreLockTip(r);return;}
 if(target(r,lockTipRoot)!=tip){
  measuredText=nil;measuredWidth=measuredHeight=-1;
  restoreLockTip(r);
  lockTipFit=r.unbox<bool>(r.call(tip,"get_resizeTextForBestFit"));lockTipMin=r.unbox<int>(r.call(tip,"get_resizeTextMinSize"));lockTipMax=r.unbox<int>(r.call(tip,"get_resizeTextMaxSize"));
  lockTipFont=r.unbox<int>(r.call(tip,"get_fontSize"));lockTipWrap=r.enumValue(r.call(tip,"get_horizontalOverflow"),"UnityEngine.HorizontalWrapMode");lockTipVertical=r.enumValue(r.call(tip,"get_verticalOverflow"),"UnityEngine.VerticalWrapMode");
  lockTipEnabled=r.unbox<bool>(r.call(tip,"get_enabled"));lockTipColor=r.unbox<TipColor>(r.call(tip,"get_color"));
  lockTipSize=r.unbox<TipSize>(r.call(r.call(tip,"get_rectTransform"),"get_sizeDelta"));lockTipRoot=r.gchandle_new(tip,false);
  logf("Song unlock single-line label configured: nativeFont=%d vertical=%d",lockTipFont,lockTipVertical);
 }
 // Do not let a larger single line be entirely truncated by the old short box.
 // Reassert only changed properties after native selector updates.
 bool fit=false,yes=true;int font=24,overflow=1;
 if(r.unbox<bool>(r.call(tip,"get_resizeTextForBestFit")))r.call(tip,"set_resizeTextForBestFit",{"System.Boolean"},{&fit});
 if(r.enumValue(r.call(tip,"get_horizontalOverflow"),"UnityEngine.HorizontalWrapMode")!=overflow)r.call(tip,"set_horizontalOverflow",{"UnityEngine.HorizontalWrapMode"},{&overflow});
 if(r.enumValue(r.call(tip,"get_verticalOverflow"),"UnityEngine.VerticalWrapMode")!=overflow)r.call(tip,"set_verticalOverflow",{"UnityEngine.VerticalWrapMode"},{&overflow});
 if(!r.unbox<bool>(r.call(tip,"get_enabled")))r.call(tip,"set_enabled",{"System.Boolean"},{&yes});
 TipColor color=r.unbox<TipColor>(r.call(tip,"get_color"));if(color.a<1){color.a=1;r.call(tip,"set_color",{"UnityEngine.Color"},{&color});}
 P rect=r.call(tip,"get_rectTransform");struct Rect{float x,y,w,h;};Rect bounds=r.unbox<Rect>(r.call(rect,"get_rect"));
 // The old multiline minimum was 12: use twice that size, not the
 // potentially much larger native font. Keep one line inside the original box.
 NSString*text=r.string(r.call(tip,"get_text"));
 if(![measuredText isEqualToString:text]||std::fabs(bounds.w-measuredWidth)>.5f||std::fabs(bounds.h-measuredHeight)>.5f){
  r.call(tip,"set_fontSize",{"System.Int32"},{&font});
  float width=r.unbox<float>(r.call(tip,"get_preferredWidth")),height=r.unbox<float>(r.call(tip,"get_preferredHeight"));
  float availableW=std::max(1.f,bounds.w-8.f),availableH=std::max(1.f,bounds.h-4.f);
  float ratio=std::min(1.f,std::min(width>0?availableW/width:1.f,height>0?availableH/height:1.f));
  fittedFont=std::max(1,int(std::floor(font*ratio)));
  measuredText=text;measuredWidth=bounds.w;measuredHeight=bounds.h;
 }
 if(r.unbox<int>(r.call(tip,"get_fontSize"))!=fittedFont)r.call(tip,"set_fontSize",{"System.Int32"},{&fittedFont});
}
#include "PMUnlockDetails.inc"
void resetLockUI(Runtime&r){clearRequirementUI(r);restoreLockTip(r);if(lockUIOwner)r.gchandle_free(lockUIOwner);lockUIOwner=0;lockUIItem=nullptr;lockUISlot=-1;lockUIManaged=false;lockUIRequirement=nil;lockUIEvaluate=0;}
void songLockUI(Runtime&r,P selector,double now){
 P items=r.call(selector,"get_SongItems");int index=r.get<int>(selector,"nowSong"),slot=r.get<int>(selector,"nowLevel");
 if(index<0||index>=r.count(items)||slot<0||slot>3)return;
 P item=r.at(items,index);NSUInteger revision=PMContentStore.shared.revision;
 bool changed=target(r,lockUIOwner)!=selector||lockUIItem!=item||lockUISlot!=slot||lockUIRevision!=revision;
 if(changed||now-lockUIEvaluate>=1){
  P song=r.get<P>(item,"songInfo");NSString*group=r.string(r.get<P>(song,"songsId"));NSDictionary*subject=songEntity(group,slot);
  bool wasManaged=lockUIManaged;
  lockUIManaged=subject!=nil;lockUIBlocked=false;lockUIRequirement=nil;lockUIDetails=nil;
  if(subject){NSString*sid=subject[@"id"],*chapter=subject[@"targetChapter"];bool songOpen=opened(r,sid),chapterOpen=!entity(chapter)||opened(r,chapter);
   lockUIBlocked=!songOpen||!chapterOpen;
   if(lockUIBlocked){NSMutableArray*tips=[NSMutableArray new];if(!songOpen)[tips addObject:chapterRequirements(ruleFor(sid))];if(!chapterOpen)[tips addObject:chapterRequirements(ruleFor(chapter))];lockUIDetails=[tips componentsJoinedByString:@"\n\n"];NSMutableArray*singleLine=[NSMutableArray new];for(NSString*tip in tips){NSArray*rows=[tip componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];NSMutableArray*parts=[NSMutableArray new];for(NSString*row in rows){NSString*part=[row stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];if(part.length)[parts addObject:part];}if(parts.count>1){NSString*heading=parts.firstObject;[parts removeObjectAtIndex:0];[singleLine addObject:[NSString stringWithFormat:@"%@：%@",heading,[parts componentsJoinedByString:@"；"]]];}else if(parts.count)[singleLine addObject:parts.firstObject];}lockUIRequirement=[singleLine componentsJoinedByString:@"；"];}
   // Native SetLevel refuses changes when the entire item is marked locked.
   // Keep custom groups navigable; per-chart lock UI and beforeStart enforce access.
   r.put(item,"<Unlocked>k__BackingField",true);
   r.put(item,"unlockInfo",r.managedString(lockUIRequirement?:@""));
  }else if(wasManaged){restoreLockTip(r);
   // Native Update has already selected the new official song. Restore only
   // the extra visibility overrides, retaining its own lock/button decision.
   P locked=r.get<P>(selector,"locked");bool visible=!r.alive(locked)||!r.unbox<bool>(r.call(locked,"get_activeSelf"));
   for(const char*field:{"difficulty","level","score","acc","ratingDisplayController"})lockComponent(r,r.get<P>(selector,field),visible);
  }
  if(target(r,lockUIOwner)!=selector){if(lockUIOwner)r.gchandle_free(lockUIOwner);lockUIOwner=r.gchandle_new(selector,false);}
  lockUIItem=item;lockUISlot=slot;lockUIRevision=revision;lockUIEvaluate=now;
 }
 if(!lockUIManaged){showRequirementButton(r,nullptr,false);return;}
 bool blocked=lockUIBlocked,playable=!blocked;
 P mask=r.get<P>(item,"lockMask");
 if(!r.alive(mask)&&blocked){P prefab=r.get<P>(selector,"lockMaskPrefab"),parent=r.get<P>(item,"coverRect");if(r.alive(prefab)&&r.alive(parent)){bool world=false;mask=r.stat(r.type("UnityEngine","Object"),"Instantiate",{"UnityEngine.Object","UnityEngine.Transform","System.Boolean"},{prefab,parent,&world});r.put(item,"lockMask",mask);}}
 lockActive(r,mask,blocked);lockActive(r,r.get<P>(selector,"locked"),blocked);
 for(const char*field:{"difficulty","level","score","acc","ratingDisplayController"})lockComponent(r,r.get<P>(selector,field),!blocked);
 P tip=r.get<P>(selector,"unlockTip");if(r.alive(tip)){
  P parent=r.call(r.call(tip,"get_transform"),"get_parent");lockComponent(r,parent,blocked);lockComponent(r,tip,blocked);
  NSString*text=blocked?lockUIRequirement:@"";if(![r.string(r.call(tip,"get_text"))isEqualToString:text])r.call(tip,"set_text",{"System.String"},{r.managedString(text?:@"")});
  fitLockTip(r,tip,blocked);
  bool details=blocked&&r.unbox<int>(r.call(tip,"get_fontSize"))<20;
  showRequirementButton(r,tip,details);


 }
 P button=r.get<P>(selector,"startButton");if(r.alive(button)&&r.unbox<bool>(r.call(button,"get_interactable"))!=playable)r.call(button,"set_interactable",{"System.Boolean"},{&playable});
 for(const char*field:{"selectorItemUpside","selectorItemDownside"}){P row=r.get<P>(item,field);if(r.alive(row)){lockActive(r,r.get<P>(row,"locked"),blocked);lockComponent(r,r.get<P>(row,"difficulty"),!blocked);}}
}
}
bool selectorAccess(Runtime&r,void*raw){
 P selector=raw;if(!selector||r.get<bool>(selector,"exit"))return true;
 restoreChallengeButtons(r);
 if(target(r,aggregateOwner)!=selector){clearAggregate(r);aggregateOwner=r.gchandle_new(selector,false);}
 P items=r.call(selector,"get_SongItems");if(!items)return true;
 double now=NSDate.timeIntervalSinceReferenceDate;NSUInteger revision=PMContentStore.shared.revision;
 if(now-aggregateScan>=1||aggregateRevision!=revision){
  aggregateScan=now;aggregateRevision=revision;bool changed=false;
  int selected=r.get<int>(selector,"nowSong");P selectedItem=selected>=0&&selected<r.count(items)?r.at(items,selected):nullptr;
  for(auto it=chapterHiddenItems.begin();it!=chapterHiddenItems.end();){P item=target(r,it->root);if(item&&!hiddenByChapter(r,item)){r.call(items,"Add",{"SongSelectorItem"},{item});itemDisplay(r,item,true);r.gchandle_free(it->root);it=chapterHiddenItems.erase(it);changed=true;}else ++it;}
  for(int i=r.count(items)-1;i>=0;--i){P item=r.at(items,i);if(!hiddenByChapter(r,item))continue;
   chapterHiddenItems.push_back({r.gchandle_new(item,false)});itemDisplay(r,item,false);r.call(items,"RemoveAt",{"System.Int32"},{&i});changed=true;
  }
  if(changed&&r.count(items)>0){int next=0;for(int i=0;i<r.count(items);++i)if(r.at(items,i)==selectedItem){next=i;break;}
   r.put(selector,"nowSong",next);r.put(selector,"targetSong",next);r.put(selector,"nowSongSelectorValue",float(next));bool instantiate=false;
   r.call(selector,"SortSong",{"System.Boolean"},{&instantiate});r.call(selector,"SetText");
  }
 }
 if(r.count(items)==0){
  for(const char*field:{"startButton"}){P button=r.get<P>(selector,field);if(r.alive(button)){bool no=false;r.call(button,"set_interactable",{"System.Boolean"},{&no});}}
  P challenge=r.get<P>(selector,"challengeSongSelectorControl");if(r.alive(challenge))for(const char*field:{"selectButton","playButton"}){P button=r.get<P>(challenge,field);if(r.alive(button)){bool no=false;r.call(button,"set_interactable",{"System.Boolean"},{&no});}}
  return false;
 }
 return true;
}
bool blockChallengeButton(Runtime&r,void*raw){
 P selector=target(r,aggregateOwner);if(!r.alive(selector))return false;
 P challenge=r.get<P>(selector,"challengeSongSelectorControl");if(!r.alive(challenge))return false;
 P button=raw;bool select=button==r.get<P>(challenge,"selectButton"),play=button==r.get<P>(challenge,"playButton");if(!select&&!play)return false;
 if(select){P items=r.call(selector,"get_SongItems");int index=r.get<int>(selector,"nowSong");
  if(index<0||index>=r.count(items)||chartBlocked(r,r.at(items,index),r.get<int>(selector,"nowLevel"))){return true;}
 }
 if(play){P queue=r.get<P>(challenge,"challengeSongItems");for(int i=0,n=r.count(queue);i<n;++i){P entry=r.at(queue,i);if(chartBlocked(r,r.get<P>(entry,"songInfo"),r.get<int>(entry,"levelIndex"))){return true;}}}
 return false;
}
bool ownsRequirementButton(void*button){return button&&button==requirementButton;}
bool pressRequirement(Runtime&r,void*button){if(!ownsRequirementButton(button))return false;activateRequirement(r,"native-button");return true;}
void refreshListLocks(Runtime&r,P selector){
 static P last=nullptr;static int lastSlot=-1,lastCount=-1;static NSUInteger lastRev=NSUIntegerMax;static double lastTime=0;static std::map<P,std::pair<bool,bool>>cache;
 P items=r.call(selector,"get_SongItems");int slot=r.get<int>(selector,"nowLevel");if(slot<0||slot>3)return;
 int count=r.count(items);double time=NSDate.timeIntervalSinceReferenceDate;NSUInteger rev=PMContentStore.shared.revision;
 if(last!=selector||lastSlot!=slot||lastCount!=count||lastRev!=rev||time-lastTime>=1){cache.clear();last=selector;lastSlot=slot;lastCount=count;lastRev=rev;lastTime=time;
  for(int i=0;i<count;++i){P item=r.at(items,i),song=r.get<P>(item,"songInfo");NSString*group=r.string(r.get<P>(song,"songsId"));NSDictionary*subject=songEntity(group,slot);if(subject)cache[item]={chartBlocked(r,item,slot),[subject[@"secret"]boolValue]};}
 }
 for(int i=0;i<count;++i){P item=r.at(items,i);auto entry=cache.find(item);if(entry==cache.end())continue;
  bool blocked=entry->second.first;r.put(item,"<Unlocked>k__BackingField",true);
  r.put(item,"unlockType",blocked?0:-1);r.put(item,"<InfoHidden>k__BackingField",blocked&&entry->second.second);
  P mask=r.get<P>(item,"lockMask");if(r.alive(mask))lockActive(r,mask,blocked);
  for(const char*field:{"selectorItemUpside","selectorItemDownside"}){P row=r.get<P>(item,field);if(r.alive(row)){lockActive(r,r.get<P>(row,"locked"),blocked);lockComponent(r,r.get<P>(row,"difficulty"),!blocked);}}
 }
}
void tick(Runtime&r,void*selector){
 if(!selector||r.get<bool>((P)selector,"exit")){requirementTap.reset();requirementVisible=false;menuActive=false;return;}
 double now=NSDate.timeIntervalSinceReferenceDate;
 try{P challenge=r.get<P>((P)selector,"challengeSongSelectorControl");if(r.alive(challenge)){
  for(const char*field:{"selectButton","playButton"}){P button=r.get<P>(challenge,field);if(r.alive(button)&&blockChallengeButton(r,button))disableChallengeButton(r,button);}
 }}catch(const std::exception&e){logf("Challenge access UI: %s",e.what());}
 try{refreshListLocks(r,(P)selector);songLockUI(r,(P)selector,now);}catch(const std::exception&e){if(now-lastScan>=1)logf("Song unlock UI failed: %s",e.what());}
 try{pollRequirementInput(r,(P)selector);}catch(const std::exception&e){requirementTap.reset();if(now-lastScan>=1)logf("Unlock details input: %s",e.what());}
 if(now-lastScan<1)return;lastScan=now;enqueueReveals(r);
}

void clear(Runtime&r){if(resultResume){void(^done)(BOOL)=resultResume;resultResume=nil;done(NO);}if(resultOwner){r.gchandle_free(resultOwner);resultOwner=0;}clearAggregate(r);resetLockUI(r);menuActive=false;[menuTimer invalidate];menuTimer=nil;PMCancelUnlockMedia();restoreMediaAudio();menuActive=false;[pending removeAllObjects];lastScan=0;(void)r;}
}
