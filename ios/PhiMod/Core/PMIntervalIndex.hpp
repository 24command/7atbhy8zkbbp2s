#pragma once
#include <algorithm>
#include <cmath>
#include <cstddef>
#include <limits>
#include <vector>
namespace phimod {
// Immutable interval tree. Query returns a conservative superset only; the
// renderer retains its exact lifetime/alpha/geometry tests for each result.
class IntervalIndex {
public:
 struct Entry{double low,high;size_t id;};
private:
 struct Node{Entry entry;double maxHigh;int left=-1,right=-1;};
 std::vector<Node>nodes;int root=-1;
 int build(std::vector<Entry>&v,size_t begin,size_t end){if(begin==end)return -1;size_t mid=begin+(end-begin)/2;int here=int(nodes.size());nodes.push_back({v[mid],v[mid].high});int l=build(v,begin,mid),r=build(v,mid+1,end);nodes[here].left=l;nodes[here].right=r;if(l>=0)nodes[here].maxHigh=std::max(nodes[here].maxHigh,nodes[l].maxHigh);if(r>=0)nodes[here].maxHigh=std::max(nodes[here].maxHigh,nodes[r].maxHigh);return here;}
 template<class Emit>void query(int n,double low,double high,Emit&emit)const{if(n<0||nodes[n].maxHigh<low)return;const auto&node=nodes[n];query(node.left,low,high,emit);if(node.entry.low>high)return;if(node.entry.high>=low)emit(node.entry.id);query(node.right,low,high,emit);}
public:
 void reset(std::vector<Entry>entries){nodes.clear();nodes.reserve(entries.size());std::stable_sort(entries.begin(),entries.end(),[](const auto&a,const auto&b){return a.low<b.low;});root=build(entries,0,entries.size());}
 template<class Emit>void query(double low,double high,Emit emit)const{if(low>high)std::swap(low,high);query(root,low,high,emit);}
};
inline bool recoveryFloorWindow(double floor,double originY,double axisXY,double axisYY,double world,double&low,double&high){
 // Non-axis-aligned lines and zero/invalid scales use the full reference scan.
 if(!std::isfinite(floor)||!std::isfinite(originY)||axisXY!=0||!std::isfinite(axisYY)||!std::isfinite(world)||std::abs(axisYY*world)<1e-9)return false;
 double radius=(11.+std::abs(originY))/std::abs(axisYY*world);
 // Account for the existing float geometry arithmetic (the index is double).
 radius+=std::max(.001,std::abs(floor)*.00001);
 low=floor-radius;high=floor+radius;return std::isfinite(low)&&std::isfinite(high);
}
}
