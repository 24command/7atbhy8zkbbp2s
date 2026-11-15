#pragma once
#include <cstdint>
#include <string>
#include <tuple>
namespace phimod {
// Scroll position/selected index are deliberately not global invalidators.
// List version catches replacement/sorting even when the count stays equal.
struct SelectorRowKey {
 uintptr_t owner=0,items=0;int version=0,count=0,slot=-1;uint64_t revision=0;std::string logical;
 bool operator==(const SelectorRowKey&b)const{return std::tie(owner,items,version,count,slot,revision,logical)==std::tie(b.owner,b.items,b.version,b.count,b.slot,b.revision,b.logical);}
};
class SelectorRowRefresh {
 SelectorRowKey key_;bool ready_=false;uintptr_t selected_=0;
public:
 bool full(const SelectorRowKey&key)const{return !ready_||!(key_==key);}
 uintptr_t previousSelected()const{return selected_;}
 void commit(const SelectorRowKey&key,uintptr_t selected){key_=key;selected_=selected;ready_=true;}
 void invalidate(){ready_=false;}
 void reset(){ready_=false;selected_=0;key_={};}
};
}
