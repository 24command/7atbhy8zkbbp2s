#pragma once
namespace pmbridge { struct Runtime; }

namespace pmnativeosscene {
// Main thread only, after the native OS coordinator accepts a user Start and
// latches busy, before chapterStartIntro (not its resume callback). The caller
// supplies exactly-once acceptance; a later cancellation/failure keeps the
// already emitted stock sound. Never call from the ordinary selector path.
// False: no ready delegate or dispatch failed; the helper logs the failure.
// Retain the accepted Start and continue gameplay; do not substitute another
// click/backend or retry from the entrance animation.
bool playStartSound(pmbridge::Runtime&);
}
