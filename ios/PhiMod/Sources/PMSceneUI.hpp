#pragma once
#include "PMIL2CPP.hpp"
namespace pmscene {
void selectorFrame(pmbridge::Runtime&,void*);
void selectorOff(pmbridge::Runtime&);
void settingsFrame(pmbridge::Runtime&,void*);
void settingsLeave(pmbridge::Runtime&);
bool press(pmbridge::Runtime&,void*);
bool ownsButton(void*);
void resultRecovery(pmbridge::Runtime&,void*,const std::string&);
void clearRecovery(pmbridge::Runtime&);
}
