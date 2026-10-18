#pragma once
#include "PMHookProtocol.hpp"
namespace phimod::hooks {
struct ExpectedEntry { uint32_t site,original; };
inline constexpr ExpectedEntry expected[]={
 {0x1580c78u,0xd10303ffu}, // levelAwake
 {0x1580f98u,0xa9be4ff4u}, // levelDestroy
 {0x1592428u,0xa9bd57f6u}, // progressStart
 {0x1592668u,0x6dbc23e9u}, // progressUpdate
 {0x1594298u,0x6dbd23e9u}, // miss
 {0x1594380u,0x6dbd23e9u}, // bad
 {0x159447cu,0x6dba33edu}, // good
 {0x1594678u,0x6dba33edu}, // perfect
 {0x1594848u,0xd10103ffu}, // scoreUpdate
 {0x1592f90u,0xa9bd57f6u}, // resultInfo
 {0x158e59cu,0x6dbc2bebu}, // click
 {0x158ede4u,0x6dbd23e9u}, // drag
 {0x15902d8u,0x6dbc23e9u}, // hold
 {0x158f540u,0x6dbd23e9u}, // flick
 {0x14a22b0u,0xa9bc5ff8u}, // record
 {0x14a65c0u,0xa9bc5ff8u}, // setRecord
 {0x14a67e0u,0xd10143ffu}, // ranking
 {0x15857f4u,0xa9bd57f6u}, // resultStart
 {0x158d2c8u,0xa9bb67fau}, // resultMove
 {0x15b5a10u,0x6db82bebu}, // selector
 {0x15b1a4cu,0xa9bc5ff8u}, // selectorOff
 {0x15a3860u,0xa9be4ff4u}, // setting
 {0x15a43f0u,0x6dbb23e9u}, // settingTab
 {0x15a4128u,0xa9bc5ff8u}, // settingBack
 {0x3a42618u,0xa9be4ff4u}, // button
 {0x157c578u,0x6db733edu}, // checkNote
 {0x157cce8u,0x6db733edu}, // checkFlick
 {0x14b00d0u,0xa9bd57f6u}, // DeleteKey
 {0x14b019cu,0xd10103ffu}, // SaveBool
 {0x14b0284u,0xd10103ffu}, // SaveInt
 {0x14b0318u,0xd10103ffu}, // SaveFloat
 {0x14b040cu,0xd10103ffu}, // SaveDate
 {0x14b04dcu,0xa9bd57f6u}, // SaveString
 {0x14b15d0u,0xd10103ffu}, // LegacySaveBool
 {0x14b16b8u,0xd10103ffu}, // LegacySaveInt
 {0x14b174cu,0xd10103ffu}, // LegacySaveFloat
 {0x14b17e0u,0xa9bd57f6u}, // LegacySaveString
 {0x3a426b4u,0xa9be4ff4u}, // buttonClick
 {0x3a4275cu,0xa9bd57f6u}, // buttonSubmit
 {0x14d85b8u,0xa9bd57f6u}, // lifeStart
 {0x14d8ae8u,0xa9bd57f6u}, // lifeNormalized
 {0x14d9284u,0xa9bc5ff8u}, // lifeModStart
 {0x1574f40u,0xa9bd57f6u}, // hpBackgroundStart
 {0x15931d8u,0xa9bd57f6u}, // progressLevelOver
 {0x14d8d6cu,0x6dbb2bebu}, // lifeUpdate
 {0x1581010u,0xa9ba6ffcu}, // levelCodes
 {0x15814f8u,0x6db63befu}, // levelInfo
 {0x1590aa4u,0x6db82bebu}, // noteManager
 {0x157d668u,0xd10283ffu}, // blocking
 {0x15788e8u,0xa9bd57f6u}, // blockLate
 {0x158f9e0u,0x6dba33edu}, // holdMove
 {0x158e2b8u,0x6dbb2bebu}, // clickMove
 {0x158eb38u,0x6dbb2bebu}, // dragMove
 {0x158f294u,0x6dbb2bebu}, // flickMove
 {0x157bb20u,0x6dba23e9u}, // judgeUpdate
 {0x15c7b3cu,0x6dbb2bebu}, // audioUpdate
 {0x157e4a0u,0x6db92bebu}, // lineCreateNote
};
static_assert(sizeof(expected)/sizeof(expected[0])==Count,"Offline hook manifest must match callback protocol");
}
