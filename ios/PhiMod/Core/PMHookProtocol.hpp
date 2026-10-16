#pragma once
#include <cstdint>
#include <cstddef>
namespace phimod::hooks {
struct Slot { std::uint64_t callback; };
static constexpr char magic[16]="PMGameplay-v1";
static constexpr std::uint32_t version=1;
enum Index : std::uint32_t {
 levelAwake=0,
 levelDestroy=1,
 progressStart=2,
 progressUpdate=3,
 miss=4,
 bad=5,
 good=6,
 perfect=7,
 scoreUpdate=8,
 resultInfo=9,
 click=10,
 drag=11,
 hold=12,
 flick=13,
 record=14,
 setRecord=15,
 ranking=16,
 resultStart=17,
 resultMove=18,
 selector=19,
 selectorOff=20,
 setting=21,
 settingTab=22,
 settingBack=23,
 button=24,
 checkNote=25,
 checkFlick=26,
 DeleteKey=27,
 SaveBool=28,
 SaveInt=29,
 SaveFloat=30,
 SaveDate=31,
 SaveString=32,
 LegacySaveBool=33,
 LegacySaveInt=34,
 LegacySaveFloat=35,
 LegacySaveString=36,
 Count
};
struct Entry {std::uint32_t site,original;std::uint64_t gateway;};
static_assert(sizeof(Entry)==16);
static_assert(sizeof(Slot)==8);
}
