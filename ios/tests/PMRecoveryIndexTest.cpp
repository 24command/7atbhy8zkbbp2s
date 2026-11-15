#include "../PhiMod/Core/PMIntervalIndex.hpp"
#include "../PhiMod/Core/PMRPEVisibility.hpp"
#include "../PhiMod/Core/PMRPEGeometry.hpp"
#include <cassert>
#include <cstdio>
#include <fstream>
#include <set>
#include <random>
#include <string>
struct Note{double start,end,floor,tail;int hold;};
void check(const std::vector<Note>&notes,const std::vector<double>&times,double origin,double axis,double world,size_t&scanned,size_t&retrieved){
 using namespace phimod;std::vector<IntervalIndex::Entry>floors,due;
 for(size_t i=0;i<notes.size();++i){const auto&n=notes[i];floors.push_back({std::min(n.floor,n.tail),std::max(n.floor,n.tail),i});due.push_back({n.start-2,n.end+.25,i});}
 IntervalIndex spatial,judgement;spatial.reset(floors);judgement.reset(due);
 for(double time:times){double current=time*2.6666666666666665,low,high;assert(recoveryFloorWindow(current,origin,0,axis,world,low,high));std::set<size_t>found;
  auto emit=[&](size_t i){if(notes[i].end>=time-.25)found.insert(i);};spatial.query(low,high,emit);judgement.query(time,time,emit);
  for(size_t i=0;i<notes.size();++i){const auto&n=notes[i];if(n.end<time-.25)continue;++scanned;bool isDue=time>=n.start-2&&time<=n.end+.25;
   auto g=rpeGeometry(float(n.floor-current),float(n.tail-current),0,1,0,1,float(world),n.hold&&time>=n.start);
   // Above/below, arbitrary offscreen origin, active long Holds, zero scroll
   // and distant notes: no candidate accepted by precise reference may be lost.
   bool near=rpeVisualNear({0,origin,1,0,0,axis},0,g.head,n.hold?g.tail:g.head,1)||rpeVisualNear({0,origin,1,0,0,axis},0,-g.head,n.hold?-g.tail:-g.head,1);
   if(near||isDue)assert(found.count(i));
  }
  retrieved+=found.size();
 }
}
void transformedIndexTest(){
 using namespace phimod;std::mt19937 rng(71);size_t reference=0,retrieved=0;
 for(double angle:{0.,.3,1.5707963267948966,2.5,3.141592653589793})for(double speed:{-999.,-1.,1.,1.2,999.})for(double world:{-10.,.1,10.}){
  RpePlanePose pose{30,-60,std::cos(angle),std::sin(angle),-std::sin(angle),std::cos(angle)};double current=1300,lo,hi;
  assert(recoveryTransformedFloorWindow(current,pose.x,pose.y,pose.xx,pose.xy,pose.yx,pose.yy,10,std::abs(speed),world,lo,hi));
  std::vector<IntervalIndex::Entry>intervals;std::vector<Note>notes;std::vector<float>xs;
  for(int i=0;i<2000;++i){double f=current+(int(rng()%200000)-100000)/100.,tail=f+(i%4==0?(int(rng()%100000)-50000)/100.:0);notes.push_back({100,120,f,tail,i%4==0});xs.push_back(float(int(rng()%2001)-1000)/100);intervals.push_back({std::min(f,tail),std::max(f,tail),size_t(i)});}
  IntervalIndex index;index.reset(intervals);std::set<size_t>hits;index.query(lo,hi,[&](size_t i){hits.insert(i);});reference+=notes.size();retrieved+=hits.size();
  for(size_t i=0;i<notes.size();++i){auto&n=notes[i];auto g=rpeGeometry(float(n.floor-current),float(n.tail-current),0,float(speed),0,1,float(world),false);for(float sign:{-1.f,1.f})if(rpeVisualNear(pose,xs[i],sign*g.head,sign*(n.hold?g.tail:g.head),1))assert(hits.count(i));}
 }
 double low,high;assert(!recoveryTransformedFloorWindow(0,0,0,1,0,0,0,10,1,10,low,high));assert(!recoveryTransformedFloorWindow(0,0,0,1,0,0,1,10,0,10,low,high));
 printf("ROTATED/REVERSE reference=%zu retrieved=%zu; no visible cap/hold interval omitted\n",reference,retrieved);
}
int main(int argc,char**argv){transformedIndexTest();size_t scanned=0,retrieved=0;
 std::vector<Note>synthetic;std::mt19937 rng(42);for(int i=0;i<12000;++i){double start=i*.07,end=start+(i%4==0?30:0),floor=double(int(rng()%20000)-10000)/10,tail=floor+(i%4==0?40:0);synthetic.push_back({start,end,floor,tail,i%4==0});}
 std::vector<double>times{-3,0,1,20,100,500,800,400,20,0};for(double origin:{0.,-60.,60.})for(double axis:{1.,-1.,.001})for(double speed:{1.,10.,-10.})check(synthetic,times,origin,axis,speed,scanned,retrieved);
 double lo,hi;assert(!phimod::recoveryFloorWindow(0,0,.01,1,10,lo,hi));assert(!phimod::recoveryFloorWindow(0,0,0,1,0,lo,hi));
 // Exact inclusive interval boundary and negative intervals.
 phimod::IntervalIndex tree;tree.reset({{-4,-1,0},{0,0,1},{1,3,2}});std::set<size_t>hits;tree.query(0,0,[&](size_t i){hits.insert(i);});assert(hits==std::set<size_t>{1});tree.reset({});hits.clear();tree.query(-10,10,[&](size_t i){hits.insert(i);});assert(hits.empty());
 if(argc>1){std::ifstream file(argv[1]);size_t charts;file>>charts;size_t actualScanned=0,actualRetrieved=0;for(size_t c=0;c<charts;++c){size_t n;file>>n;std::vector<Note>notes(n);double end=0;for(auto&v:notes){file>>v.start>>v.end>>v.floor>>v.tail>>v.hold;end=std::max(end,v.end);}assert(file.good());std::vector<double>samples;for(double t=-3;t<end+1;t+=1)samples.push_back(t);for(int i=0;i<1200;++i)samples.push_back(i/120.);check(notes,samples,-3.9,1,10,actualScanned,actualRetrieved);}printf("PACKAGE reference candidates=%zu indexed=%zu reduction=%.2f%%\n",actualScanned,actualRetrieved,100.*(1.-double(actualRetrieved)/actualScanned));}
 puts("PASS conservative index vs full reference: long holds, distant notes, reversed axes, offscreen lines, backwards seeks, all due notes; unsupported transforms fallback");
}
