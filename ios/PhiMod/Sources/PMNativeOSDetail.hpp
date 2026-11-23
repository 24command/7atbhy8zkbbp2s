#pragma once
#include "PMIL2CPP.hpp"

// 4.0.4 presentation only. The host supplies a private, initialized donor
// hierarchy (not the active official chapter), and owns its scene lifetime.
namespace pmnativedetail {
using pmbridge::P; using pmbridge::Runtime;
enum class Style { c8, c9 };
struct Speech { NSString *heading=nil; NSString *transcript=nil; double seconds=0; NSData *waveform=nil; };
// Find exactly one serialized controller under a host-owned GameObject,
// including inactive children. No global search and no additive scene loads.
P findDonor(Runtime&, P donorRoot, Style);
// Inputs are live Unity objects except row (a plain managed SongSelectorItem).
// C8: disable Chapter8SelectMusicControl BEFORE first activation (its OnDisable writes saves).
// Supply an active root enclosing both controller and canvas, never the stock scene.
// One disposable donor per visit. Never reuse its delayed animation callbacks.
// Coordinator owns input: it routes slot changes through update(), accepts
// Start only via the checked OS scene launch, and calls close before unload.
// C9 builds stock addressable keys internally. For a PM/ cover pass the live
// Unity Sprite resolved for this exact selection, or a row whose cover loader
// has already settled on its exact coverAssetCode. Otherwise open/update fails.
uint64_t open(Runtime&, Style, P donorRoot, P row, int slot, const Speech& = {}, bool narrow=false, P coverSprite=nullptr);
bool update(Runtime&, uint64_t visit, P row, int slot, P coverSprite=nullptr);
void close(Runtime&, uint64_t visit);
}
