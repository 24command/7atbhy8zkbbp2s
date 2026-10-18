#include "../PhiMod/Core/PMFlowCore.hpp"
#include "../PhiMod/Core/PMGameplayCore.hpp"
#include <iostream>
#include <limits>
using namespace phimod;
static int checks=0;
#define CHECK(x) do{++checks;if(!(x))throw std::runtime_error("Failed: " #x);}while(0)
int main(){try{
 FailureDelay delay;
 CHECK(!delay.started());CHECK(!delay.ready(100));delay.begin(10);CHECK(delay.started());
 CHECK(!delay.ready(10));CHECK(!delay.ready(11.499f));CHECK(delay.ready(11.5f));
 delay.begin(11);CHECK(delay.ready(11.5f)); // repeated ticks must not reset the timer
 CHECK(!delay.ready(9));CHECK(!delay.ready(std::numeric_limits<float>::quiet_NaN()));
 delay.reset();CHECK(!delay.started());
 for(float bad:{-1.f,std::numeric_limits<float>::infinity(),std::numeric_limits<float>::quiet_NaN()}){
  bool rejected=false;try{delay.begin(bad);}catch(const std::invalid_argument&){rejected=true;}CHECK(rejected);CHECK(!delay.started());
 }
 CHECK(resultStep(0)==1);CHECK(resultStep(1)==2);CHECK(resultStep(-1)==0);CHECK(resultStep(2)==0);
 // Coroutine lifecycle: yield once, render once, never replay after stop.
 int state=0,yields=0,renders=0;
 for(int i=0;i<6;++i){int step=resultStep(state);if(step==1){++yields;state=1;}else{state=-1;if(step==2)++renders;}}
 CHECK(yields==1);CHECK(renders==1);
 Session hp;hp.setCoverage({true,true,true,true,true,true,true});Options o;o.hpEnabled=true;o.hpMax=1;o.challenge=1;
 hp.request(o);CHECK(hp.begin({}));hp.registerNote({1,1,0,1});CHECK(hp.observe(1,0,Rating::Miss));
 CHECK(hp.pendingAction(false,false,false)==Action::None);
 CHECK(hp.pendingAction(true,true,false)==Action::None);CHECK(hp.pendingAction(true,false,true)==Action::None);
 CHECK(hp.pendingAction(true,false,false)==Action::TrackLost); // loss takes precedence over retry
 CHECK(hp.pendingAction(true,false,false)==Action::TrackLost); // failed managed transition not consumed
 hp.acknowledgeAction(Action::TrackLost);CHECK(hp.pendingAction(true,false,false)==Action::None);
 Session retry;retry.setCoverage({true,true,true,true,true,true,true});o=Options{};o.challenge=1;
 retry.request(o);CHECK(retry.begin({}));retry.registerNote({1,1,0,1});CHECK(retry.observe(1,.1f,Rating::Good));
 CHECK(retry.pendingAction(true,false,false)==Action::Retry);CHECK(retry.pendingAction(true,false,false)==Action::Retry);
 retry.acknowledgeAction(Action::Retry);CHECK(retry.pendingAction(true,false,false)==Action::None);
 // AP/FC alone preserves native scores; only the configured assisted modes latch protection.
 CHECK(retry.allowRecordWrite());
 o.autoplay=true;retry.request(o);CHECK(retry.sync());CHECK(!retry.allowRecordWrite());
 std::cout<<"PASS: "<<checks<<" flow / transition checks\n";return 0;
 }catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}}
