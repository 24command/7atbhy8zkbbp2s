#pragma once
#import "PMStorySequence.h"
namespace pmbridge { struct Runtime; }
namespace pmnativecoordinator {
void selectorLoaded(pmbridge::Runtime&, int handle, NSString *chapter);
void abortSelectorEntry(pmbridge::Runtime&);
void ready(pmbridge::Runtime&, void *selector, NSString *chapter);
void selectorFrame(pmbridge::Runtime&, void *selector);
void detach(pmbridge::Runtime&);
bool press(pmbridge::Runtime&, void *button);
bool pointerClick(pmbridge::Runtime&, void *button, void *pointerEvent);
void sceneUnloaded(pmbridge::Runtime&, int handle, bool owned);
bool transitioning();
bool transitionCoverActive();
// Hidden return-selector preparation; consumes Update only for this owned handoff.
bool stageSelector(pmbridge::Runtime&,void *selector,void (^nativeUpdate)(void));
}
