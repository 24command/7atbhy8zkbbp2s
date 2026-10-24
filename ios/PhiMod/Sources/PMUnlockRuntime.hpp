#pragma once
#include "PMIL2CPP.hpp"
namespace pmunlock {
void attach(pmbridge::Runtime&);
void songInfo(pmbridge::Runtime&,void* song,int slot,void* value);
void itemInfo(pmbridge::Runtime&,void* item,int slot,void* value);
void chapterReady(pmbridge::Runtime&,void* selector);
void tick(pmbridge::Runtime&,void* selector);
void clear(pmbridge::Runtime&);
}
