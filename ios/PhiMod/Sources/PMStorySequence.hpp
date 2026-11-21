#pragma once
// At most one post-clear handoff exists. Navigation is one-shot even if a
// chapter-ready callback re-enters; direct returns to SongSelector may take it
// without routing through ChapterSelector first.
namespace pmstorysequence {
template<class Ticket> class Handoff {
    Ticket ticket{};
    bool routed = false;
public:
    void issue(Ticket value) { ticket = value; routed = false; }
    Ticket take() { Ticket saved = ticket; issue(Ticket{}); return saved; }
    template<class Navigate> bool route(Navigate navigate) {
        if (!ticket) return false;
        if (routed) return true;
        Ticket saved = ticket;
        routed = true;
        struct Guard {
            Handoff &owner;
            Ticket saved;
            bool ok = false;
            ~Guard() { if (!ok && owner.ticket == saved) owner.issue(Ticket{}); }
        } guard{*this, saved};
        return guard.ok = navigate(saved);
    }
    bool holds(Ticket value) const { return ticket == value; }
};
}

#ifdef __OBJC__
#import "PMStorySequence.h"
namespace pmstorysequence {
// Owned by PMDoorRun. No selector, UIKit view or callback is retained.
extern Handoff<NSDictionary *> handoff;
BOOL attachToPending(NSString *chapter, NSArray<NSDictionary *> *songs);
}
#endif
