#pragma once
#include "PMIL2CPP.hpp"
namespace pmcontent {
void* loadSkinAudio(pmbridge::Runtime&,NSString*path);
void attach(pmbridge::Runtime&);void pulse();void refreshMainlineAccess(pmbridge::Runtime&);
void chapterPrepare(pmbridge::Runtime&,void*);void chapterReady(pmbridge::Runtime&,void*);
bool sourceHoldGeometry(pmbridge::Runtime&,void*control);
bool shortSourceHold(pmbridge::Runtime&,void*note);
bool customLevel();bool isMainlineChapter(NSString*);bool isMainlineSong(NSString*);void levelBegin(pmbridge::Runtime&);void levelEnd(pmbridge::Runtime&);
bool assetConstructor(pmbridge::Runtime&,void*self,void*key);bool assetRelease(pmbridge::Runtime&,void*self,bool force=false);
void levelInfo(pmbridge::Runtime&,void*song,int slot,void*info);
void selectorLoadingBegin(pmbridge::Runtime&,void*selector);
void selectorLoadingFrame(pmbridge::Runtime&,void*selector);
void selectorLoadingEnd(pmbridge::Runtime&,bool finishSelected);
void prepareSelectorItems(pmbridge::Runtime&,void*selector);
void selectorFrame(pmbridge::Runtime&,void*selector);
NSDictionary*selectedDifficulty(NSString*group,int slot);
NSDictionary*difficultyForSong(pmbridge::Runtime&,void*song,int slot);
bool difficultyInput(pmbridge::Runtime&,void*selector);
bool ownsDifficultyButton(void*button);
bool pressDifficultyButton(pmbridge::Runtime&,void*button);
void freezeChallengeDifficulties(pmbridge::Runtime&,void*selector=nullptr);
void difficultySelectorOff(pmbridge::Runtime&);
void difficultyResultLabel(pmbridge::Runtime&,void*iterator);
void difficultyTransitionLabel(pmbridge::Runtime&,void*selector);
void difficultyIntro(pmbridge::Runtime&,void*level);
void difficultyGameplayLabel(pmbridge::Runtime&,void*progress);
void restoreSelectorRowVisibility(pmbridge::Runtime&);
void selectorDifficultyUI(pmbridge::Runtime&,void*selector);
NSDictionary*officialSnapshot();NSDictionary*cachedOfficialSnapshot();NSDictionary*command(NSString*action,NSString*identifier,int slot);
void beforeInformation(pmbridge::Runtime&,void*level);
void beforeChart(pmbridge::Runtime&,void*level);void afterChart(pmbridge::Runtime&,void*level);
void prepareHoldHitFX(pmbridge::Runtime&,void*control);
void judgeWithHudPause(pmbridge::Runtime&,void*,void*,void(*)(void*,void*));
bool hasNoteController(pmbridge::Runtime&,void*line,int index,bool above);
void recoverSourceNotes(pmbridge::Runtime&,void*manager);
void visuals(pmbridge::Runtime&,void*progress);void noteMoved(pmbridge::Runtime&,void*control,bool hold);
void finishNoteGeometry(pmbridge::Runtime&,void*control,bool hold);
void ranking(pmbridge::Runtime&,void*,void*,void(*)(void*,void*));
void validate(pmbridge::Runtime&);
}
