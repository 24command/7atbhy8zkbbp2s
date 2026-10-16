#pragma once
#include "PMIL2CPP.hpp"
namespace pmscene {
void selectorFrame(pmbridge::Runtime&,void*);
void selectorOff(pmbridge::Runtime&);
void settingsFrame(pmbridge::Runtime&,void*);
void settingsLeave(pmbridge::Runtime&);
bool press(pmbridge::Runtime&,void*);
void hpFrame(float,float,bool);
}
