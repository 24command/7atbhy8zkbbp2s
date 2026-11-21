#pragma once
#ifdef __OBJC__
#import <Foundation/Foundation.h>
@class PMPreparedStoryCues;
// Chapter worker. The immutable result holds timings, captions and validated still names.
FOUNDATION_EXPORT PMPreparedStoryCues *PMStoryCuePrepare(NSArray<NSDictionary *> *cues, NSString *chapterDir);
// Main thread, in the successful PMDoorArm callback immediately before NormalStart.
FOUNDATION_EXPORT void PMStoryCueArm(PMPreparedStoryCues *prepared);
#ifdef __cplusplus
namespace pmstory {
void captureLaunch();
void cancelLaunch();
bool beginExactTrack();
void endTrack();
bool blocksPause(double songTime);
void present(double songTime);
}
#endif
#endif

#ifdef __cplusplus
#include <algorithm>
#include <cmath>
#include <cstddef>
#include <vector>
namespace pmstory {
struct Frame { int text = -1, image = -1; bool block = false; int nextImage = -1; };
// Each boundary holds the frame in effect until the next boundary. Inserting cues
// in author order preserves last-visible-wins for text and images independently.
class Timeline {
    struct Boundary { double at; Frame frame; };
    std::vector<Boundary> boundaries;
    int count = 0;

    std::size_t split(double t) {
        auto it = std::lower_bound(boundaries.begin(), boundaries.end(), t,
            [](const Boundary &b, double t) { return b.at < t; });
        if (it == boundaries.end() || it->at != t) {
            Frame before = it == boundaries.begin() ? Frame{} : (it - 1)->frame;
            it = boundaries.insert(it, {t, before});
        }
        return static_cast<std::size_t>(it - boundaries.begin());
    }
public:
    bool add(double at, double duration, bool text, bool image, bool block, int imageRow = -1) {
        double end = at + duration;
        if (!(at >= 0 && duration > 0 && end > at && std::isfinite(end))) return false;
        std::size_t first = split(at), last = split(end);
        for (std::size_t i = first; i < last; ++i) {
            auto &f = boundaries[i].frame;
            if (text) f.text = count;
            if (image) f.image = imageRow < 0 ? count : imageRow;
            f.block |= block;
        }
        ++count;
        return true;
    }
    // Called once on the chapter worker. Look past gaps and text-only changes,
    // including the image revealed again when an overlapping cue ends.
    void prepareLookahead() {
        int nearest = -1, following = -1;
        for (auto it = boundaries.rbegin(); it != boundaries.rend(); ++it) {
            Frame &f = it->frame;
            if (f.image >= 0 && f.image != nearest) {
                following = nearest;
                nearest = f.image;
            }
            f.nextImage = f.image < 0 ? nearest : following;
        }
    }
    Frame sample(double t) const {
        if (!std::isfinite(t) || boundaries.empty()) return {};
        auto it = std::upper_bound(boundaries.begin(), boundaries.end(), t,
            [](double t, const Boundary &b) { return t < b.at; });
        if (it != boundaries.begin()) return (it - 1)->frame;
        Frame f;
        const auto &first = boundaries.front().frame;
        f.nextImage = first.image < 0 ? first.nextImage : first.image;
        return f;
    }
};
}
#endif
