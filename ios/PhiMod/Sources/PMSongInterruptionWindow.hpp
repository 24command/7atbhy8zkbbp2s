#pragma once
namespace pmsonginterruption {
// Retail Unity uses the UIApplication lifecycle without a scene manifest.
// A verified legacy Unity window is valid while the application is active.
inline bool windowActive(bool hasWindow,bool hidden,bool appActive,bool hasScene,bool sceneActive){
 return hasWindow && !hidden && appActive && (!hasScene || sceneActive);
}
}
