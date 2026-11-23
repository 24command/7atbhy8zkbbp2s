#pragma once
#import "PMStockUnlockPresenter.h"
#include "../Core/PMChapterC8C9Unlock.hpp"

// Bridge for the custom OS media coordinator. All times are absolute seconds
// on its media clock. Pass -1 for an omitted bound. The coordinator owns
// playback, visibility, cancellation, and the once/visit completion fence.
namespace pmc89unlock {
inline NSString *stockMovieReference(int chapter) {
    const Profile *profile = defaultProfile(chapter);
    return profile ? @(profile->movie) : nil;
}

// Main thread. Pass the installed ID from chapter order and display fields from
// that same song. Locked songs need no selector item or playable difficulty.
// fields: title (required), artist, difficulty, level, charter, illustrator.
// Drive the returned transparent overlay with setPresentationSeconds:.
inline void prepareInfo(int chapter, NSString *source, double duration,
                        NSString *songID, NSDictionary<NSString *,NSString *> *fields,
                        double show, double hide,
                        void (^completion)(PMStockUnlockInfoView *)) {
    Window window{};
    if (!resolve(chapter, source.UTF8String, duration, show, hide, window)) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        return;
    }
    // Level 24 and 27 credit polygons match the four in level 8 byte-for-byte.
    // DF's ShowInfo stream also matches ShowInfoETC. The 321 version extends
    // its hold. C9 composes the same stock art with its own movie and cue.
    [PMStockUnlockInfoView prepareChapter:0 songID:songID fields:fields
                         infoShowSeconds:window.show infoHideSeconds:window.hide
                              completion:completion];
}
}
