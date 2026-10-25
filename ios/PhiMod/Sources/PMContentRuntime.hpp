#pragma once
#include "PMIL2CPP.hpp"
namespace pmcontent {
void attach(pmbridge::Runtime&);void pulse();void refreshMainlineAccess(pmbridge::Runtime&);
void chapterPrepare(pmbridge::Runtime&,void*);void chapterReady(pmbridge::Runtime&,void*);
bool customLevel();bool isMainlineChapter(NSString*);bool isMainlineSong(NSString*);void levelBegin(pmbridge::Runtime&);void levelEnd(pmbridge::Runtime&);
bool assetConstructor(pmbridge::Runtime&,void*self,void*key);bool assetRelease(pmbridge::Runtime&,void*self,bool force=false);
void levelInfo(pmbridge::Runtime&,void*song,int slot,void*info);
void selectorFrame(pmbridge::Runtime&,void*selector);
NSDictionary*officialSnapshot();NSDictionary*cachedOfficialSnapshot();NSDictionary*command(NSString*action,NSString*identifier,int slot);
void beforeChart(pmbridge::Runtime&,void*level);void afterChart(pmbridge::Runtime&,void*level);
void visuals(pmbridge::Runtime&,void*progress);void noteMoved(pmbridge::Runtime&,void*control,bool hold);
void ranking(pmbridge::Runtime&,void*,void*,void(*)(void*,void*));
void validate(pmbridge::Runtime&);
}
