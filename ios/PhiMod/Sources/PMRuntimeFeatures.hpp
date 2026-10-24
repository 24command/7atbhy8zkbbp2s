#pragma once
#include "PMIL2CPP.hpp"
namespace pmfeatures {
void attach(pmbridge::Runtime&);
void levelBegin(pmbridge::Runtime&, void* level);
void levelEnd(pmbridge::Runtime&);
void afterChart(pmbridge::Runtime&, void* level);
void noteMoved(pmbridge::Runtime&, void* control, bool hold);
void tick(pmbridge::Runtime&, void* progress);
void observe(int rating);
}
