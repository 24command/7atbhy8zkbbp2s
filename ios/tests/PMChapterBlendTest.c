#include "../PhiMod/Core/PMChapterVM.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
static PMOSPage page;
static void ok(const char *s){assert(PMBuildOSPage(s,strlen(s),1,&page));}
static void no(const char *s){assert(!PMBuildOSPage(s,strlen(s),1,&page));}
int main(void){
 ok("image{src='x.pma',blend='add'}");assert(page.elements[0].blend==PMOSBlendAdd);
 ok("image{src='x.png'}; image{src='y.png',blend='normal'}");assert(page.elements[0].blend==0&&page.elements[1].blend==0);
 no("frame{blend='add'}");no("hotspot{open=1,blend='add'}");no("image{src='x.png',blend=1}");
 no("image{src='x.png',blend=true}");no("image{src='x.png',blend='Add'}");no("image{src='x.png',blend='multiply'}");
 no("image{src='x.png',blend='add'..string.char(0)}");
 no("screen('map');frame{};screen('entry');image{src='x.png',blend='add'};entryTransition{kind='timeline',screen='entry',duration=2}");
 ok("screen('map');image{src='x.png',blend='add'};screen('entry');image{src='x.png'};entryTransition{kind='timeline',screen='entry',duration=2}");
 puts("chapter image blend schema passed");return 0;
}
