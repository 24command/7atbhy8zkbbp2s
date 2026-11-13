#pragma once
#include "PMIL2CPP.hpp"
namespace pmfeatures {
void* noteSprite(pmbridge::Runtime&,int type,int part,void*original);
void beforeNoteMove(pmbridge::Runtime&,void*control,bool hold);
bool playSkinSound(pmbridge::Runtime&,void*self,int index);
void skinEffectCreated(pmbridge::Runtime&,void*original,void*clone,void*control);
void flushHitEffects(pmbridge::Runtime&);
void styleLine(pmbridge::Runtime&,void*renderer);
void attach(pmbridge::Runtime&);
void levelBegin(pmbridge::Runtime&, void* level);
void levelEnd(pmbridge::Runtime&);
void afterChart(pmbridge::Runtime&, void* level);
void noteMoved(pmbridge::Runtime&, void* control, bool hold);
void tick(pmbridge::Runtime&, void* progress);
void observe(int rating);
}
