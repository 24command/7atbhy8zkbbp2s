#include "../PhiMod/Core/PMDifficultyArrowGeometry.hpp"
#include <cassert>
#include <cmath>
#include <cstdio>
int main(){
 constexpr float nativeSlope=23.31156349182129f/87.f;
 for(float h:{40.f,56.f,87.f,120.f}){
  auto g=phimod::difficultyArrowGeometry(h,nativeSlope,-50,50);
  assert(std::fabs(g.cut/g.height-nativeSlope)<.00001f);
  assert(g.width-g.cut>=35.99f);
  float nativeLeft=-50+g.cut/2,arrowRight=g.leftCenter+g.width/2-g.cut/2;
  float nativeRight=50-g.cut/2,arrowLeft=g.rightCenter-g.width/2+g.cut/2;
  assert(std::fabs(nativeLeft-arrowRight-6)<.0001f);assert(std::fabs(arrowLeft-nativeRight-6)<.0001f);
 }
 auto native=phimod::difficultyArrowGeometry(87,nativeSlope,0,100);
 assert(native.leftCenter>-28);assert(native.rightCenter<128);
 puts("PASS native parallelogram slope and symmetric midline gaps across row heights");
}
