#pragma once
#include "PMIL2CPP.hpp"
namespace pmcontent {
void attach(pmbridge::Runtime&);void pulse();
bool customLevel();void levelBegin(pmbridge::Runtime&);void levelEnd(pmbridge::Runtime&);
bool assetConstructor(pmbridge::Runtime&,void*self,void*key);bool assetRelease(pmbridge::Runtime&,void*self);
void levelInfo(pmbridge::Runtime&,void*song,int slot,void*info);
void selectorFrame(pmbridge::Runtime&,void*selector);
NSDictionary*officialSnapshot();NSDictionary*command(NSString*action,NSString*identifier,int slot);
void beforeChart(pmbridge::Runtime&,void*level);void afterChart(pmbridge::Runtime&,void*level);
void visuals(pmbridge::Runtime&,void*progress);void noteMoved(pmbridge::Runtime&,void*control,bool hold);
void ranking(pmbridge::Runtime&,void*,void*,void(*)(void*,void*));
void validate(pmbridge::Runtime&);
}
