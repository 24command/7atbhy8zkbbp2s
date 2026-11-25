#pragma once
#include <string>
#include <string_view>

namespace pmnativeosnavigation {
enum class Face { Default, List, OS };

// Main-thread memory of the visible face in ONE chapter visit. Loading, gameplay,
// Result, retries and hidden story/course selectors do not end that visit.
class Visit {
    std::string chapter_;
    Face face_ = Face::Default;
public:
    void chapter(std::string_view key) {
        if (chapter_ != key) { chapter_ = key; face_ = Face::Default; }
    }
    void presentedOS(std::string_view key) {
        if (key.empty()) return;
        chapter(key); face_ = Face::OS;
    }
    void presentedList(std::string_view key, bool owned, bool uncovered, bool settled) {
        // A hidden NormalStart / staged list must not change the visible origin.
        if (key.empty() || !owned || !uncovered || !settled) return;
        chapter(key); face_ = Face::List;
    }
    bool wantsOS(std::string_view key, bool listFirst, bool switchHidden, bool checkpoint) const {
        // Routed checkpoints intentionally outrank face memory, as does OS-only UI.
        if (switchHidden || checkpoint) return true;
        if (chapter_ == key && face_ != Face::Default) return face_ == Face::OS;
        return !listFirst;
    }
    void chapterReady(int index, std::string_view path, bool active, bool automaticallyRouted) {
        // Retail 4.0.4 globalgamemanagers: index 6 is the real chapter menu.
        // A story/checkpoint auto-route through that menu is still the same visit.
        if (!automaticallyRouted && active && index == 6 &&
            path == "Assets/Phigros2/ChapterSelector/ChapterSelector.unity") {
            chapter_.clear(); face_ = Face::Default;
        }
    }
};
}
