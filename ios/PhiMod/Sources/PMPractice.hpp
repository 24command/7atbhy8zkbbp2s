#pragma once
#include "PMIL2CPP.hpp"
#include "../Core/PMGameplayCore.hpp"
#include <string>
namespace pmpractice {
using pmbridge::P;
using pmbridge::Runtime;
void prepare(Runtime&,const phimod::Options&);
void begin(Runtime&,P progress);
void clear(Runtime&);
bool ownsAudio(Runtime&,P);
void audioBefore(Runtime&,P);
void audioAfter(Runtime&,P);
bool beforeProgress(Runtime&,P);
bool afterProgress(Runtime&,P);
bool paused();
bool allowNoteCreation();
bool previewFrame(Runtime&,P manager);
bool updateRange(Runtime&,const phimod::Options&);
struct State {bool active=false,segment=false,paused=false,countdown=false,ended=false,loop=false,countIn=false,ready=false,playing=false;float start=0,end=-1,duration=0,cursor=0,rate=1,effectiveRate=1;};
State state(Runtime&);
bool command(Runtime&,int action,float playbackRate=-1.f,float position=-1.f);
bool consumeRestart();
std::string status(Runtime&);
void validate(Runtime&);
void judgeRateEnter(Runtime&);
void judgeRateLeave();
}