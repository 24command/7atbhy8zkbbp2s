#pragma once
#include <algorithm>
#include <vector>
namespace phimod {
struct ModSettingsRowBox{float x,y,width,height;};
struct ModSettingsLayout{float contentHeight;std::vector<ModSettingsRowBox>rows;};
inline ModSettingsLayout modSettingsLayout(float width,float viewportHeight,const std::vector<float>&heights){
 const float padding=24,gap=16;float y=padding;ModSettingsLayout out{};
 for(float height:heights){height=std::max(1.f,height);out.rows.push_back({padding,y,std::max(1.f,width-2*padding),height});y+=height+gap;}
 out.contentHeight=std::max(viewportHeight,y+(heights.empty()?0:padding-gap));return out;
}
}
