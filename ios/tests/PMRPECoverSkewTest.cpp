#include "../PhiMod/Core/PMRPEGeometry.hpp"
#include <cassert>
int main(){
 assert(rpeCovered(true,1,2,3,4,1));assert(!rpeCovered(false,1,2,3,4,1));
 assert(!rpeCovered(true,2,2,3,4,1));assert(!rpeCovered(true,1,2,3,2,1));
 assert(!rpeCovered(true,1,2,3,3.001,1));assert(rpeCovered(true,1,2,4,3,-1));
 assert(rpeSkew(0,20,false,1,1)==0);assert(rpeSkew(4,0,false,1,1)==0);
 float a=rpeSkew(1,45,false,2,1);assert(std::fabs(a-.5f)<1e-5);assert(std::fabs(rpeSkew(1,45,true,2,1)+a)<1e-5);
 assert(rpeSkew(1,45,false,0,1)==0);
}
