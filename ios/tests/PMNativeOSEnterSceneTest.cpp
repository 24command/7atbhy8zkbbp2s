#include "../PhiMod/Sources/PMNativeOSEnterScene.hpp"
#include <cassert>
#include <cmath>
#include <cstdio>
using pmnativeenterscene::Clock;
int main(){
 Clock c;assert(!c.due(100,9));c.shown(NAN);assert(!c.running);
 c.shown(100);c.shown(103);assert(c.began==100);
 assert(!c.claim(108.999,9));assert(!c.claim(99,9));assert(!c.claim(NAN,9));
 assert(c.claim(109,9));assert(c.committing);assert(!c.claim(110,9));
 c.complete();assert(c.finished&&!c.running&&!c.committing);c.shown(200);assert(!c.claim(220,9));
 c.reset();assert(!c.finished&&!c.running);c.shown(400);assert(!c.claim(408,9));assert(c.claim(450,9));
 // Invalidated visit resets its entire clock; an old elapsed value cannot claim
 // before a new rendered scene explicitly announces its start.
 c.reset();assert(!c.claim(1000,9));c.shown(1000);assert(!c.claim(1001,9));
 std::puts("native entry-scene clock passed");
}
