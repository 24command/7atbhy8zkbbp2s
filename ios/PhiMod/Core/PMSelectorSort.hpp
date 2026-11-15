#pragma once
#include <cstdint>
#include <cmath>
namespace phimod {
// Same two level-dependent sort modes as 4.0.3 SongSelector.SetLevel.
inline bool levelDependentSort(int sortType){return sortType==2||sortType==3;}
class DeferredSelectorSort {
 uintptr_t owner_=0;
public:
 void request(uintptr_t owner){owner_=owner;}
 void clear(){owner_=0;}
 bool pending(uintptr_t owner)const{return owner&&owner_==owner;}
 bool ready(uintptr_t owner,int sortType,bool touching,float speed)const{return pending(owner)&&levelDependentSort(sortType)&&!touching&&std::isfinite(speed)&&std::fabs(speed)<.05f;}
};
}
