#pragma once
#include <algorithm>
#include <cmath>
#include <cstring>

namespace pmc89unlock {
struct Profile {
    const char *movie;
    double duration, show, hide;
};

// 4.0.4 build 3. Times are movie PTS in seconds. In the C8 controllers
// the movie-time predicate activates SongInfoCanvas. Its ShowInfo alpha
// ramp begins 62 animation frames later (60 Hz).
inline constexpr Profile destruction{"@stock/c8/321-unlock", 807./30, 11.56666666 + 62./60, 11.56666666 + 11};
inline constexpr Profile distortion{"@stock/c8/df-unlock", 1396./30, 26.8 + 62./60, 26.8 + 7};
// The C9 DS intro contains video + difficulty controls. Position the shared
// seven-second credit animation at the end of this movie as an authored cue.
inline constexpr Profile signals{"@stock/c9/ds-intro", 540./30, 11 + 62./60, 18};

inline const Profile *defaultProfile(int chapter) {
    return chapter == 8 ? &destruction : chapter == 9 ? &signals : nullptr;
}

struct Window { double show, hide; };
// duration is effective playable time, including any author-imposed cutoff.
// Pass the declaration's source reference, never the cache filename. Missing
// bounds (-1) follow the verified clip or, for a custom clip, the full window.
inline bool resolve(int chapter, const char *source, double duration,
                    double show, double hide, Window &out) {
    const Profile *profile = defaultProfile(chapter);
    if (!profile || !std::isfinite(duration) || duration <= 0 || duration > 86400) return false;
    if (source && *source) {
        if (chapter == 8 && std::strcmp(source, distortion.movie) == 0) profile = &distortion;
        else if (std::strcmp(source, profile->movie) != 0) profile = nullptr;
    }
    // If a shorter cut ends before the retail cue, use that cut's available
    // window. Only infer missing bounds; explicit author times are validated.
    double end = hide == -1 ? (profile ? std::min(duration, profile->hide) : duration) : hide;
    if (hide == -1 && show >= end) end = duration;
    if (show == -1) show = profile && profile->show < end ? profile->show : 0;
    if (!(show >= 0 && show < end && end <= duration)) return false;
    out = {show, end};
    return true;
}
}
