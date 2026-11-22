// Unity owns these objects for the scene lifetime. Use them only for identity.
P doorProgress=nullptr, lostDoorProgress=nullptr;
// Scene ownership outlives the score binding, including the HP failure fade.
P pauseLockedDoor=nullptr;
bool watchingDoorLaunch=false;

// Apply only to the per-attempt copy, and only after consuming an exact replay.
static inline bool applyChapterReplay(bool matched,phimod::Options &attemptOptions){
 if(matched)attemptOptions.hpEnabled=false;
 return matched;
}

bool doorPlayEligible(const phimod::Options &options){
 return options.allowsDoorChallenge();
}

// Owned by the exact door binding. Release presentation synchronously, including
// a lethal judgment nested inside the native judge update.
void (*endDoorPresentation)()=nullptr;
P currentLevel=nullptr;
void clearDoorPresentation(){
 if(!endDoorPresentation)return;
 auto end=endDoorPresentation;
 endDoorPresentation=nullptr;
 end();
}
void releaseDoorBinding(){
 doorProgress=nullptr;
 clearDoorPresentation();
}
void abandonBoundDoor(){
 if(!doorProgress)return;
 releaseDoorBinding();
 PMDoorAbandon();
}
void finishBoundDoor(BOOL clear){
 if(!doorProgress)return;
 releaseDoorBinding(); // Disarm before handing the outcome to the OS worker.
 PMDoorFinish(clear);
}

void observeDoorLoss(P pc,const phimod::Session &session,bool accepted,float before){
 if(!doorProgress || pc!=doorProgress || !accepted || before<=0 || !session.trackLost())return;
 try{
  auto &r=R();
  if(!doorPlayEligible(session.options()) || r.get<bool>(pc,"levelBreak") || r.get<bool>(pc,"leave") || r.get<bool>(pc,"_inChallengeMode")){
   abandonBoundDoor();
   return;
  }
  lostDoorProgress=pc;
  finishBoundDoor(NO);
 }catch(const std::exception &e){diagf("Door HP outcome unavailable: %s",e.what());abandonBoundDoor();}
}

void settleDoorEnd(P pc,const phimod::Session *session,bool ending){
 if(!doorProgress || pc!=doorProgress)return;
 try{
  auto &r=R();P info=r.get<P>(pc,"levelInformation");
  if(session && doorPlayEligible(session->options()) && !ending && !session->trackLost() && session->hp()>0 &&
     !r.get<bool>(pc,"levelBreak") && !r.get<bool>(pc,"leave") && !r.get<bool>(pc,"_inChallengeMode") &&
     info && r.get<bool>(info,"chartLoaded") && r.get<bool>(info,"levelBegan") &&
     r.get<bool>(info,"levelOver") && r.get<bool>(info,"canLevelOver"))finishBoundDoor(YES);
  else abandonBoundDoor();
 }catch(const std::exception &e){diagf("Door level end unavailable: %s",e.what());abandonBoundDoor();}
}

bool cancelIdleDoorLaunch(P selector,bool disabling=false){
 if(!watchingDoorLaunch || (!disabling && PMUnlockMediaBusy()))return false;
 // An accepted native launch holds exit until Awake. A canceled intro gives
 // control back to the selector and never creates a LevelControl to clean up.
 try{if(R().get<bool>(selector,"exit"))return false;}
 catch(const std::exception &e){diagf("Door launch state unavailable: %s",e.what());}
 watchingDoorLaunch=false;
 PMDoorCancelPending();
 return true;
}

// The 4.0.4 gesture path (JudgeControl.Update -> CheckPause) and the
// app pause/focus path (ProgressControl.Update -> Play(false)) both read
// LevelInformation.canPause. Only timed cues temporarily borrow that flag.
template<class Bridge> class StoryPauseScope {
 Bridge &r;
 P levelOwner=nullptr,owner=nullptr,info=nullptr;
 bool course=false;
public:
 StoryPauseScope(const StoryPauseScope &)=delete;
 StoryPauseScope(Bridge &runtime,P self,bool judge,bool (*blocks)(double),P courseOwner=nullptr):r(runtime){
  if(!endDoorPresentation&&!pauseLockedDoor&&!courseOwner)return;
  try{
   P pc=judge?r.template get<P>(self,"progressControl"):self;
   if(!pc)return;
   if(pc==pauseLockedDoor){
    // Both stock pause inputs may run before levelBegan, or after scoring ends.
    P level=r.template get<P>(pc,"levelInformation");
    if(level && r.template get<bool>(level,"canPause"))r.put(level,"canPause",false);
    if(judge && r.template get<float>(self,"pauseTime")>0)r.put(self,"pauseTime",0.f);
    if(!judge && r.template get<bool>(pc,"leave"))r.put(pc,"leave",false);
    return;
   }
   if(pc!=doorProgress&&pc!=courseOwner)return;
   bool whole=pc==courseOwner;
   P level=r.template get<P>(pc,"levelInformation");
   if(!level || (pc!=courseOwner&&r.template get<bool>(pc,"levelBreak")) || r.template get<bool>(level,"levelOver")){
    clearDoorPresentation();return;
   }
   if(!r.template get<bool>(level,"levelBegan") || !r.template get<bool>(pc,"isPlaying") ||
      (!whole&&!blocks(r.template get<float>(pc,"nowTime"))) || !r.template get<bool>(level,"canPause"))return;
   if(judge){
    if(r.template get<float>(self,"pauseTime")>0)r.put(self,"pauseTime",0.f);
   }else if(r.template get<bool>(pc,"leave")){
    // Both application callbacks latch leave. Consume the blocked request so
    // native Update cannot replay it after the end boundary.
    r.put(pc,"leave",false);
   }
   r.put(level,"canPause",false);
   levelOwner=currentLevel;owner=pc;info=level;course=(pc==courseOwner);
  }catch(const std::exception &e){diagf("Story pause gate: %s",e.what());}
 }
 ~StoryPauseScope(){
  if(!info || currentLevel!=levelOwner || owner==lostDoorProgress)return;
  try{
   if((course||!r.template get<bool>(owner,"levelBreak")) && !r.template get<bool>(info,"levelOver"))r.put(info,"canPause",true);
  }catch(const std::exception &e){diagf("Story pause restore: %s",e.what());}
 }
};
