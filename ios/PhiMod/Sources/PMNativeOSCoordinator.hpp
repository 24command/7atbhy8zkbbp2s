#pragma once
#import "PMStorySequence.h"
namespace pmbridge { struct Runtime; }
namespace pmnativecoordinator {
void ready(pmbridge::Runtime&, void *selector, NSString *chapter, PMStoryStartSong start);
void detach(pmbridge::Runtime&);
bool press(pmbridge::Runtime&, void *button);
bool transitioning();
}
