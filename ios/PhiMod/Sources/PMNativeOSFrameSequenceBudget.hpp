#pragma once
#include <algorithm>
#include <cmath>
#include <cstddef>

namespace pmnativeosmap { namespace residency {
// Four million texels (16 MiB RGBA), shared by one displayed page. Count a
// distinct still once, each silhouette once, and each animated surface once.
// Reserve all of that page's nodes so a later manual/timed reveal stays bounded.
constexpr size_t pageTexels = 4u * 1024u * 1024u;
inline int dimensionLimit(size_t surfaces) {
    return std::min(2048, int(std::sqrt(double(pageTexels) / std::max(size_t(1),surfaces))));
}
}}
