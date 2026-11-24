#include "../PhiMod/Core/PMChapterVM.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static PMOSPage page;
static int build(const char *source) {
    return PMBuildOSPage(source, strlen(source), 3, &page);
}
static void accepts(const char *source) {
    int ok = build(source);
    if (!ok) fprintf(stderr, "Unexpected rejection: %s\n%s\n", source, page.error);
    assert(ok && !page.error[0]);
}
static void rejects(const char *source, const char *message) {
    int ok = build(source);
    if (ok || !strstr(page.error, message))
        fprintf(stderr, "Expected rejection containing '%s': %s\nActual: %s\n", message, source, page.error);
    assert(!ok && strstr(page.error, message));
    assert(!page.nodes && !page.screens);
}

static void defaultsAndVideo(void) {
    accepts("home('os')");
    assert(!page.entryTransition.declared && page.entryTransition.kind == PMOSEntryTransitionNative);
    assert(page.entryTransition.load == PMOSEntryLoadCovered && page.entryTransition.screen == -1);
    assert(page.initialScreen == -1 && page.nativeChapter == 9 && page.nativePhase == 1);
    accepts("screen('map');frame{};nativeChapter(9,2);entryTransition{kind='native'}");
    assert(page.entryTransition.declared && page.initialScreen == 0 && page.nativePhase == 2);
    accepts("nativeChapter(8);entryTransition{kind='native',load='covered'}");
    assert(page.nativeChapter == 8 && page.entryTransition.load == PMOSEntryLoadCovered);
    assert(page.entryTransition.reveal == PMOSEntryRevealNative);
    accepts("entryTransition{kind='video',src='Entry.MOV'};onEnterMovie{key='arrival',src='arrival.mp4'}");
    assert(page.entryTransition.kind == PMOSEntryTransitionVideo && page.entryTransition.load == PMOSEntryLoadEnd);
    assert(!strcmp(page.entryTransition.src, "Entry.MOV") && !page.entryTransition.hasDuration);
    assert(page.entryTransition.reveal == PMOSEntryRevealNative);
    assert(!strcmp(page.entryMovieKey, "movie.arrival") && !page.entryMovieSeen);
    accepts("entryTransition{kind='video',src='entry.mP4',duration=2,load='covered',at=.75}");
    assert(page.entryTransition.hasDuration && page.entryTransition.duration == 2 && page.entryTransition.at == .75);
    accepts("entryTransition{kind='video',src='entry.mp4',load='time',at=0}");
    assert(page.entryTransition.hasAt && !page.entryTransition.hasDuration);
    accepts("entryTransition{kind='video',src='entry.mov',duration=2,load='time',at=2}");
    assert(page.entryTransition.load == PMOSEntryLoadTime);
    accepts("entryTransition{kind='video',src='\xe5\x85\xa5\xe5\x9c\xba.mov'}");
    accepts("entryTransition{kind='video',src='entry.mp4',reveal='none'}");
    assert(page.entryTransition.reveal == PMOSEntryRevealNone);
    accepts("entryTransition{kind='video',src='entry.mp4',reveal='native'}");
    assert(page.entryTransition.reveal == PMOSEntryRevealNative);
    /* No transition declaration must reset all data from the preceding page. */
    accepts("screen('first');frame{};screen('second');frame{}");
    assert(!page.entryTransition.declared && !page.entryTransition.src[0]);
    assert(!page.entryTransition.hasAt && !page.entryTransition.hasDuration);
    assert(page.entryTransition.screen == -1 && page.initialScreen == 0);
}

#define TIMELINE "entryTransition{kind='timeline',screen='intro',duration=2};screen('intro');"
static void timeline(void) {
    accepts(TIMELINE "frame{id='root',color='#102030FF',enter=.2,bob=.1,bobPeriod=2};"
        "image{parent='root',src='panel.PNG',x=.1,y=.2,w=.5,h=.6,start=.1,duration=1.8,fade=.2,fit='cover'};"
        "screen('map');hotspot{open=1}");
    const PMOSEntryTransition *entry = &page.entryTransition;
    assert(entry->kind == PMOSEntryTransitionTimeline && entry->load == PMOSEntryLoadEnd);
    assert(entry->screen == 0 && page.initialScreen == 1 && page.screens == 2 && page.nodes == 3);
    assert(page.elements[1].parent == 0 && page.elements[1].screen == 0 && page.elements[2].screen == 1);
    assert(page.elements[1].start == .1 && page.elements[1].duration == 1.8 && page.elements[1].fade == .2);
    assert(page.elements[0].motion.enter == .2 && page.elements[0].motion.bob == .1);
    accepts("screen('map');frame{};screen('intro');image{cover=1};"
        "entryTransition{kind='timeline',screen='intro',duration=3,load='covered',at=1}");
    assert(page.entryTransition.screen == 1 && page.initialScreen == 0 && page.nodes == 2);
    accepts("entryTransition{kind='timeline',screen='intro',duration=1,reveal='none'};screen('intro');frame{}");
    assert(page.entryTransition.reveal == PMOSEntryRevealNone);
    accepts(TIMELINE "frame{}");
    assert(page.entryTransition.reveal == PMOSEntryRevealNative);
    assert(page.initialScreen == -1); /* An ordinary card sheet is host-owned. */
    accepts("screen('intro');local function panel(i) frame{x=i*.1,start=i*.1,duration=.5} end;"
        "for i=1,3 do panel(i) end;screen('main');frame{};"
        "entryTransition{kind='timeline',screen='intro',duration=1,load='time',at=0}");
    assert(page.nodes == 4 && page.initialScreen == 1 && page.entryTransition.hasAt);
    assert(fabs(page.elements[2].start - .3) < 1e-12);
    const char *extensions[] = {"a.png", "a.JPG", "a.jpeg", "a.WebP"};
    for (unsigned i = 0; i < sizeof(extensions)/sizeof(*extensions); ++i) {
        char source[256];
        snprintf(source, sizeof(source), TIMELINE "image{src='%s'}", extensions[i]);
        accepts(source);
    }
    /* Ordinary maps keep their existing media and interaction rules. */
    accepts("screen('map');image{src='map.gif',loop=true,onClick=function() return {open=1} end};"
        "entryTransition{kind='timeline',screen='intro',duration=1};screen('intro');frame{}");
    assert(page.initialScreen == 0 && page.elements[0].loop && page.elements[0].handler);
}

static void transitionTimeCeiling(void) {
    assert(PMOSEntryTransitionMaxSeconds == 600);
    accepts("entryTransition{kind='video',src='entry.mov',duration=600,load='time',at=600}");
    assert(page.entryTransition.duration == 600 && page.entryTransition.at == 600);
    accepts("entryTransition{kind='video',src='entry.mp4',load='covered',at=600}");
    assert(!page.entryTransition.hasDuration && page.entryTransition.at == 600);
    accepts("entryTransition{kind='timeline',screen='intro',duration=600,load='covered',at=600};screen('intro');frame{}");
    assert(page.entryTransition.duration == 600 && page.entryTransition.at == 600);
    const char *over[] = {"600.000001", "601", "610", "1e308"};
    for (unsigned i=0; i<sizeof(over)/sizeof(*over); ++i) {
        char source[256];
        snprintf(source,sizeof(source),"entryTransition{kind='video',src='a.mp4',duration=%s}",over[i]);
        rejects(source,"duration exceeds the 600-second transition limit");
        snprintf(source,sizeof(source),"entryTransition{kind='video',src='a.mov',load='time',at=%s}",over[i]);
        rejects(source,"at exceeds the 600-second transition limit");
        snprintf(source,sizeof(source),"entryTransition{kind='timeline',screen='intro',duration=%s};screen('intro');frame{}",over[i]);
        rejects(source,"duration exceeds the 600-second transition limit");
        snprintf(source,sizeof(source),"entryTransition{kind='timeline',screen='intro',duration=600,load='covered',at=%s};screen('intro');frame{}",over[i]);
        rejects(source,"at exceeds the 600-second transition limit");
    }
    /* This is not a world/map clock limit. Preserve existing node semantics. */
    accepts("screen('map');frame{start=1000,duration=3600,fade=700,enter=800,bobPeriod=900}");
    assert(page.elements[0].start == 1000 && page.elements[0].duration == 3600);
    assert(page.elements[0].fade == 700 && page.elements[0].motion.enter == 800);
}

static void invalidSchemas(void) {
    const char *cases[][2] = {
        {"entryTransition()", "expects one table"},
        {"entryTransition('native')", "expects one table"},
        {"entryTransition({}, {})", "expects one table"},
        {"entryTransition{}", "requires kind"},
        {"entryTransition{kind='stock'}", "kind must be"},
        {"entryTransition{kind='native',load='callback'}", "load must be"},
        {"entryTransition{kind='native',reveal=.2}", "reveal must be a string"},
        {"entryTransition{kind='native',nodes={}}", "unknown entryTransition field"},
        {"entryTransition{kind='native',onEnd=function() end}", "unknown entryTransition field"},
        {"entryTransition{kind='native'};entryTransition{kind='native'}", "only one"},
        {"entryTransition{kind='native',src='a.mp4'}", "src is only"},
        {"entryTransition{kind='native',screen='intro'}", "screen is only"},
        {"entryTransition{kind='native',duration=1}", "host timing"},
        {"entryTransition{kind='native',at=0}", "at conflicts"},
        {"entryTransition{kind='native',load='time'}", "supports only load='covered'"},
        {"entryTransition{kind='video'}", "requires a local"},
        {"entryTransition{kind='video',src='a.gif'}", "requires a local"},
        {"entryTransition{kind='video',src='../a.mp4'}", "requires a local"},
        {"entryTransition{kind='video',src='sub/a.mp4'}", "requires a local"},
        {"entryTransition{kind='video',src='C:a.mp4'}", "requires a local"},
        {"entryTransition{kind='video',src='.a.mov'}", "requires a local"},
        {"entryTransition{kind='video',src='a\\nb.mp4'}", "requires a local"},
        {"entryTransition{kind='video',src='a\x7f.mp4'}", "requires a local"},
        {"entryTransition{kind='video',src='a\xc2\x80.mp4'}", "requires a local"},
        {"entryTransition{kind='video',src='a\xc0\xaf.mp4'}", "requires a local"},
        {"entryTransition{kind='video',src='a.mp4',screen='intro'}", "screen is only"},
        {"entryTransition{kind='video',src='a.mp4',load='covered'}", "requires at"},
        {"entryTransition{kind='video',src='a.mp4',load='end',at=1}", "at conflicts"},
        {"entryTransition{kind='video',src='a.mp4',duration=0}", "must be positive"},
        {"entryTransition{kind='video',src='a.mp4',duration=-1}", "finite nonnegative"},
        {"entryTransition{kind='video',src='a.mp4',duration=0/0}", "finite nonnegative"},
        {"entryTransition{kind='video',src='a.mp4',duration=1/0}", "finite nonnegative"},
        {"entryTransition{kind='video',src='a.mp4',duration='1'}", "must be a number"},
        {"entryTransition{kind='video',src='a.mp4',load='time',at=-1}", "finite nonnegative"},
        {"entryTransition{kind='video',src='a.mp4',load='time',at=1/0}", "finite nonnegative"},
        {"entryTransition{kind='video',src='a.mp4',duration=1,load='time',at=2}", "exceeds duration"},
        {"entryTransition{kind='timeline',duration=1}", "requires screen"},
        {"entryTransition{kind='timeline',screen='intro'}", "requires duration"},
        {"entryTransition{kind='timeline',screen='intro',duration=1,src='a.mp4'}", "src is only"},
        {"entryTransition{kind='timeline',screen='intro',duration=1}", "unknown entryTransition screen"},
        {TIMELINE, "requires frame or image"},
        {TIMELINE "frame{onUpdate=function() end}", "unsupported entryTransition timeline node field"},
        {TIMELINE "frame{src='ignored.png'}", "unsupported entryTransition timeline node field"},
        {"entryTransition{kind='native',load='end'}", "supports only load='covered'"},
        {"entryTransition{kind='native',load='time',at=0}", "supports only load='covered'"},
        {"entryTransition{kind='native',reveal='none'}", "reveal is only valid"},
        {"entryTransition{kind='native',reveal='native'}", "reveal is only valid"},
        {"entryTransition{kind='video',src='a.mp4',reveal=false}", "reveal must be a string"},
        {"entryTransition{kind='video',src='a.mp4',reveal='fade'}", "reveal must be native or none"},
        {"entryTransition{kind=1}", "kind must be a string"},
        {"entryTransition{kind='native',load=false}", "load must be a string"},
        {"entryTransition{kind='video',src=42}", "src must be a string"},
        {"entryTransition{kind='timeline',screen=false,duration=1}", "screen must be a string"},
        {"entryTransition{kind='native',load='time',at='0'}", "at must be a number"},
        {TIMELINE "image{src='a.gif'}", "still image"},
        {TIMELINE "image{src='a.mp4'}", "still image"},
        {TIMELINE "image{src='a.mov'}", "still image"},
        {TIMELINE "image{src='a.svg'}", "still image"},
        {TIMELINE "image{src='a.png',loop=true}", "passive motion"},
        {TIMELINE "frame{tapTime=.1}", "passive motion"},
        {TIMELINE "frame{tapFlash=.1}", "passive motion"},
        {TIMELINE "frame{tapScale=1.2}", "passive motion"},
        {TIMELINE "frame{onClick=function() end}", "noninteractive"},
        {TIMELINE "image{src='a.png',open=1}", "noninteractive"},
        {TIMELINE "hotspot{open=1}", "noninteractive"},
        {TIMELINE "frame{to='map'};screen('map');frame{}", "noninteractive"},
        {TIMELINE "frame{};screen('map');hotspot{to='intro'}", "reserved"},
        {"screen('map');frame{to='intro'};" TIMELINE "frame{}", "reserved"},
        {TIMELINE "frame{challenge='anything'}", "noninteractive"},
    };
    for (unsigned i = 0; i < sizeof(cases)/sizeof(*cases); ++i) rejects(cases[i][0], cases[i][1]);
    char longName[400]; memset(longName, 'a', 260); longName[260] = 0;
    char source[512]; snprintf(source, sizeof(source), "entryTransition{kind='video',src='%s.mp4'}", longName);
    rejects(source, "oversized");
    rejects("entryTransition{kind='video',src='a\\0.mp4'}", "contains NUL");
}

typedef struct { int commits; } Store;
static int readFlag(void *context, const char *key, int *value) {
    (void)context; (void)key; *value=0; return 1;
}
static int commit(void *context, const PMOSProgressChange *changes, size_t count) {
    (void)changes; (void)count; ++((Store *)context)->commits; return 1;
}
static void callbackIsolation(void) {
    const char *source = TIMELINE "frame{};screen('map');"
        "hotspot{onClick=function() progress.set('x',1);return {to='intro'} end};"
        "hotspot{onClick=function() return {checkpoint={mode='session',page='intro'}} end};"
        "hotspot{onClick=function() entryTransition{kind='native'} end};"
        "hotspot{onClick=function() return {open=2} end};"
        "hotspot{onClick=function() return {to='map'} end};"
        "hotspot{onClick=function() return {checkpoint={mode='relaunch',page='intro'}} end};"
        "hotspot{onClick=function() return {checkpoint={mode='session',page='map'}} end}";
    Store store={0}; PMOSProgress progress={&store,readFlag,commit};
    PMOSSession *session=PMOSStartWithProgress(source,strlen(source),3,&page,progress);
    assert(session && page.initialScreen == 1 && page.nodes == 8);
    memset(&page, 0, sizeof(page)); /* Session owns its destination restrictions. */
    PMOSAction action;
    for (int node=0;node<=3;++node) {
        assert(!PMOSClick(session,node,&action));
        assert(action.error[0] && action.dest == -1 && !action.song && !action.checkpoint);
        assert(strstr(action.error,node==0 ? "noninteractive" : node==3 ? "declarations are closed" : "reserved"));
    }
    assert(!store.commits);
    assert(PMOSClick(session,4,&action) && action.song == 2);
    assert(PMOSClick(session,5,&action) && action.dest == 1);
    assert(!PMOSClick(session,6,&action) && strstr(action.error,"reserved"));
    assert(PMOSClick(session,7,&action) && action.dest == 1 && action.checkpoint == 1);
    PMOSStop(session);
}

int main(void) {
    defaultsAndVideo(); timeline(); transitionTimeCeiling(); invalidSchemas(); callbackIsolation();
    puts("chapter entry transition VM tests passed");
    return 0;
}
