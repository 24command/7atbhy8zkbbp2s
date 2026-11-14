#pragma once
#include "PMIL2CPP.hpp"
namespace pmunlock {
void attach(pmbridge::Runtime&);void validate(pmbridge::Runtime&);void mainlinePhase1Start(pmbridge::Runtime&,void*);bool mainlinePhase1ToPhase2(pmbridge::Runtime&,void*);bool mainlineApplyMapCover(pmbridge::Runtime&,void*);
NSString* coverPath(pmbridge::Runtime&,NSString* identifier);
bool beforeStart(pmbridge::Runtime&,void* selector,void (^resume)(void));
void songInfo(pmbridge::Runtime&,void* song,int slot,void* value);
void itemInfo(pmbridge::Runtime&,void* item,int slot,void* value);
void chapterReady(pmbridge::Runtime&,void* selector);
bool selectorAccess(pmbridge::Runtime&,void*selector);
bool blockChallengeButton(pmbridge::Runtime&,void*button);
bool ownsRequirementButton(void*button);
bool pressRequirement(pmbridge::Runtime&,void*button);
bool selectorModalUpdate(pmbridge::Runtime&,void*selector);
bool selectorButtonBlocked(pmbridge::Runtime&,void*button);
void tick(pmbridge::Runtime&,void* selector);
void resultStarted(pmbridge::Runtime&,void* owner);
bool beforeResultContinue(pmbridge::Runtime&,void* button);
void clear(pmbridge::Runtime&);
}
