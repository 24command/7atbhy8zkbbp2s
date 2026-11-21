#include "../PhiMod/Core/PMChapterVM.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static PMOSPage p;
static int run(const char *s){return PMBuildOSPage(s,strlen(s),3,&p);}
static void testLayout(void){
 assert(run("canvas(16,9); screen('map');frame{id='panel',x=.2,w=.5,color='#11223344'}; image{parent='panel',cover=1,open=2};hotspot{parent='panel',x=.5,w=.5,to='east'};screen('east');image{src='gate.png',open=2}; frame{label='Back',to='map'}"));
 assert(p.screens==2&&p.nodes==5&&p.aspect>1.77&&p.aspect<1.78);
 assert(p.elements[0].rgba==0x11223344&&p.elements[1].parent==0&&p.elements[1].cover==1&&p.elements[1].open==2);
 assert(p.elements[2].dest==1&&p.elements[2].x==.5&&p.elements[4].dest==0);
 assert(!run("image{src='../outside.png'}"));assert(!run("image{src='a.png',cover=1}"));
 assert(!run("frame{parent='later'}"));assert(!run("frame{id='x'};frame{id='x'}"));
 assert(!run("frame{w=0}"));assert(!run("frame{x=0/0}"));assert(!run("hotspot{open=4}"));
 assert(!run("hotspot{to='missing'}"));assert(!run("hotspot{open=1,to='other'}"));
 assert(run("frame{id='a'};frame{id='b',parent='a'};hotspot{parent='b',open=3}"));assert(p.elements[2].depth==2);
}
static PMOSSession *start(const char *source) {
    return PMOSStart(source, strlen(source), 3, &p);
}

static void expectAction(PMOSSession *s, int node, int song, int dest) {
    PMOSAction a;
    memset(&a, 0x55, sizeof(a));
    assert(PMOSClick(s, node, &a));
    assert(a.song == song && a.dest == dest && a.element == -1 && !a.visible && !a.error[0]);
}

static void expectFailure(PMOSSession *s, int node, const char *message) {
    PMOSAction a;
    memset(&a, 0x55, sizeof(a));
    assert(!PMOSClick(s, node, &a));
    assert(!a.song && a.dest == -1 && a.element == -1 && !a.visible && a.error[0] && strstr(a.error, message));
}

static void testPersistentClicks(void) {
    char source[] = "local n=0; screen('start');"
        "frame{onClick=function() n=n+1; return {open=n} end};"
        "image{src='story.gif',loop=true,onClick=function() "
        "if n==2 then return {to='end'} end end};"
        "hotspot{to='end'}; screen('end'); hotspot{open=3}; frame{}";
    PMOSSession *first = start(source);
    assert(first && p.nodes == 5 && p.screens == 2 && p.elements[1].loop);
    assert(p.elements[0].handler && p.elements[1].handler && !p.elements[2].handler);
    PMOSSession *second = start(source);
    assert(second);
    memset(source, 0, sizeof(source));
    memset(&p, 0, sizeof(p));
    expectAction(first, 0, 1, -1);
    expectAction(first, 1, 0, -1);
    expectAction(first, 0, 2, -1);
    expectAction(first, 1, 0, 1);
    expectAction(second, 0, 1, -1);
    PMOSStop(second);
    expectAction(first, 2, 0, 1);
    expectAction(first, 3, 3, -1);
    expectAction(first, 4, 0, -1);
    expectFailure(first, -1, "node");
    expectFailure(first, 5, "node");
    assert(!PMOSClick(first, 0, NULL));
    PMOSStop(first);
    PMOSStop(NULL);
    expectFailure(NULL, 0, "node");
}

static void testHandlerFailures(void) {
    assert(!run("frame{onClick=1}"));
    assert(!run("hotspot{onClick=false}"));
    assert(!run("hotspot{onClick=function() end, open=1}"));
    assert(!run("image{src='art',onClick=function() end,to='main'}"));
    const char *bad[] = {
        "home('list')", "card(1)", "screen('x')", "canvas(2,1)",
        "frame{}", "image{cover=1}", "hotspot{open=1}",
        "return 1", "return {}", "return {open=0}", "return {open=4}",
        "return {open=1.5}", "return {open='1'}", "return {to='missing'}",
        "return {show=false}", "return {hide=1}", "return {show=''}",
        "return {show='x',hide='x'}", "return {show='x',open=2}", "return {to=false}", "return {to='main',open=1}", "return {open=1,extra=true}",
        "return {to='main\\0suffix'}", "return {1}", "return nil, 2", "missing()",
        "return load('return 1')()", "return io.open('chapter')"
    };
    for (size_t i = 0; i < sizeof(bad)/sizeof(bad[0]); ++i) {
        char source[384];
        snprintf(source, sizeof(source), "local first=true; hotspot{id='x',onClick=function() "
            "if first then first=false; %s end; return {to='main'} end}", bad[i]);
        PMOSSession *s = start(source);
        assert(s);
        expectFailure(s, 0, i < 7 ? "declarations are closed" : "");
        expectAction(s, 0, 0, 0);
        assert(p.nodes == 1 && p.screens == 1 && !p.count && !p.listFirst && !p.aspect);
        PMOSStop(s);
    }
}

static void testNodeTiming(void) {
    assert(run("frame{}; image{src='a',start=2.25,duration=4.5,fade=.5};"
               "hotspot{open=1,start=3,duration=0,hidden=true}"));
    assert(p.elements[0].start == 0 && p.elements[0].duration == 0 && p.elements[0].fade == 0);
    assert(p.elements[1].start == 2.25 && p.elements[1].duration == 4.5 && p.elements[1].fade == .5);
    assert(p.elements[2].start == 3 && p.elements[2].duration == 0 && p.elements[2].hidden);
    assert(!run("frame{start=-1}"));
    assert(!run("frame{duration=0/0}"));
    assert(!run("frame{fade=1/0}"));
    assert(!run("frame{fade='2'}"));
    assert(!run("frame{start=1e308,duration=1e308}"));
}

static void testVisibility(void) {
    assert(!run("frame{hidden=1}"));
    assert(!run("image{src='a',hidden='false'}"));
    PMOSSession *s = start("screen('map'); frame{id='panel',hidden=true};"
        "hotspot{hidden=false,onClick=function() return {show='panel'} end};"
        "screen('east'); local show=false; hotspot{onClick=function() show=not show; "
        "if show then return {show='panel'} else return {hide='panel'} end end};"
        "image{id='panel',cover=1,hidden=true}; frame{id='east-only'};"
        "screen('west'); hotspot{onClick=function() return {hide='east-only'} end}");
    assert(s && p.elements[0].hidden && !p.elements[1].hidden);
    assert(!p.elements[2].hidden && p.elements[3].hidden);
    memset(&p, 0, sizeof(p));
    PMOSAction a;
    assert(PMOSClick(s, 1, &a) && a.element == 0 && a.visible == 1);
    assert(PMOSClick(s, 2, &a) && a.element == 3 && a.visible == 1);
    assert(PMOSClick(s, 2, &a) && a.element == 3 && !a.visible);
    assert(!a.song && a.dest == -1 && !a.error[0]);
    expectFailure(s, 5, "unknown element");
    PMOSStop(s);
}

static void testClickBudgets(void) {
    const char *source = "local n=0; local blocks={}; local block='x';"
        "for i=1,19 do block=block..block end;"
        "hotspot{onClick=function() while true do end end};"
        "hotspot{onClick=function() local v=0; for i=1,20000 do v=v+i end; return nil end};"
        "hotspot{onClick=function() n=n+1; blocks[n]=block..n end};"
        "hotspot{onClick=function() blocks={}; return {open=2} end}";
    PMOSSession *s = start(source);
    assert(s);
    for (int i = 0; i < 20; ++i) expectAction(s, 1, 0, -1);
    for (int i = 0; i < 3; ++i) expectFailure(s, 0, "instruction limit");
    PMOSAction a;
    int kept = 0;
    while (kept < 16 && PMOSClick(s, 2, &a)) ++kept;
    assert(kept > 0 && kept < 16 && strstr(a.error, "memory"));
    assert(!a.song && a.dest == -1);
    expectAction(s, 3, 2, -1);
    expectAction(s, 2, 0, -1);
    PMOSStop(s);
    assert(!PMOSStart("x", 2097153, 1, &p) && p.error[0]);
}

int main(void){testLayout();testPersistentClicks();testHandlerFailures();testNodeTiming();testVisibility();testClickBudgets();assert(run("return {}")&&!p.listFirst&&!p.count);assert(run("home('list'); for i=1,song_count do card(i,'Title','Body') end"));assert(p.listFirst&&p.count==3&&p.cards[2].song==3&&!strcmp(p.cards[1].caption,"Body"));
 assert(!run("card(4)")&&strstr(p.error,"os.lua:1:"));assert(!run("home('bad')"));assert(!run("while true do end")&&strstr(p.error,"limit"));assert(!run("local t='a';for i=1,30 do t=t..t end"));assert(!run("require('os')"));assert(!run("for i=1,129 do card(1) end"));assert(!run("card("));assert(!run("\033Lua"));assert(run("card(2)")&&p.count==1);puts("chapter OS Lua tests passed");return 0;}
