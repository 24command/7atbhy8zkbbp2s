#pragma once
#include <cmath>
struct PMHudOffset{float x,y;};
inline PMHudOffset pmHudOffset(float ox,float oy,float dx,float dy,float sx,float sy,float degrees){
 float radians=degrees*.017453292519943295f,c=std::cos(radians),s=std::sin(radians);
 return {dx+ox-(ox*sx*c-oy*sy*s),dy+oy-(ox*sx*s+oy*sy*c)};
}
