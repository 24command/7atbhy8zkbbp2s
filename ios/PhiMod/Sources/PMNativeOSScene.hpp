#pragma once
#include <cstdint>
namespace pmbridge { struct Runtime; }

namespace pmnativeosscene {
using pmbridge::Runtime;
enum class Route { SaturnOS, C8, C9, C9Phase2 };
// Unity main thread. Install chapter context before requesting a Single load.
// The returned visit is zero if the request was rejected. On arrival root is a
// borrowed active GameObject. Its stock children are dormant serialized roots.
// A null root reports an interrupted load or failed acquisition. Callers own
// presentation, safe donor activation and navigation out of the visit.
using Arrived = void (*)(Runtime&, uint64_t visit, Route, void *root);
uint64_t enter(Runtime&, Route, Arrived);
void *activeRoot(Runtime&);
// Optional notification once the return operation finishes and the selector is active.
// False means there is no selector handoff (chapter Back or an interrupted load).
using Returned = void (*)(Runtime&, uint64_t visit, bool atSongSelector);
bool leaveToSongSelector(Runtime&, Returned = nullptr);
// Stock C8/C9 Back sets nextScene to ChapterSelector and loads Loading.
bool leaveToChapter(Runtime&, Returned);
bool isSongSelector(Runtime&, int handle);

// PMHookBackend only. Installed after publishing all offline entry gates.
void hooksInstalled();
bool sceneLoaded(Runtime&, int handle, int loadMode);
bool sceneUnloaded(Runtime&, int handle);
bool ownsController(Runtime&, Route, void *controller);
}
