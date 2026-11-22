#pragma once
#include "PMIL2CPP.hpp"
#include "PMNativeOSRows.hpp"
#include "PMNativeOSScene.hpp"
namespace pmsecretcourse {
using pmbridge::Runtime; using pmbridge::P;
struct Pin {
    Runtime &r; uint32_t handle;
    Pin(Runtime &r,P obj):r(r),handle(obj?r.gchandle_new(obj,false):0){
        if(obj && !handle) throw std::runtime_error("Cannot retain course object");
    }
    ~Pin(){if(handle)r.gchandle_free(handle);}
    Pin(const Pin&)=delete;
    P get()const{return handle?r.gchandle_get_target(handle):nullptr;}
};
bool active();
bool backendReady();
void bindChart(Runtime&,P song,NSDictionary *chart);
NSDictionary *binding(Runtime&,P song);
void clearBindings(Runtime&);
bool launch(Runtime&, P list, NSString *chapter, NSString *door, NSInteger tier, bool noPause);
P pauseOwner();
void level(Runtime&,P progress);
void result(Runtime&);
P resultList(Runtime&);
void progressFrame(Runtime&,P progress);
void menu(Runtime&);
}
