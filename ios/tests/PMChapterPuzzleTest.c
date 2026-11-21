#include "../PhiMod/Core/PMChapterVM.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

/* One Store models one chapter's callback context. Retain it, not the VM,
   across starts. A rejected batch is never visible on the next click. */
typedef struct { int lock, map, reward, commits, reject, failRead, lockA, lockB, east, west; } Store;
static int *slot(Store *s, const char *key) {
    if (!strcmp(key, "puzzle.lock")) return &s->lock;
    if (!strcmp(key, "puzzle.map")) return &s->map;
    if (!strcmp(key, "puzzle.lock.A")) return &s->lockA;
    if (!strcmp(key, "puzzle.lock.B")) return &s->lockB;
    if (!strcmp(key, "puzzle.map.east")) return &s->east;
    if (!strcmp(key, "puzzle.map.west")) return &s->west;
    assert(!strcmp(key, "reward")); return &s->reward;
}
static int readKey(void *ctx, const char *key, int *out) {
    Store *s = ctx;
    if (s->failRead) return 0;
    *out = *slot(s, key); return 1;
}
static int commit(void *ctx, const PMOSProgressChange *changes, size_t n) {
    Store *s = ctx;
    if (s->reject) return 0;
    assert(n > 0);
    for (size_t i = 0; i < n; ++i) *slot(s, changes[i].key) = changes[i].value;
    ++s->commits; return 1;
}
static PMOSPage page;
static PMOSSession *start(const char *src, Store *s) {
    PMOSProgress cb = {s, readKey, commit};
    PMOSSession *vm = PMOSStartWithProgress(src, strlen(src), 6, &page, cb);
    if (!vm) fprintf(stderr, "start: %s\n", page.error);
    assert(vm); return vm;
}
static void click(PMOSSession *vm, int node, int expected) {
    PMOSAction a;
    int ok = PMOSClick(vm, node, &a);
    if (!ok || a.song != expected) fprintf(stderr, "node %d: expected %d, got %d (%s)\n", node, expected, a.song, a.error);
    assert(ok && a.song == expected);
}
static void fails(PMOSSession *vm, int node, const char *msg) {
    PMOSAction a; assert(!PMOSClick(vm, node, &a));
    assert(strstr(a.error, msg) && a.song == 0 && a.dest == -1);
}
static const char script[] =
    "local pieces={'A','B','A'}; puzzle.define{id='lock',mode='ordered',pieces=pieces}; pieces[1]='C';"
    "puzzle.define{id='map',mode='set',pieces={'east','west'}};"
    "local code={advanced=1, solved=2, complete=3, invalid=4, wrong=5, duplicate=6};"
    "local function use(id,p) return function() local r=puzzle.submit(id,p);"
    " if r=='solved' then progress.set('reward',progress.get('reward')+1) end; return {open=code[r]} end end;"
    "frame{onClick=use('lock','A')}; image{cover=1,onClick=use('lock','B')};"
    "hotspot{onClick=use('map','west')}; screen('other'); frame{onClick=use('map','east')};"
    "hotspot{onClick=function() if puzzle.submit('map')=='invalid' and puzzle.submit('map',nil)=='invalid'"
    " and puzzle.submit('map','')=='invalid' and puzzle.submit('map','missing')=='invalid'"
    " and puzzle.submit('map',4)=='invalid' and puzzle.submit('map','west\\0')=='invalid' then return {open=4} end end};"
    "hotspot{onClick=function() local n,t,s=puzzle.status('lock'); local m=puzzle.missing('lock');"
    " if t==3 and #m==t-n and s==(n==t) then return {open=n+1} end end};"
    "hotspot{onClick=function() local n,t,s=puzzle.status('map'); local m=puzzle.missing('map');"
    " if t==2 and #m==t-n and s==(n==t) and (n==2 or m[1]=='east') then return {open=n+1} end end};"
    "hotspot{onClick=function() puzzle.submit('map','east'); progress.set('reward',10); return {to='typo'} end};"
    "hotspot{onClick=function() puzzle.define{id='late',mode='set',pieces={'A'}} end};";

static void testPlay(void) {
    Store store = {0}, other = {0};
    PMOSSession *vm = start(script, &store);
    click(vm, 1, 5); click(vm, 4, 4); click(vm, 5, 1); click(vm, 6, 1);
    assert(!store.commits);
    click(vm, 0, 1); click(vm, 0, 5); click(vm, 2, 1); click(vm, 2, 6);
    assert(store.commits == 2 && !store.reward);
    fails(vm, 7, "unknown"); fails(vm, 8, "declarations are closed");
    assert(store.commits == 2 && !store.reward);
    PMOSStop(vm);
    vm = start(script, &store);
    click(vm, 5, 2); click(vm, 6, 2);
    store.reject = 1; fails(vm, 3, "commit failed"); store.reject = 0;
    click(vm, 6, 2); assert(!store.reward);
    click(vm, 3, 2); click(vm, 1, 1); click(vm, 0, 2);
    assert(store.commits == 5 && store.reward == 2);
    PMOSStop(vm);
    vm = start(script, &store);
    click(vm, 0, 3); click(vm, 2, 3); click(vm, 4, 4); click(vm, 5, 4); click(vm, 6, 3);
    assert(store.commits == 5 && store.reward == 2);
    PMOSSession *isolated = start(script, &other); click(isolated, 5, 1); click(isolated, 6, 1);
    PMOSStop(isolated);
    store.failRead = 1; fails(vm, 0, "read failed"); store.failRead = 0;
    store.map = 4; fails(vm, 3, "saved puzzle progress"); fails(vm, 6, "saved puzzle progress");
    store.lock = -1; fails(vm, 5, "saved puzzle progress"); store.lock = 4; fails(vm, 1, "saved puzzle progress");
    assert(store.commits == 5); PMOSStop(vm);
}

static void testValidation(void) {
    const char *bad[] = {"{}", "{id='a',mode='set'}", "{id='a',mode='set',pieces={}}",
        "{id='a',mode='set',pieces={'a','a'}}", "{id='a',mode='set',pieces={'a',[3]='b'}}",
        "{id='a',mode='set',pieces={'a',extra='b'}}", "{id='a',mode='set',pieces={1}}",
        "{id='a',mode='set',pieces={'a\\0'}}", "{id='a',mode='set',pieces={''}}",
        "{id='bad/id',mode='set',pieces={'a'}}", "{id='a',mode='sets',pieces={'a'}}",
        "{id='a',mode='set',pieces={'a'}}; puzzle.define{id='a',mode='set',pieces={'b'}}"};
    for (size_t i=0; i<sizeof(bad)/sizeof(bad[0]); ++i) {
        char src[256]; snprintf(src, sizeof(src), "puzzle.define%s", bad[i]);
        assert(!PMBuildOSPage(src, strlen(src), 0, &page) && page.error[0]);
    }
    const char *noid = "puzzle.submit('other','A')";
    assert(!PMBuildOSPage(noid, strlen(noid), 0, &page) && strstr(page.error, "unknown puzzle"));
}
static void testLimits(void) {
    const char *src = "local t={}; for i=1,31 do t[i]='k'..i end; puzzle.define{id='map',mode='set',pieces=t};"
        "hotspot{onClick=function() for i=31,1,-1 do local r=puzzle.submit('map',t[i]);"
        " if r~=(i==1 and 'solved' or 'advanced') then return {open=2} end end;"
        " local n,_,s=puzzle.status('map'); if n==31 and s then return {open=1} end end};"
        "hotspot{onClick=function() for i=1,129 do puzzle.status('map') end end};";
    Store store={0}; PMOSSession *vm=start(src,&store); click(vm,0,1);
    assert(store.commits==1 && store.map==2147483647); fails(vm,1,"access limit"); PMOSStop(vm);
    const char *tooMany="local t={}; for i=1,32 do t[i]='x' end; puzzle.define{id='x',mode='ordered',pieces=t}";
    assert(!PMBuildOSPage(tooMany,strlen(tooMany),0,&page));
}
/* This fixture also runs unchanged against the historical G VM. Seed the
   callback store directly to model a save written before the API merge. */
static void testLegacyPlay(void) {
    const char *src =
        "puzzle{id='lock',mode='ordered',pieces={'A','B'}};"
        "puzzle{id='map',mode='set',pieces={'east','west'}};"
        "hotspot{onClick=function() if puzzleSolved('lock')==false and puzzleSubmit('lock','B')==false"
        " and puzzleSubmit('lock','unknown')==false then return {open=1} end end};"
        "hotspot{onClick=function() if puzzleSubmit('lock','A')==true and puzzleSubmit('lock','A')==false"
        " and puzzleSolved('lock')==true then return {open=2} end end};"
        "hotspot{onClick=function() if puzzleSubmit('map','west')==true and puzzleSolved('map')==true"
        " then progress.set('reward',1); return {open=3} end end};"
        "hotspot{onClick=function() if puzzleSolved('lock')==true and puzzleSolved('map')==true"
        " and progress.get('puzzle.lock.A')==1 and progress.get('puzzle.map.west')==1"
        " and puzzleSubmit('map','west')==false then return {open=4} end end};"
        "hotspot{onClick=function() if puzzleSubmit('map','west')==true and puzzleSolved('map')==false"
        " then return {open=5} end end};"
        "hotspot{onClick=function() puzzleSubmit('map','west'); return {to='unknown'} end};";
    Store s = {0};
    s.lockB = s.east = 1; /* A non-prefix ordered save and a partially solved set. */
    s.lockA = -1;
    s.west = 2; /* G treats exactly 1 as collected. */
    PMOSSession *vm = start(src, &s);
    click(vm, 0, 1);
    click(vm, 1, 2);
    assert(s.lockA == 1 && s.lockB == 1 && s.commits == 1);
    fails(vm, 5, "unknown");
    s.reject = 1; fails(vm, 2, "commit failed"); s.reject = 0;
    assert(s.west == 2 && !s.reward && s.commits == 1);
    click(vm, 2, 3);
    assert(s.east == 1 && s.west == 1 && s.reward == 1 && s.commits == 2);
    assert(!s.lock && !s.map);
    PMOSStop(vm);
    vm = start(src, &s);
    click(vm, 3, 4);
    assert(s.commits == 2);
    PMOSStop(vm);
    Store fresh = {0}; vm = start(src, &fresh);
    click(vm, 0, 1); /* B is uncollected but out of order. */
    click(vm, 4, 5); /* The same submission order is valid for a set. */
    assert(fresh.commits == 1 && fresh.west == 1 && !fresh.east && !fresh.lockB);
    PMOSStop(vm);
}

static void testLegacyValidation(void) {
    const char *bad[] = {
        "puzzle{id='a.b',mode='set',pieces={'x'}}", "puzzle{id='a',mode='set',pieces={'x.y'}}",
        "puzzle{id='a',mode='ordered',pieces={'x','x'}}", "puzzle{id='a',mode='set',pieces={'bad/id'}}",
        "puzzle{id='a',mode='set',pieces={'x',[3]='z'}}", "puzzleSolved('missing')",
        "puzzle{id='a',mode='set',pieces={'x'}}; puzzleSubmit('a')",
        "puzzle{id='a',mode='set',pieces={'x'}}; puzzleSubmit('a','bad.name')",
        "puzzle{id='a',mode='set',pieces={'x'}}; puzzleSolved('a',1)"
    };
    for (size_t i = 0; i < sizeof(bad)/sizeof(bad[0]); ++i)
        assert(!PMBuildOSPage(bad[i], strlen(bad[i]), 0, &page) && page.error[0]);
    char src[256];
    for (int n = 32; n <= 33; ++n) {
        snprintf(src, sizeof(src), "local t={}; for i=1,%d do t[i]='p'..i end; puzzle{id='a',mode='set',pieces=t}", n);
        assert(PMBuildOSPage(src, strlen(src), 0, &page) == (n == 32));
        snprintf(src, sizeof(src), "for i=1,%d do puzzle{id='p'..i,mode='set',pieces={'x'}} end", n);
        assert(PMBuildOSPage(src, strlen(src), 0, &page) == (n == 32));
    }
    for (int n = 28; n <= 29; ++n) {
        snprintf(src, sizeof(src), "local x=''; for i=1,%d do x=x..'x' end; puzzle{id=x,mode='set',pieces={x}}", n);
        assert(PMBuildOSPage(src, strlen(src), 0, &page) == (n == 28));
    }
}

static void testMixedFormats(void) {
    const char *src = "puzzle{id='lock',mode='set',pieces={'A'}};"
        "puzzle.define{id='lock',mode='ordered',pieces={'A','A'}};"
        "hotspot{onClick=function() if puzzleSubmit('lock','A') and puzzleSolved('lock')"
        " and puzzle.submit('lock','A')=='advanced' then return {open=1} end end};"
        "hotspot{onClick=function() if puzzleSolved('lock') and puzzle.submit('lock','A')=='solved'"
        " then return {open=2} end end};";
    Store s = {0}; PMOSSession *vm = start(src, &s);
    click(vm, 0, 1); PMOSStop(vm);
    assert(s.lockA == 1 && s.lock == 1 && s.commits == 1);
    vm = start(src, &s); click(vm, 1, 2); PMOSStop(vm);
    assert(s.lockA == 1 && s.lock == 2 && s.commits == 2);
    const char *legacy = "puzzle{id='lock',mode='set',pieces={'A'}};";
    const char *modern = "puzzle.define{id='lock.A',mode='set',pieces={'A'}};";
    for (int first = 0; first < 2; ++first) {
        char clash[160]; snprintf(clash, sizeof(clash), "%s%s", first ? legacy : modern, first ? modern : legacy);
        assert(!PMBuildOSPage(clash, strlen(clash), 0, &page) && strstr(page.error,"overlapping puzzle save key"));
    }
}

int main(int argc, char **argv) {
    testLegacyPlay(); testLegacyValidation();
    if (!(argc == 2 && !strcmp(argv[1], "--legacy"))) {
        testMixedFormats(); testPlay(); testValidation(); testLimits();
    }
    puts("chapter puzzle tests passed"); return 0;
}
