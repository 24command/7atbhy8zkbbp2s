// Unity owns these objects for the scene lifetime. Use them only for identity.
P doorProgress=nullptr, lostDoorProgress=nullptr;
bool watchingDoorLaunch=false;

bool doorPlayEligible(const phimod::Options &options){
 return !options.autoplay && !options.practiceMode && std::fabs(options.playbackRate-1.f)<=.0001f;
}

void abandonBoundDoor(){
 if(!doorProgress)return;
 doorProgress=nullptr;
 PMDoorAbandon();
}
void finishBoundDoor(BOOL clear){
 if(!doorProgress)return;
 doorProgress=nullptr; // Disarm before handing the outcome to the OS worker.
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

void cancelIdleDoorLaunch(P selector){
 if(!watchingDoorLaunch || PMUnlockMediaBusy())return;
 // An accepted native launch holds exit until Awake. A canceled intro gives
 // control back to the selector and never creates a LevelControl to clean up.
 try{if(R().get<bool>(selector,"exit"))return;}
 catch(const std::exception &e){diagf("Door launch state unavailable: %s",e.what());}
 watchingDoorLaunch=false;
 PMDoorCancelPending();
}
