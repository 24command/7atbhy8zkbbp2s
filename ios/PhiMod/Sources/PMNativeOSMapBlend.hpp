#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>

namespace pmnativeosmap::blend {
constexpr const char *shaderResource = "shaders/trueshadow-additive";
// Retail resources.assets path 139: UI/TrueShadow-Additive. Metal vertex RGB
// is multiplied by vertex alpha, then the pass blends SrcAlpha/One. Therefore
// with Graphic.color.a=1 and an isolated CanvasGroup, contribution is
// texture.rgb * tint.rgb * texture.a * groupAlpha^2. Never compensate via HDR
// vertex colors (Unity Graphic colors are Color32) or pretend UI/Default has a
// dynamic _SrcBlend binding. Clip masks still act normally; opacity is explicit.
inline float unit(float value) {
    return std::isfinite(value) ? std::clamp(value,0.f,1.f) : 0.f;
}
inline float groupAlpha(float inherited, float tintAlpha, float rootAlpha, bool active) {
    return active ? std::sqrt(unit(inherited)*unit(tintAlpha)*unit(rootAlpha)) : 0.f;
}
struct Layer {
    uint32_t group=0, graphic=0;
    float alpha=0, tintAlpha=1;
    bool input=false;
};
// Tint alpha is represented only in the isolated group, never a second time in
// the vertex color. Normal graphics retain their existing RGBA unchanged.
template<class Color> inline Color graphicColor(Layer &layer, Color color, bool tintEnabled=true) {
    if (layer.group && tintEnabled) { layer.tintAlpha=unit(color.alpha); color.alpha=1; }
    return color;
}
}
