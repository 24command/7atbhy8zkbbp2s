#include "PMSecretCourseRuntime.hpp"
#import "PMDoorRun.h"
#import "PMDiagnostics.h"
#include <vector>
#include <atomic>
#include <memory>
namespace pmsecretcourse {
namespace {
uint32_t owned;
// Save hooks can run off the selector thread; never inspect managed roots there.
std::atomic<bool> protecting{false};
struct Previous {
 Pin list,hidden,result,notes,start;
 int index,active,tier,hp; bool enabled,failed;
 Previous(Runtime &r,P g):list(r,r.get<P>(g,"challengeSongItems")),hidden(r,r.get<P>(g,"hiddenChallengeSongItem")),
 result(r,r.get<P>(g,"levelResultInfo")),notes(r,r.get<P>(g,"noteCodes")),start(r,r.get<P>(g,"levelStartInfo")),
 index(r.get<int>(g,"nowChallengeIndex")),active(r.get<int>(g,"activeChallengeSongIndex")),tier(r.get<int>(g,"secretChallengeLifeTierIndex")),
 hp(r.get<int>(g,"secretChallengeLife")),enabled(r.get<bool>(g,"secretChallengeLifeEnabled")),failed(r.get<bool>(g,"secretChallengeLifeFailed")){}
 void restore(Runtime &r,P g){
  r.put(g,"challengeSongItems",list.get());r.put(g,"hiddenChallengeSongItem",hidden.get());r.put(g,"levelResultInfo",result.get());
  r.put(g,"noteCodes",notes.get());r.put(g,"levelStartInfo",start.get());r.put(g,"nowChallengeIndex",index);r.put(g,"activeChallengeSongIndex",active);
  r.put(g,"secretChallengeLifeTierIndex",tier);r.put(g,"secretChallengeLife",hp);r.put(g,"secretChallengeLifeEnabled",enabled);r.put(g,"secretChallengeLifeFailed",failed);
 }
};
std::unique_ptr<Previous> previous;
NSString *chapterID,*doorID;
int entered=-1, launchedTier=-1;
bool reported;
P progressOwner;
bool finishedLeg,lockPause;
struct Binding {uint32_t root; NSDictionary *chart;};
std::vector<Binding> bindings;
P rules(Runtime &r){return r.type("Phigros2.ChallengeMode.Scripts","SecretChallengeLifeRules");}
bool owns(Runtime &r,P game){return owned&&r.get<P>(game,"challengeSongItems")==r.gchandle_get_target(owned);}
void release(Runtime &r){if(owned)r.gchandle_free(owned);owned=0;previous.reset();protecting.store(false);clearBindings(r);chapterID=nil;doorID=nil;entered=launchedTier=-1;reported=false;progressOwner=nullptr;finishedLeg=false;}
}
P pauseOwner(){return active()&&lockPause&&!reported&&!finishedLeg?progressOwner:nullptr;}
bool active(){return protecting.load();}
void bindChart(Runtime &r,P song,NSDictionary *chart){bindings.push_back({r.gchandle_new(song,false),chart?:@{}});}
void clearBindings(Runtime &r){for(auto &b:bindings)r.gchandle_free(b.root);bindings.clear();}
NSDictionary *binding(Runtime &r,P song){for(auto &b:bindings)if(r.gchandle_get_target(b.root)==song)return b.chart;return nil;}
bool launch(Runtime &r,P list,NSString *chapter,NSString *door,NSInteger tier,bool noPause){
 P game=r.mainGame(),rulesClass=rules(r);
 const int count=r.count(list);
 if(active()||(count!=3&&count!=4))return false;
 if(tier < -1 || tier > 4)return false;
 int index=tier==-1?1:int(tier); // Chapter-local default: 10 LIFE, never read stock tier saves.
 if(index<0||r.unbox<int>(r.stat(rulesClass,"NormalizeTierIndex",{"System.Int32"},{&index}))!=index)return false;
 int hp=r.unbox<int>(r.stat(rulesClass,"GetLifeForTierIndex",{"System.Int32"},{&index}));if(hp<=0)return false;
 auto saved=std::make_unique<Previous>(r,game);
 Pin result(r,r.object_new(r.klass("LevelResultInfo")));r.call(result.get(),".ctor");
 // No stock PlayUnlock: it substitutes its own song IDs. ChallengeMode's
 // iterator reads rows 0..2 from the list and row 3 from hiddenChallengeSongItem.
 owned=r.gchandle_new(list,false);if(!owned)return false;previous=std::move(saved);protecting.store(true);chapterID=[chapter copy];doorID=[door copy];launchedTier=index;lockPause=noPause;
 try{
  r.put(game,"challengeSongItems",list);r.put(game,"hiddenChallengeSongItem",count==4?r.at(list,3):nullptr);
  r.put(game,"levelResultInfo",result.get());r.put(game,"nowChallengeIndex",0);
  // The queue and its entries are fresh. Initialize only transient LIFE fields;
  // the stock initializer conditionally reads and repairs saved progression.
  r.put(game,"activeChallengeSongIndex",-1);r.put(game,"secretChallengeLifeFailed",false);
  r.put(game,"secretChallengeLifeTierIndex",index);r.put(game,"secretChallengeLife",hp);r.put(game,"secretChallengeLifeEnabled",true);
  r.stat(r.type("UnityEngine.SceneManagement","SceneManager"),"LoadScene",{"System.String"},{r.string_new("ChallengeMode")});return true;
 }catch(...){@try{previous->restore(r,game);}@finally{release(r);}throw;}
}
void level(Runtime &r,P progress){
 if(!active())return;P g=r.mainGame();if(!owns(r,g)){release(r);return;}
 int i=r.get<int>(g,"activeChallengeSongIndex");
 if(reported||!progress||(entered>=0&&!finishedLeg)||i!=entered+1||i<0||i>=r.count(r.gchandle_get_target(owned))){menu(r);return;}
 P entry=r.at(r.gchandle_get_target(owned),i),row=r.get<P>(entry,"songInfo"),song=r.get<P>(row,"songInfo"),start=r.get<P>(g,"levelStartInfo");
 int slot=r.get<int>(entry,"levelIndex");P levels=r.get<P>(song,"levels");
 if(!start||!levels||slot<0||uintptr_t(slot)>=r.array_length(levels)||
    ![r.string(r.get<P>(start,"songsId")) isEqual:r.string(r.get<P>(song,"songsId"))]||
    ![r.string(r.get<P>(start,"songsLevel")) isEqual:r.string(r.arrayAt(levels,slot))]){menu(r);return;}
 NSDictionary *chart=binding(r,song);NSString *key=r.string(r.get<P>(start,"chartAddressableKey"));
 if(!chart||!key.length||(chart.count?![key hasPrefix:[NSString stringWithFormat:@"PM/%@/chart@",chart[@"id"]]]:[key hasPrefix:@"PM/"])){menu(r);return;}
 entered=i;progressOwner=progress;finishedLeg=false;
}
// The challenge mod configures LevelBreak("ChallengeMode") on every leg, so
// levelBreak alone is not evidence of abandonment. Observe the native end flags
// before the result is copied or the failed-run filler creates zero results.
void progressFrame(Runtime &r,P pc){
 if(!active()||finishedLeg||reported||pc!=progressOwner||!r.get<bool>(pc,"_inChallengeMode")||r.get<bool>(pc,"leave"))return;
 P info=r.get<P>(pc,"levelInformation");
 if(info&&r.get<bool>(info,"chartLoaded")&&r.get<bool>(info,"levelBegan")&&r.get<bool>(info,"canLevelOver")&&r.get<bool>(info,"levelOver"))finishedLeg=true;
}
P resultList(Runtime &r){return active()&&owns(r,r.mainGame())?r.gchandle_get_target(owned):nullptr;}
void result(Runtime &r){
 if(!active())return;P g=r.mainGame();if(!owns(r,g)){release(r);return;}
 if(reported)return;reported=true;
 if(entered<0||!r.get<bool>(g,"secretChallengeLifeEnabled")||entered!=r.get<int>(g,"activeChallengeSongIndex"))return;
 if(r.get<bool>(g,"secretChallengeLifeFailed")){if(r.get<int>(g,"secretChallengeLife")<=0)PMDoorRecordCourseOutcome(chapterID,doorID,launchedTier,NO);return;}
 P list=r.gchandle_get_target(owned);const int count=r.count(list);
 if(!finishedLeg||entered!=count-1||r.get<int>(g,"secretChallengeLife")<=0)return;
 for(int i=0;i<count;++i)if(!r.get<P>(r.at(list,i),"result"))return;
 PMDoorRecordCourseOutcome(chapterID,doorID,launchedTier,YES);
}
void menu(Runtime &r){
 if(!active())return;
 @try{P g=r.mainGame();if(owns(r,g))previous->restore(r,g);}
 @finally{release(r);}
}
}
