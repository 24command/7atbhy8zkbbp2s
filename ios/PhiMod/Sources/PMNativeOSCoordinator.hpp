#pragma once
#import "PMStorySequence.h"
namespace pmbridge { struct Runtime; }
namespace pmnativecoordinator {
void ready(pmbridge::Runtime&, void *selector, NSString *chapter, PMStoryStartSong start);
void selectorFrame(pmbridge::Runtime&, void *selector);
void detach(pmbridge::Runtime&);
bool press(pmbridge::Runtime&, void *button);
bool pointerClick(pmbridge::Runtime&, void *button, void *pointerEvent);
void sceneUnloaded(pmbridge::Runtime&, int handle, bool owned);
bool transitioning();
}
