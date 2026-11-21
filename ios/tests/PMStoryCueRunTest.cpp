#include "../PhiMod/Sources/PMStoryCueRun.h"
#include "../PhiMod/Core/PMGameplayCore.hpp"
#include <cassert>
#include <map>
#include <stdexcept>
#include <string>
#include <type_traits>

namespace {
using BOOL = bool;
constexpr bool YES = true, NO = false;
struct Object {
    std::map<std::string, Object *> refs;
    std::map<std::string, double> values;
};
using P = Object *;
struct Runtime {
    template<class T> T get(P obj, const char *key) {
        if constexpr (std::is_same_v<T, P>) return obj->refs.at(key);
        else return static_cast<T>(obj->values.at(key));
    }
    template<class T> void put(P obj, const char *key, T value) { obj->values.at(key) = value; }
};
Runtime &R() { static Runtime runtime; return runtime; }
void diagf(const char *, const char *) { assert(false); }
void PMDoorAbandon() {}
void PMDoorCancelPending() {}
void PMDoorFinish(bool) {}
bool PMUnlockMediaBusy() { return false; }
#include "../PhiMod/Sources/PMDoorGameplay.inc"
pmstory::Timeline timeline;
bool blocked(double t) { return timeline.sample(t).block; }
int ends;
void ended() { ++ends; }
}

int main() {
    assert(!timeline.add(NAN, 1, true, true, true));
    assert(!timeline.add(0, INFINITY, true, true, true));
    assert(!timeline.add(1, 0, true, true, true));
    assert(timeline.add(0, 5, true, false, true));
    assert(timeline.add(2, 1, true, true, false));
    assert(timeline.add(4, 2, false, false, true));
    auto check = [](double t, int text, int image, bool block) {
        auto frame = timeline.sample(t);
        assert(frame.text == text && frame.image == image && frame.block == block);
    };
    check(-1, -1, -1, false);
    check(0, 0, -1, true);
    check(2, 1, 1, true);
    check(3, 0, -1, true);
    check(5, -1, -1, true);
    check(6, -1, -1, false);
    check(2.5, 1, 1, true);
    check(NAN, -1, -1, false);

    Object info{{}, {{"canPause",1},{"levelOver",0},{"levelBegan",1}}};
    Object pc{{{"levelInformation",&info}}, {{"isPlaying",1},{"leave",1},{"levelBreak",0},{"nowTime",2}}};
    Object judge{{{"progressControl",&pc}}, {{"pauseTime",1}}}, unrelated;
    doorProgress = &pc;
    currentLevel = &info;
    endDoorPresentation = ended;
    auto canPause = [&]{ return R().get<bool>(&info,"canPause"); };
    { StoryPauseScope gate(R(), &unrelated, false, blocked); assert(canPause()); }
    try {
        StoryPauseScope gate(R(), &judge, true, blocked);
        assert(!canPause() && judge.values.at("pauseTime") == 0);
        throw std::runtime_error("unwind native callback");
    } catch (const std::runtime_error &) {}
    assert(canPause());
    { StoryPauseScope gate(R(), &pc, false, blocked); assert(!canPause() && !pc.values.at("leave")); }
    assert(canPause());
    info.values["canPause"] = 0;
    { StoryPauseScope gate(R(), &pc, false, blocked); }
    assert(!canPause());
    info.values["canPause"] = 1;
    pc.values["nowTime"] = 6;
    pc.values["leave"] = 1;
    { StoryPauseScope gate(R(), &pc, false, blocked); assert(canPause() && pc.values.at("leave")); }
    pc.values["nowTime"] = 2;
    { StoryPauseScope gate(R(), &pc, false, blocked); info.values["levelOver"] = 1; }
    assert(!canPause());
    { StoryPauseScope gate(R(), &pc, false, blocked); }
    assert(!endDoorPresentation && ends == 1);
    abandonBoundDoor();
    assert(ends == 1);
    doorProgress = &pc;
    endDoorPresentation = ended;
    settleDoorEnd(&pc, nullptr, true);
    assert(!doorProgress && !endDoorPresentation && ends == 2);

    // A lethal judgement inside the native update must end presentation once.
    phimod::Options options;
    options.hpEnabled = true;
    options.hpMax = 1;
    options.hpDelta = {0, 0, 0, -1};
    phimod::Session session;
    session.setCoverage({true, true, true, true, true, true, true});
    session.request(options);
    assert(session.begin({}));
    session.registerNote({1, 1, 0, 1});
    info.values["levelOver"] = 0;
    info.values["canPause"] = 1;
    pc.values["_inChallengeMode"] = 0;
    doorProgress = &pc;
    endDoorPresentation = ended;
    {
        StoryPauseScope gate(R(), &pc, false, blocked);
        assert(!canPause());
        float before = session.hp();
        bool accepted = session.observe(1, 0, phimod::Rating::Miss);
        observeDoorLoss(&pc, session, accepted, before);
    }
    assert(!canPause() && !doorProgress && lostDoorProgress == &pc && ends == 3);
    // Lock the entire attempt, even with no cue presentation or timed interval.
    doorProgress=&pc;doorNoPause=true;lostDoorProgress=nullptr;endDoorPresentation=nullptr;
    pc.values["nowTime"]=600;pc.values["levelBreak"]=0;info.values["canPause"]=1;
    {StoryPauseScope gate(R(),&judge,true,blocked);assert(!canPause());} assert(canPause());
    {StoryPauseScope gate(R(),&pc,false,blocked);assert(!canPause());abandonBoundDoor();} assert(canPause()&&!doorNoPause);
    {StoryPauseScope gate(R(),&pc,false,blocked);assert(canPause());}
    doorProgress=&pc;doorNoPause=true;finishBoundDoor(YES);assert(!doorNoPause);
    // In a native course levelBreak is set for the normal challenge transition.
    pc.values["levelBreak"]=1;
    {StoryPauseScope gate(R(),&pc,false,blocked,&pc);assert(!canPause());} assert(canPause());
    {StoryPauseScope gate(R(),&pc,false,blocked);assert(canPause());}
    watchingDoorLaunch = true;
    unrelated.values["exit"] = 0;
    assert(cancelIdleDoorLaunch(&unrelated) && !cancelIdleDoorLaunch(&unrelated));
    assert(ends == 3);
}
