#pragma once
#include "PMNativeOSScene.hpp"
namespace pmnativechrome {
using pmbridge::Runtime;
using pmnativeosscene::Route;
enum class Face { Hidden, Map, Detail };
enum class Intent { Pass, Consumed, Back, List, Start, Slot };
struct Press { Intent intent=Intent::Pass; int slot=-1; };
namespace policy {
constexpr bool visible(Face face, Intent action, bool allowList=true) {
    return action==Intent::Back ? face==Face::Map || face==Face::Detail :
           action==Intent::List ? allowList && face==Face::Map :
           (action==Intent::Start || action==Intent::Slot) && face==Face::Detail;
}
constexpr bool enabled(Face face, bool input, unsigned mask, Press action, bool allowList=true) {
    return input && visible(face,action.intent,allowList) && (action.intent!=Intent::Slot ||
           (action.slot>=0 && action.slot<4 && (mask & (1u<<action.slot))));
}
}
struct View { void *parent=nullptr, *font=nullptr, *detailRoot=nullptr; };
// Unity main thread. Pass the visit, route and root from scene Arrived. All
// returned objects are borrowed until close. parent is a full-screen private
// RectTransform; detailRoot is an active GameObject (null for SaturnOS).
bool open(Runtime&, uint64_t visit, Route, void *sceneRoot, View &out);
// Call after detail::open/update so only the owned controls regain input.
// The coordinator owns mode, slot availability (bits 0..3), and Start checks.
// The six-argument form sets list access for this visit. Omitting allowList
// preserves the last setting. A new visit starts with list access allowed.
bool present(Runtime&, uint64_t visit, Face, bool input, unsigned slotMask=0);
bool present(Runtime&, uint64_t visit, Face, bool input, unsigned slotMask, bool allowList);
// Prepare a fresh detail copy when a song is selected. View.detailRoot stays stable.
bool resetDetail(Runtime&, uint64_t visit);
// At Button.Press, consume everything except Pass, including gated controls.
Press press(Runtime&, void *button);
// Close map/detail first, then chrome, before unloading the authored scene.
void close(Runtime&, uint64_t visit);
}
