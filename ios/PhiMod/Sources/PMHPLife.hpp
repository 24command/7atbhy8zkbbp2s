#pragma once
#include "PMIL2CPP.hpp"
#include "../Core/PMGameplayCore.hpp"
namespace pmhp {
void prepare(pmbridge::Runtime&,void*,const phimod::Options&);
void beginAttempt(float hp);
void loadVisuals(pmbridge::Runtime&,void* progress);
std::string loadingStatus(pmbridge::Runtime&);
void clear(pmbridge::Runtime&);
bool active();
bool ownsBar(pmbridge::Runtime&,void*);
float normalized();
void barStart(pmbridge::Runtime&,void*);
void barUpdate(pmbridge::Runtime&,void*);
void modStart(pmbridge::Runtime&,void*);
void backgroundBefore(pmbridge::Runtime&);
void frame(pmbridge::Runtime&,float);
void scoreFrame(pmbridge::Runtime&,void*);
void flash(pmbridge::Runtime&);
bool failureReady(pmbridge::Runtime&,void*);
bool failing();
void rememberChartCount(pmbridge::Runtime&,void*);
void finishChallenge(pmbridge::Runtime&,void*);
void finish(pmbridge::Runtime&);
void validate(pmbridge::Runtime&);
}
