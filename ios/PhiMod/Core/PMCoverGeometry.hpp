#pragma once
#include <algorithm>
#include <cmath>
#include <stdexcept>
namespace pmcover {
struct Rect{double x,y,w,h;};
inline Rect fit(double sw,double sh,double tw,double th,bool fill){
 if(!std::isfinite(sw)||!std::isfinite(sh)||!std::isfinite(tw)||!std::isfinite(th)||sw<=0||sh<=0||tw<=0||th<=0)throw std::invalid_argument("Invalid cover dimensions");
 double factor=fill?std::max(tw/sw,th/sh):std::min(tw/sw,th/sh);
 double w=sw*factor,h=sh*factor;return {(tw-w)/2,(th-h)/2,w,h};
}
}
