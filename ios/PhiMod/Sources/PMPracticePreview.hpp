#pragma once
#include "PMIL2CPP.hpp"
namespace pmpracticepreview {
int reset(pmbridge::Runtime&,void* progress,float current);
void render(pmbridge::Runtime&,void* manager,float current,bool countdown,float target);
void clear();
void discardControls();
bool creating();
bool settled(void*note);
void validate(pmbridge::Runtime&);
}
