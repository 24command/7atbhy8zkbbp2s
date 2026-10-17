#include "../PhiMod/Core/PMChartCore.hpp"
#include "../PhiMod/Core/PMGameplayCore.hpp"
#include <iostream>
#include <limits>
#include <random>
using namespace phimod;
static int checks=0;
#define CHECK(x) do { ++checks; if(!(x))throw std::runtime_error("Failed: " #x); } while(0)
template<class F>void rejects(F f){bool rejected=false;try{f();}catch(const std::exception &){rejected=true;}CHECK(rejected);}
static Coverage ready(){return {true,true,true,true,true,true,true};}
static Options assist(){Options o;o.judge=true;return o;}
int main(){
 try {
  Options o;o.validate();o.perfectMs=181;rejects([&]{o.validate();});o=Options{};o.radius=std::numeric_limits<float>::quiet_NaN();rejects([&]{o.validate();});
  for(int field=0;field<7;++field){Session s;Coverage c=ready();switch(field){case 0:c.frame=false;break;case 1:c.lifecycle=false;break;case 2:c.recordUpdate=false;break;case 3:c.recordSet=false;break;case 4:c.ranking=false;break;case 5:c.persistence=false;break;case 6:c.result=false;break;}s.setCoverage(c);s.request(assist());CHECK(!s.begin({}));CHECK(s.phase()==Phase::Idle);}
  Session normal;CHECK(normal.begin({}));CHECK(normal.allowRecordWrite());normal.request(assist());CHECK(!normal.sync());CHECK(normal.windows().perfect==.08f);normal.result();normal.finishResult();
  Session s;s.setCoverage(ready());o=assist();o.perfectMs=100;o.goodMs=250;s.request(o);CHECK(s.begin({.07f,.15f,.19f}));CHECK(!s.allowRecordWrite());CHECK(std::fabs(s.windows().bad-.29f)<.00001f);
  for(int feature=0;feature<6;++feature){Session protectedSession;protectedSession.setCoverage(ready());Options protectedOptions{};if(feature==0)protectedOptions.judge=true;if(feature==1)protectedOptions.autoplay=true;if(feature==2)protectedOptions.clearNoise=true;if(feature==3)protectedOptions.fullscreen=true;if(feature==4)protectedOptions.accuracyOnly=true;if(feature==5)protectedOptions.unified=1;protectedSession.request(protectedOptions);CHECK(protectedSession.begin({}));CHECK(!protectedSession.allowRecordWrite());}
  for(int feature=0;feature<3;++feature){Session unprotectedSession;unprotectedSession.setCoverage(ready());Options unprotectedOptions{};if(feature==0)unprotectedOptions.noise=true;if(feature==1)unprotectedOptions.hpEnabled=true;if(feature==2)unprotectedOptions.challenge=1;unprotectedSession.request(unprotectedOptions);CHECK(unprotectedSession.begin({}));CHECK(unprotectedSession.allowRecordWrite());}
  Session challengeRetry;challengeRetry.setCoverage(ready());o=Options{};o.challenge=1;challengeRetry.request(o);CHECK(challengeRetry.begin({}));challengeRetry.registerNote({31,0,0,1});CHECK(challengeRetry.observe(31,0,Rating::Good));CHECK(challengeRetry.takeAction(true,false,false)==Action::Retry);CHECK(challengeRetry.allowRecordWrite());
  rejects([&]{s.setCoverage({});});rejects([&]{s.begin({});});rejects([&]{s.finishResult();});
  s.request(Options{});CHECK(s.sync());CHECK(std::fabs(s.windows().perfect-.07f)<.00001f);CHECK(!s.allowRecordWrite());s.result();CHECK(!s.allowRecordWrite());s.finishResult();CHECK(s.allowRecordWrite());CHECK(s.serial()==1);
  Session hp;hp.setCoverage(ready());o=Options{};o.hpEnabled=true;o.hpMax=40;hp.request(o);CHECK(hp.begin({}));hp.registerNote({1,1,0,1});hp.registerNote({2,2,0,1});hp.registerNote({3,3,0,1,true});CHECK(hp.observe(1,0,Rating::Miss));CHECK(hp.hp()==15);CHECK(!hp.observe(1,0,Rating::Miss));CHECK(!hp.observe(3,0,Rating::Miss));CHECK(!hp.observe(999,0,Rating::Miss));CHECK(!hp.observe(2,std::numeric_limits<float>::max(),Rating::Miss));CHECK(!hp.observe(2,0,static_cast<Rating>(4)));CHECK(hp.observe(2,.01f,Rating::Miss));CHECK(hp.hp()==0&&hp.trackLost());CHECK(hp.takeAction(false,false,false)==Action::None);CHECK(hp.takeAction(true,true,false)==Action::None);CHECK(hp.takeAction(true,false,false)==Action::TrackLost);CHECK(hp.takeAction(true,false,false)==Action::None);CHECK(!hp.creditOnce(3));CHECK(hp.samples().size()==2);CHECK(std::fabs(hp.samples()[1].offsetMs-10)<.0001f);rejects([&]{hp.registerNote({2,2,0,1});});
  Session resize;resize.setCoverage(ready());o=Options{};o.hpEnabled=true;o.hpMax=100;resize.request(o);CHECK(resize.begin({}));resize.registerNote({1,0,0,1});CHECK(resize.observe(1,0,Rating::Miss));CHECK(resize.hp()==75);o.hpMax=200;resize.request(o);CHECK(resize.sync());CHECK(resize.hp()==150);
  for(int challenge:{1,2}){Session c;c.setCoverage(ready());o=Options{};o.challenge=challenge;c.request(o);CHECK(c.begin({}));c.registerNote({1,0,0,1});CHECK(c.observe(1,0,Rating::Good));CHECK(c.takeAction(true,false,false)==(challenge==1?Action::Retry:Action::None));CHECK(c.takeAction(true,false,false)==Action::None);c.registerNote({2,0,0,1});CHECK(c.observe(2,0,Rating::Bad));CHECK(c.takeAction(true,false,false)==Action::Retry);}
  Session hold;hold.setCoverage(ready());o=Options{};o.autoplay=true;hold.request(o);CHECK(hold.begin({}));hold.registerNote({1,1,2,3});CHECK(hold.deferHold(1,0,{0,0,0},true,1));CHECK(hold.deferHold(1,0,{0,0,0},true,2));CHECK(hold.dueHolds(2.999f,true).empty());auto tail=hold.dueHolds(3,false);CHECK(tail.size()==1&&tail[0].code==1);CHECK(hold.dueHolds(4,true).empty());CHECK(!hold.creditOnce(1));CHECK(!hold.allowRecordWrite());hold.failClosed();CHECK(!hold.shouldApplyGameplay());CHECK(!hold.sync());hold.result();CHECK(!hold.allowRecordWrite());hold.finishResult();CHECK(hold.allowRecordWrite());
  Session split;split.setCoverage(ready());o=Options{};o.autoplay=true;split.request(o);CHECK(split.begin({}));split.registerNote({10,1,0,1});split.registerNote({11,2,2,3});CHECK(split.noteType(10)==1&&split.noteType(11)==3);CHECK(!split.deferHold(10,0,{0,0,0},true,1));CHECK(split.deferHold(11,0,{0,0,0},true,2));
  Session flush;flush.setCoverage(ready());o=Options{};o.autoplay=true;flush.request(o);CHECK(flush.begin({}));flush.registerNote({21,1,5,3});CHECK(flush.deferHold(21,3,{1,2,3},true,1));auto forced=flush.flushPendingHolds();CHECK(forced.size()==1&&forced[0].code==21&&forced[0].offset==3);CHECK(flush.flushPendingHolds().empty());CHECK(!flush.creditOnce(21));
  CHECK(accuracyScore(10,0,10)==1000000.f);CHECK(accuracyScore(0,10,10)==650000.f);rejects([]{accuracyScore(1,1,1);});rejects([]{accuracyScore(0,0,0);});CHECK(convertedNoteType(3,0)==3);CHECK(convertedNoteType(1,4)==4);rejects([]{convertedNoteType(1,5);});
  auto united=noiseUnion({{0,0,2,1},{1,0,3,1}});CHECK(united.size()==1&&united[0].right==3);rejects([]{noiseUnion({{0,0,std::numeric_limits<float>::infinity(),1}});});
  std::mt19937 random(42); // integer geometry: compare exact occupied cells and nonoverlap
  for(int trial=0;trial<100;++trial){std::vector<Rect> input;bool occupied[10][10]={};for(int k=0;k<12;++k){int l=random()%9,b=random()%9,r=l+1+random()%(10-l),t=b+1+random()%(10-b);input.push_back({float(l),float(b),float(r),float(t)});for(int x=l;x<r;++x)for(int y=b;y<t;++y)occupied[x][y]=true;}auto result=noiseUnion(input);for(int x=0;x<10;++x)for(int y=0;y<10;++y){int overlap=0;for(auto rect:result)if(x>=rect.left&&x<rect.right&&y>=rect.bottom&&y<rect.top)++overlap;CHECK(overlap==int(occupied[x][y]));}}

  CHECK(autoPlan(true,false,true,false,false,0,1).kind==AutoPlan::Kind::Wait);
  CHECK(autoPlan(true,false,true,false,false,1,1).replaceClock);
  CHECK(!autoPlan(true,false,true,true,true,2,1).replaceClock);
  CHECK(autoPlan(true,false,true,true,true,2,1).safeFrames==2);
  CHECK(autoPlan(true,true,true,false,false,2,1).kind==AutoPlan::Kind::Original);
  CHECK(autoPlan(true,false,false,false,false,2,1).kind==AutoPlan::Kind::Original);
  HoldGrace grace;CHECK(!grace.inject(1,1,0,{0},.1f,false));CHECK(grace.inject(1,1.05f,0,{4},.1f,false));
  CHECK(!grace.inject(1,1.15f,0,{4},.1f,false));CHECK(!grace.inject(1,.5f,0,{4},.1f,false));
  CHECK(!grace.inject(1,1.01f,0,{4},.1f,false));
  auto spatial=fullScreenOverrides({{1,1,0,1},{2,3,0,1}},{{1,5},{2,6}},1,9,true);
  CHECK(spatial.size()==1&&spatial[0].originalX==5&&spatial[0].replacementX==9);
  CHECK(chartUtf16("ASCII chart")==u"ASCII chart");
  CHECK(chartUtf16("\xE8\xB0\xB1\xF0\x9F\x8E\xB5")==u"\u8C31\U0001F3B5");
  CHECK(chartUtf16(std::string("a\0b",3))==std::u16string(u"a\0b",3));
  for(auto invalid:{"\x80","\xC0\xAF","\xED\xA0\x80","\xF4\x90\x80\x80","\xF0\x9F"})rejects([&]{chartUtf16(invalid);});
  CHECK(rpeFloor({},2,9)==9);
  std::vector<RpeFloorSegment> floors{{0,2,2,0},{2,4,3,4}};
  CHECK(rpeFloor(floors,-1,99)==-2);CHECK(rpeFloor(floors,1,99)==2);CHECK(rpeFloor(floors,2,99)==4);CHECK(rpeFloor(floors,3,99)==7);
  CHECK(rpeControl({},2)==1);CHECK(rpeControl({{0,2,1,3}},-1)==1);CHECK(rpeControl({{0,2,1,3}},1)==2);CHECK(rpeControl({{0,2,1,3}},3)==3);
  auto geometry=rpeGeometry(2,5,1,1,0,1,2,false);CHECK(geometry.head==2&&geometry.tail==8);
  auto started=rpeGeometry(2,5,3,1,0,1,2,true);CHECK(started.head==0&&started.tail==4);
  auto above=rpeHoldLayout(geometry,2,0,false),below=rpeHoldLayout(geometry,2,0,true);
  CHECK(above.origin==2&&above.scale==3);CHECK(below.origin==-2&&below.scale==-3);
  auto hud=rpeHudOffset(10,20,2,3,1,1,0);CHECK(hud.x==2&&hud.y==3);
  std::cout<<"PASS: "<<checks<<" gameplay core checks\n";return 0;
 }catch(const std::exception &e){std::cerr<<e.what()<<'\n';return 1;}
}
