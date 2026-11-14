#pragma once
#include <algorithm>
#include <cmath>
namespace phimod {
struct DifficultyArrowGeometry{float width,height,cut,leftCenter,rightCenter;};
inline DifficultyArrowGeometry difficultyArrowGeometry(float rowHeight,float inverseSlope,float left,float right){
 float height=std::max(40.f,rowHeight),slope=std::isfinite(inverseSlope)?std::fabs(inverseSlope):.2679492f;
 float cut=height*slope,width=std::max(64.f,cut+36.f),gap=6.f;
 // Native parallelogram vertices: (cut,top),(right,top),(right-cut,bottom),(left,bottom).
 // Match a 6-unit gap at the midline, not the unslanted bounding boxes.
 return {width,height,cut,left-width*.5f+cut-gap,right+width*.5f-cut+gap};
}
}
