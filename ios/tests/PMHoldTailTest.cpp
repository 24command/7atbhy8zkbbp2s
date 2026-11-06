#include "../PhiMod/Core/PMHoldTail.hpp"
#include <cassert>
int main(){
 auto p=phimod::shortHoldTail(56.5f,.125f,56.614544f,.08f,true,false,false);
 assert(p.protectRelease);assert(std::fabs(p.deadline-56.545f)<1e-5);assert(std::fabs(p.adjustedDuration-.265f)<1e-6);
 assert(!phimod::shortHoldTail(1,.125f,1.044f,.08f,true,false,false).protectRelease);
 assert(phimod::shortHoldTail(1,.125f,1.046f,.08f,true,false,false).protectRelease);
 assert(!phimod::shortHoldTail(1,.125f,1.1f,.08f,false,false,false).protectRelease);
 assert(!phimod::shortHoldTail(1,.125f,1.1f,.08f,true,true,false).protectRelease);
 assert(!phimod::shortHoldTail(1,.125f,1.1f,.08f,true,false,true).protectRelease);
 for(float duration:{.01f,.0757576f,.125f,.219f}){auto q=phimod::shortHoldTail(1,duration,1,.08f,true,false,false);assert(std::fabs(1+q.adjustedDuration-.22f-q.deadline)<1e-6);assert(q.deadline>=1);}
 assert(phimod::noteRenderFinished(1,true,.9f,1,0));
 assert(!phimod::noteRenderFinished(2,true,.9f,1,0));assert(!phimod::noteRenderFinished(4,true,.9f,1,0));
 assert(!phimod::noteRenderFinished(3,true,1.1f,1,.125f));assert(phimod::noteRenderFinished(3,true,1.125f,1,.125f));
}
