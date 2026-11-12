#pragma once
#include <map>
namespace phimod {
// Cache an immutable chart calculation at its playback timestamp. A backward
// seek is a new query too; clear when replacing the chart, not only at song end.
template<class Key,class Value> class FrameCache {
 struct Entry{double time;Value value;};std::map<Key,Entry>values;
public:
 template<class Compute> Value get(Key key,double time,Compute compute){auto it=values.find(key);if(it!=values.end()&&it->second.time==time)return it->second.value;Value value=compute();values[key]={time,value};return value;}
 void clear(){values.clear();}
};
}
