// Included inside PMHookBackend's anonymous namespace. The portable controller is
// compiled verbatim by PMSongInterruptionGameplayTest.cpp with a fake adapter.
namespace songinterruption {
enum class Entry { Progress, Judge, Audio, Notes };

template<class Host> class Gameplay {
 using Object=typename Host::Object;
 Host &host;
 typename Host::Owner owner{};
 typename Host::Snapshot saved{};
 uint64_t generation=0;
 bool bound=false,frozen=false,recovering=false,triggering=false,quitClaimed=false;
 bool reportedRecovery=false;
 void discard(){
  ++generation;bound=false;frozen=false;recovering=false;triggering=false;quitClaimed=false;
  reportedRecovery=false;host.release(owner);owner={};saved={};
 }
 bool owns(uint64_t ticket)const{return bound&&ticket==generation;}
 void enforce(){
  if(!bound||!frozen)return;
  // Focus/resume callbacks can restart the wrapper outside these Update hooks.
  // Read its flag each held tick, but never issue a managed Pause every frame.
  try{host.repauseIfPlaying(owner);}catch(const std::exception &e){
   if(!reportedRecovery){host.error("resumed audio pause",e.what());reportedRecovery=true;}
  }
  try{host.hold(owner,saved);}catch(const std::exception &e){
   if(!reportedRecovery){host.error("hold",e.what());reportedRecovery=true;}
  }
 }
 bool restore(){
  if(!bound)return true;
  if(!host.live(owner)){discard();return true;} // Never resurrect a dead/new scene.
  if(!frozen){discard();return true;}
  try{host.resume(owner,saved);discard();return true;}
  catch(const std::exception &e){
   if(!reportedRecovery){host.error("resume (held; retrying)",e.what());reportedRecovery=true;}
   // Resume may have scheduled sound before another managed operation failed.
   // Re-pause it and retain the native hold; do not release on partial rollback.
   try{host.pause(owner);}catch(const std::exception &pauseError){host.error("re-pause",pauseError.what());}
   enforce();return false;
  }
 }
 bool freeze(uint64_t ticket){
  if(!owns(ticket)||frozen||!host.live(owner))return false;
  try{
   if(!host.eligible(owner))return false;
   host.capture(owner,saved); // Complete snapshot before the first mutation.
   if(!owns(ticket)||!host.live(owner))return false;
   frozen=true;
   host.protect(); // Save latch precedes every native mutation and survives rollback.
   host.hold(owner,saved);
   host.pause(owner); // 4.0.4 AddressableAudioSource.Pause, NEVER ProgressControl.Play(false).
   host.hold(owner,saved); // Pause resets wrapper clock bookkeeping; preserve exposed clocks.
   return owns(ticket)&&host.live(owner);
  }catch(const std::exception &e){host.error("freeze",e.what());return false;}
 }
 void close(uint64_t ticket){
  if(!owns(ticket)||!frozen||recovering||quitClaimed||!host.live(owner))return;
  quitClaimed=true; // This callback is supplied ONLY to the UI's sole user action.
  host.quit();
 }
public:
 explicit Gameplay(Host &adapter):host(adapter){}
 bool holding()const{return bound&&frozen;}
 bool validHost(){return bound&&host.live(owner);}
 void invalidated(){
  if(!bound)return;
  recovering=true;
  (void)restore();
 }
 // New Awake must not erase an independently armed next launch. Begin below
 // retires the previous UI before publishing the new native owner.
 void awake(){discard();if(!host.pending())host.end();}
 void end(){discard();host.end();}
 void unloaded(int scene){if(bound&&host.inScene(owner,scene))end();}
 template<class Identifier> bool begin(Object level,Object progress,Identifier identifier,int slot){
  discard();
  const uint64_t ticket=generation;
  // The UI copies these into the accepted playing payload in Begin, not Arm.
  host.configure([this,ticket]{return owns(ticket)&&host.live(owner);},
                 [this,ticket]{if(owns(ticket))invalidated();});
  if(!host.begin(identifier,slot))return false;
  try{host.acquire(owner,level,progress);bound=true;return true;}
  catch(const std::exception &e){host.error("bind",e.what());end();return false;}
 }
 bool tick(Entry entry,Object object){
  if(!bound)return false;
  // Only Progress's existing pre/post-native gates discover the threshold.
  // Until frozen/recovering, the other hot hooks do ZERO adapter/Unity work.
  // Once held, all entries still perform the exact owner and scene checks below.
  if(entry!=Entry::Progress&&!frozen&&!recovering)return false;
  if(!host.matches(owner,entry,object))return false;
  if(!host.live(owner)){end();return false;}
  if(recovering)return !restore();
  if(frozen){
   if(!triggering&&!quitClaimed&&!host.blocking()){
    // blocking() may synchronously invalidate/restore this owner.
    if(bound&&!recovering)invalidated();
    return holding();
   }
   enforce();return true;
  }
  if(triggering)return false;
  const uint64_t ticket=generation;
  if(!host.eligible(owner)||!host.due(host.time(owner))||!owns(ticket))return false;
  triggering=true;
  bool attached=false;
  try{attached=host.trigger([this,ticket]{return freeze(ticket);},[this,ticket]{close(ticket);});}
  catch(const std::exception &e){host.error("present",e.what());}
  if(!owns(ticket))return false; // End/invalidation/replacement may have reentered.
  triggering=false;
  if(!attached&&frozen){if(!recovering)invalidated();return holding();}
  return frozen;
 }
 // Declared BEFORE StoryPauseScope so its destructor runs LAST, including unwind.
 // A nested trigger cannot leave canPause restored by the preexisting story scope.
 void fence(){if(bound&&frozen&&host.live(owner))enforce();}
};
} // namespace songinterruption

#ifndef PM_SONG_INTERRUPTION_GAMEPLAY_TEST
namespace songinterruption {
struct NativeHost {
 using Object=P;
 enum Root { Level,Progress,Info,Judge,Audio,Notes,UnityAudio,RootCount };
 struct Owner { uint32_t roots[RootCount]{};int scene=0; };
 struct Snapshot {
  bool canPause=false,canLevelOver=false,stopJudge=false,isPlaying=false;
  float now=0,audioTime=0,judgeTime=0,wrapperTime=0,internalTime=0,startTime=0,clipTime=0;
 };
 static P object(const Owner&o,Root which){return o.roots[which]?R().gchandle_get_target(o.roots[which]):nullptr;}
 static int sceneValue(P boxed){
  auto&r=R();P type=r.type("UnityEngine.SceneManagement","Scene");uint32_t alignment=0;
  if(!boxed||r.object_get_class(boxed)!=type||!r.class_is_valuetype(type)||r.class_value_size(type,&alignment)!=sizeof(int))
   throw std::runtime_error("Unexpected interruption Scene value");
  int value=0;memcpy(&value,r.object_unbox(boxed),sizeof(value));return value;
 }
 static int levelScene(P level){auto&r=R();return sceneValue(r.call(r.call(level,"get_gameObject"),"get_scene"));}
 static void keep(Owner&o,Root which,P value){
  auto&r=R();if(!r.alive(value))throw std::runtime_error("Interruption owner component unavailable");
  if(o.roots[which]){if(object(o,which)!=value)throw std::runtime_error("Interruption component replaced");return;}
  o.roots[which]=r.gchandle_new(value,false);
  if(!o.roots[which])throw std::runtime_error("Interruption GC root unavailable");
 }
 void acquire(Owner&o,P level,P pc){
  keep(o,Level,level);keep(o,Progress,pc);o.scene=levelScene(level);
  if(!live(o))throw std::runtime_error("Interruption level/scene mismatch");
 }
 void release(Owner&o){
  for(auto &root:o.roots){if(root)R().gchandle_free(root);root=0;}
 }
 bool live(const Owner&o){
  try{auto&r=R();P level=object(o,Level),pc=object(o,Progress);
   if(!r.alive(level)||level!=currentLevel||!r.alive(pc)||r.get<P>(level,"progressControl")!=pc||
      levelScene(level)!=o.scene||sceneValue(r.stat(r.type("UnityEngine.SceneManagement","SceneManager"),"GetActiveScene"))!=o.scene)return false;
   // Once captured, replaced/destroyed children cannot inherit the old hold.
   for(Root which:{Info,Judge,Audio,Notes,UnityAudio})if(o.roots[which]&&!r.alive(object(o,which)))return false;
   if(o.roots[Info]&&r.get<P>(pc,"levelInformation")!=object(o,Info))return false;
   if(o.roots[Judge]&&r.get<P>(pc,"judgeControl")!=object(o,Judge))return false;
   if(o.roots[Audio]&&r.get<P>(pc,"audioSource")!=object(o,Audio))return false;
   if(o.roots[Notes]&&r.get<P>(object(o,Judge),"noteUpdateManager")!=object(o,Notes))return false;
   if(o.roots[UnityAudio]&&r.get<P>(object(o,Audio),"audioSource")!=object(o,UnityAudio))return false;
   return true;
  }catch(const std::exception&){return false;}
 }
 bool inScene(const Owner&o,int scene){return o.scene==scene;}
 bool matches(const Owner&o,Entry entry,P value){
  try{auto&r=R();P pc=object(o,Progress);if(entry==Entry::Progress)return pc==value;
   if(!r.alive(pc))return false;
   if(entry==Entry::Judge&&o.roots[Judge])return object(o,Judge)==value;
   if(entry==Entry::Audio&&o.roots[Audio])return object(o,Audio)==value;
   if(entry==Entry::Notes&&o.roots[Notes])return object(o,Notes)==value;
   P judge=r.get<P>(pc,"judgeControl");
   if(entry==Entry::Judge)return judge==value;
   if(entry==Entry::Audio)return r.get<P>(pc,"audioSource")==value;
   return r.alive(judge)&&r.get<P>(judge,"noteUpdateManager")==value;
  }catch(const std::exception&){return false;}
 }
 bool eligible(const Owner&o){
  auto&r=R();P pc=object(o,Progress),info=r.get<P>(pc,"levelInformation"),audio=r.get<P>(pc,"audioSource");
  return !pmsecretcourse::active()&&!levelOverStarted&&r.alive(info)&&r.alive(audio)&&
   r.get<bool>(info,"chartLoaded")&&r.get<bool>(info,"levelBegan")&&!r.get<bool>(info,"levelOver")&&
   r.get<bool>(pc,"isPlaying")&&!r.get<bool>(pc,"leave")&&!r.get<bool>(pc,"levelBreak")&&
   !r.get<bool>(pc,"_inChallengeMode")&&r.get<bool>(audio,"loadOver")&&r.get<bool>(audio,"playFlag");
 }
 double time(const Owner&o){return R().get<float>(object(o,Progress),"nowTime");}
 void capture(Owner&o,Snapshot&s){
  auto&r=R();P pc=object(o,Progress);
  keep(o,Info,r.get<P>(pc,"levelInformation"));keep(o,Judge,r.get<P>(pc,"judgeControl"));
  keep(o,Audio,r.get<P>(pc,"audioSource"));keep(o,Notes,r.get<P>(object(o,Judge),"noteUpdateManager"));
  keep(o,UnityAudio,r.get<P>(object(o,Audio),"audioSource"));
  P info=object(o,Info),judge=object(o,Judge),audio=object(o,Audio);
  // Preflight before mutations, including the non-boolean rollback contracts.
  r.resolve(r.object_get_class(audio),"Pause");r.resolve(r.object_get_class(audio),"Seek",{"System.Single"});
  r.resolve(r.object_get_class(audio),"PlayScheduled",{"System.Double"});
  s.canPause=r.get<bool>(info,"canPause");s.canLevelOver=r.get<bool>(info,"canLevelOver");
  s.stopJudge=r.get<bool>(judge,"stopJudge");s.isPlaying=r.get<bool>(pc,"isPlaying");
  s.now=r.get<float>(pc,"nowTime");s.audioTime=r.get<float>(pc,"audioTime");s.judgeTime=r.get<float>(judge,"nowTime");
  s.wrapperTime=r.get<float>(audio,"time");s.internalTime=r.get<float>(audio,"internalTime");s.startTime=r.get<float>(audio,"startTime");
  s.clipTime=r.unbox<float>(r.call(object(o,UnityAudio),"get_time"));
  if(!std::isfinite(s.now)||!std::isfinite(s.audioTime)||!std::isfinite(s.clipTime)||s.clipTime<0)
   throw std::runtime_error("Interruption clock unavailable");
 }
 void clocks(const Owner&o,const Snapshot&s){
  auto&r=R();P pc=object(o,Progress),audio=object(o,Audio);
  r.put(pc,"nowTime",s.now);r.put(pc,"audioTime",s.audioTime);r.put(object(o,Judge),"nowTime",s.judgeTime);
  r.put(audio,"time",s.wrapperTime);r.put(audio,"internalTime",s.internalTime);r.put(audio,"startTime",s.startTime);
 }
 void hold(const Owner&o,const Snapshot&s){
  auto&r=R();r.put(object(o,Info),"canPause",false);r.put(object(o,Info),"canLevelOver",false);
  r.put(object(o,Judge),"stopJudge",true);r.put(object(o,Progress),"isPlaying",false);clocks(o,s);
 }
 void pause(const Owner&o){R().call(object(o,Audio),"Pause");}
 void repauseIfPlaying(const Owner&o){
  if(R().get<bool>(object(o,Audio),"playFlag"))pause(o);
 }
 void resume(const Owner&o,const Snapshot&s){
  auto&r=R();P audio=object(o,Audio),pc=object(o,Progress),info=object(o,Info);
  for(Root which:{Info,Judge,Audio,Notes,UnityAudio})if(!r.alive(object(o,which)))
   throw std::runtime_error("Interruption rollback component unavailable");
  // 4.0.4: Seek 0x15C8FD8 resets the physical cursor AND DSP history; then
  // PlayScheduled 0x15C9184 schedules the source and resets scheduleTerminate.
  // SetPlayFlag.MoveNext 0x15C9B68 restores playFlag through the native coroutine.
  // Do not use Play(false), Stop (releases the clip), or bool-only fake resume.
  float clip=s.clipTime;double immediate=0;
  r.call(audio,"Seek",{"System.Single"},{&clip});
  r.call(audio,"PlayScheduled",{"System.Double"},{&immediate});
  r.put(pc,"nowTime",s.now);r.put(pc,"audioTime",s.audioTime);r.put(object(o,Judge),"nowTime",s.judgeTime);
  r.put(audio,"time",s.wrapperTime); // Do NOT overwrite the rebuilt DSP/startTime/internalTime.
  r.put(info,"canPause",s.canPause);r.put(info,"canLevelOver",s.canLevelOver);
  r.put(object(o,Judge),"stopJudge",s.stopJudge);r.put(pc,"isPlaying",s.isPlaying);
 }
 void configure(std::function<bool()>valid,std::function<void()>invalidated){
  PMSetSongInterruptionHostGuard(^BOOL{return valid();},^{invalidated();});
 }
 bool pending(){return PMSongInterruptionPending();}
 bool begin(NSString*identifier,int slot){return PMBeginSongInterruption(identifier,slot);}
 void end(){PMEndSongInterruption();}
 bool due(double value){return PMSongInterruptionDue(value);}
 bool blocking(){return PMSongInterruptionBlocking();}
 bool trigger(std::function<bool()>freeze,std::function<void()>quit){
  return PMTriggerSongInterruption(^BOOL{return freeze();},^{quit();});
 }
 void protect(){guard.store(true);}
 void quit(){
  // ONLY the UI's validated user action reaches here. No timer, teardown,
  // invalidation or test process invokes this exit fallback.
  try{R().stat(R().type("UnityEngine","Application"),"Quit");}
  catch(const std::exception&e){diagf("Interruption user quit: %s",e.what());}
  std::exit(EXIT_SUCCESS);
 }
 void error(const char*stage,const char*message){diagf("Song interruption %s: %s",stage,message);}
};
NativeHost nativeHost;
Gameplay<NativeHost> gameplay(nativeHost);
// All copied UI callbacks contain NO borrowed scene pointers. Begin configures
// numeric-generation guards before the UI copies them into its playing payload.
// Old invalidation/freeze/quit callbacks therefore cannot mutate a newer owner.
bool tick(Entry entry,P self){
 try{return gameplay.tick(entry,self);}
 catch(const std::exception&e){diagf("Song interruption entry: %s",e.what());return gameplay.holding();}
}
struct PauseFence { ~PauseFence(){try{gameplay.fence();}catch(const std::exception&e){diagf("Song interruption fence: %s",e.what());}} };
} // namespace songinterruption
#endif
