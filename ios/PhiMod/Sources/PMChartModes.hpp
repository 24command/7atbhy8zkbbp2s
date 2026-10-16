#pragma once
#include "PMIL2CPP.hpp"
#include "../Core/PMModeCore.hpp"
namespace pmmodes {
using pmbridge::P;using pmbridge::Runtime;
struct Point {float x,y;};
void prepare(Runtime&,P,const phimod::Options&);
void clear(Runtime&);
void beforeCodes(Runtime&,P);
void afterInformation(Runtime&,P);
void beginFrame(Runtime&,P);
void moved(Runtime&,P,bool hold=false);
void frame(Runtime&,P);
void late(Runtime&,P);
bool blocking(Runtime&,Point,P*,bool& handled);
void completed(Runtime&,P);
void holdMove(Runtime&,P);
void validate(Runtime&);
// A scoped managed-array edit; always restores on success, exceptions and early return.
class HoldScope {
 Runtime&r_;P line_=nullptr,array_=nullptr;int count_=0;float first_=0;bool arrayChanged_=false,countChanged_=false;
 void restore();
 public:
 HoldScope(Runtime&,P);
 ~HoldScope() noexcept;
 void finish(){restore();}
 HoldScope(const HoldScope&)=delete;
};
}
