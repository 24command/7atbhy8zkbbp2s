#include "../PhiMod/Core/PMChapterVM.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static PMOSPage p;
static int run(const char *s){return PMBuildOSPage(s,strlen(s),3,&p);}
int main(void){assert(run("return {}")&&!p.listFirst&&!p.count);assert(run("home('list'); for i=1,song_count do card(i,'Title','Body') end"));assert(p.listFirst&&p.count==3&&p.cards[2].song==3&&!strcmp(p.cards[1].caption,"Body"));
 assert(!run("card(4)")&&strstr(p.error,"os.lua:1:"));assert(!run("home('bad')"));assert(!run("while true do end")&&strstr(p.error,"limit"));assert(!run("local t='a';for i=1,30 do t=t..t end"));assert(!run("require('os')"));assert(!run("for i=1,129 do card(1) end"));assert(!run("card("));assert(!run("\033Lua"));assert(run("card(2)")&&p.count==1);puts("chapter OS Lua tests passed");return 0;}
