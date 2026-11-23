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
    assert(!a.challenge && !a.checkpoint && !a.difficulty[0]);
    assert(a.song == song && a.dest == dest && a.element == -1 && !a.visible && !a.error[0]);
}

static void expectFailure(PMOSSession *s, int node, const char *message) {
    PMOSAction a;
    memset(&a, 0x55, sizeof(a));
    assert(!PMOSClick(s, node, &a));
    assert(!a.challenge && !a.checkpoint && !a.difficulty[0]);
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

static void testCheckpoints(void) {
    PMOSSession *s = start("screen('map');"
        "hotspot{onClick=function() return {checkpoint={mode='session',page='end'}} end};"
        "hotspot{onClick=function() return {checkpoint={song=3,difficulty='IN',mode='relaunch'}} end};"
        "screen('end');"
        "hotspot{onClick=function() return {checkpoint={page='map',mode='relaunch'}} end};"
        "hotspot{onClick=function() return {checkpoint={mode='session',song=1}} end}");
    assert(s);
    memset(&p, 0, sizeof(p));
    PMOSAction a;
    const int modes[] = {1, 2, 2, 1}, songs[] = {0, 3, 0, 1}, dests[] = {1, -1, 0, -1};
    for (int i = 0; i < 4; ++i) {
        assert(PMOSClick(s, i, &a));
        assert(a.checkpoint == modes[i] && a.song == songs[i] && a.dest == dests[i]);
        assert(!strcmp(a.difficulty, i == 1 ? "IN" : ""));
        assert(a.element == -1 && !a.visible && !a.error[0]);
    }
    PMOSStop(s);

    const char *bad[] = {
        "false", "{}", "{song=1}", "{mode='session'}", "{mode='session',song=1,page='main'}",
        "{mode='Session',song=1}", "{mode='relaunch ',song=1}", "{mode=false,page='main'}",
        "{mode='session',page='missing'}", "{mode='session',page=1}",
        "{mode='session',page='main',difficulty='IN'}", "{mode='session',song=0}",
        "{mode='session',song=4}", "{mode='session',song=1.5}", "{mode='session',song='1'}",
        "{mode='session',song=1,difficulty=false}", "{mode='session',song=1,difficulty=''}",
        "{mode='session',song=1,extra=true}", "{mode='session',song=1,[1]=true}",
        "{mode='session\\0',song=1}", "{mode='session',page='main\\0x'}",
        "{mode='session',song=1,difficulty='IN\\0x'}", "{mode='session',['song\\0']=1}",
        "{mode='session',song=1,difficulty='IN'},open=2"
    };
    char source[384];
    for (size_t i = 0; i < sizeof(bad)/sizeof(bad[0]); ++i) {
        snprintf(source, sizeof(source), "hotspot{onClick=function() return {checkpoint=%s} end};"
                 "hotspot{open=2}", bad[i]);
        s = start(source);
        assert(s);
        expectFailure(s, 0, "");
        expectAction(s, 1, 2, -1);
        PMOSStop(s);
    }

    char difficulty[97];
    memset(difficulty, 'x', sizeof(difficulty));
    for (size_t len = 95; len <= 96; ++len) {
        difficulty[len] = 0;
        snprintf(source, sizeof(source), "hotspot{onClick=function() return "
                 "{checkpoint={mode='session',song=1,difficulty='%s'}} end}", difficulty);
        s = start(source);
        assert(s);
        if (len == 95) {
            assert(PMOSClick(s, 0, &a) && !strcmp(a.difficulty, difficulty));
        } else expectFailure(s, 0, "oversized");
        PMOSStop(s);
        difficulty[len] = 'x';
    }
}

typedef struct {
    PMOSProgressChange entries[PMOSProgressAccessLimit];
    size_t count, lastBatch;
    int reads, commits, failRead, failCommit;
} TestStore;

static size_t storeIndex(TestStore *store, const char *key) {
    for (size_t i = 0; i < store->count; ++i)
        if (!strcmp(store->entries[i].key, key)) return i;
    return store->count;
}

static int storeRead(void *context, const char *key, int *value) {
    TestStore *store = context;
    ++store->reads;
    if (store->failRead) return 0;
    size_t index = storeIndex(store, key);
    *value = index == store->count ? 0 : store->entries[index].value;
    return 1;
}

static int storeCommit(void *context, const PMOSProgressChange *changes, size_t count) {
    TestStore *store = context;
    ++store->commits;
    store->lastBatch = count;
    assert(count && count <= PMOSProgressAccessLimit);
    if (store->failCommit) return 0;
    for (size_t i = 0; i < count; ++i) {
        size_t index = storeIndex(store, changes[i].key);
        assert(index < PMOSProgressAccessLimit);
        if (index == store->count) ++store->count;
        store->entries[index] = changes[i];
    }
    return 1;
}

static PMOSSession *startProgress(const char *src, TestStore *store) {
    PMOSProgress callbacks = {store, storeRead, storeCommit};
    return PMOSStartWithProgress(src, strlen(src), 3, &p, callbacks);
}

#define CHALLENGE_FIXTURE \
    "local t={after=0,hp=1,perfect=0,good=-1,bad=-1,miss=-1};" \
    "local d={id='gate',song=1,tiers={t}};"

static void testChallengeActions(void) {
    TestStore store = {0};
    store.entries[0] = (PMOSProgressChange){"door.A_1.x-y.fail", 4};
    store.entries[1] = (PMOSProgressChange){"door.replay.clear", 1};
    store.count = 2;
    PMOSSession *s = startProgress(CHALLENGE_FIXTURE
        "d.id='A_1.x-y'; d.song=3; d.difficulty='IN';"
        "d.tiers[2]={after=4,hp=10000,perfect=.25,good=-10000,bad=10000,miss=-.5};"
        "local state,n=challenge(d); card(1,state,n);"
        "d.id='locked'; d.unlocked=false; d.difficulty=nil;"
        "local locked,f=challenge(d); card(2,locked,f);"
        "progress.set('door.replay.fail',7); d.id='replay';"
        "local clear,retries=challenge(d); card(3,clear,retries);"
        "hotspot{onClick=function() return {challenge='A_1.x-y'} end};"
        "hotspot{onClick=function() return {challenge='locked'} end};"
        "hotspot{onClick=function() return {challenge='replay'} end};"
        "hotspot{onClick=function() return {challenge='missing'} end};"
        "hotspot{onClick=function() return {challenge='locked',open=2} end};"
        "hotspot{onClick=function() challenge(d) end}", &store);
    assert(s && p.challengeCount == 3 && p.count == 3 && store.reads == 5);
    assert(!strcmp(p.cards[0].title,"closed") && !strcmp(p.cards[0].caption,"4"));
    assert(!strcmp(p.cards[1].title,"locked") && !strcmp(p.cards[1].caption,"0"));
    assert(!strcmp(p.cards[2].title,"clear") && !strcmp(p.cards[2].caption,"7"));
    const PMOSChallenge *c = &p.challenges[0];
    assert(c->song == 3 && !strcmp(c->id,"A_1.x-y") && !strcmp(c->difficulty,"IN"));
    assert(c->state == PMOSChallengeClosed && c->failures == 4 && c->tierCount == 2);
    assert(c->tiers[0].after == 0 && c->tiers[0].hp == 1 && c->tiers[1].after == 4);
    assert(c->tiers[1].hp == 10000 && c->tiers[1].perfect == .25f && c->tiers[1].good == -10000);
    assert(c->tiers[1].bad == 10000 && c->tiers[1].miss == -.5f);
    assert(p.challenges[1].state == PMOSChallengeLocked && !p.challenges[1].difficulty[0]);
    assert(p.challenges[2].state == PMOSChallengeClear && p.challenges[2].failures == 7);
    memset(&p, 0, sizeof(p)); /* The caller may discard the page before clicking. */
    PMOSAction a;
    assert(PMOSClick(s, 0, &a) && a.challenge == 1 && !a.song && a.dest == -1);
    expectAction(s, 1, 0, -1);
    assert(PMOSClick(s, 2, &a) && a.challenge == 3);
    expectFailure(s, 3, "unknown challenge");
    expectFailure(s, 4, "exactly one field");
    expectFailure(s, 5, "declarations are closed");
    PMOSStop(s);
}

static void testChallengeBindings(void) {
    PMOSSession *s = start(CHALLENGE_FIXTURE
        "hotspot{challenge='locked'}; frame{challenge='gate'}; image{cover=2,challenge='gate'};"
        "card(3,'Locked','Preview',{challenge='locked'});"
        "card(1,nil,nil,{challenge='gate',heading='Intro',seconds=2.5});"
        "card(1,nil,nil,{challenge='gate',seconds=0}); card(1,nil,nil,{challenge='gate',heading=''});"
        "card(1,nil,nil,{}); card(1); card(1,nil,nil,{seconds=3,heading='Legacy'});"
        "challenge(d); d.id='locked'; d.unlocked=false; challenge(d)");
    assert(s && p.nodes == 3 && p.count == 7 && p.challengeCount == 2);
    assert(p.elements[0].challenge == 2 && !p.elements[0].handler);
    assert(p.cards[0].challenge == 2 && p.cards[0].song == 3 && !p.cards[0].speech);
    assert(p.challenges[p.cards[0].challenge - 1].state == PMOSChallengeLocked);
    assert(!strcmp(p.cards[0].title, "Locked") && !strcmp(p.cards[0].caption, "Preview"));
    for (int i = 1; i <= 2; ++i) assert(p.elements[i].challenge == 1 && p.elements[i].handler);
    for (int i = 1; i <= 3; ++i) assert(p.cards[i].challenge == 1 && p.cards[i].speech);
    assert(p.cards[1].seconds == 2.5 && !strcmp(p.cards[1].speechHeading, "Intro"));
    assert(p.cards[4].speech && !p.cards[4].seconds && !p.cards[4].speechHeading[0] && !p.cards[4].challenge);
    assert(!p.cards[5].speech && !p.cards[5].challenge);
    assert(p.cards[6].speech && !p.cards[6].challenge && p.cards[6].seconds == 3);
    assert(!strcmp(p.cards[6].speechHeading, "Legacy"));
    memset(&p, 0, sizeof(p));
    expectAction(s, 0, 0, -1);
    for (int i = 1; i <= 2; ++i) {
        PMOSAction action;
        assert(PMOSClick(s, i, &action) && action.challenge == 1 && !action.song && action.dest == -1);
    }
    PMOSStop(s);

    assert(!run("hotspot{challenge='missing'}") && strstr(p.error, "unknown challenge"));
    assert(!run("card(1,nil,nil,{challenge='missing'})") && strstr(p.error, "unknown challenge"));
    assert(!run(CHALLENGE_FIXTURE "challenge(d); frame{challenge='gate',open=1}"));
    assert(!run(CHALLENGE_FIXTURE "challenge(d); image{cover=1,challenge='gate',to='main'}"));
    assert(!run(CHALLENGE_FIXTURE "challenge(d); hotspot{challenge='gate',onClick=function() end}"));
    assert(!run(CHALLENGE_FIXTURE "challenge(d); card(1,nil,nil,{challenge='gate',seconds=-1})"));
    assert(!run(CHALLENGE_FIXTURE "challenge(d); card(1,nil,nil,{challenge='gate',heading=false})"));
    assert(!run(CHALLENGE_FIXTURE "challenge(d); card(1,nil,nil,{challenge='gate',open=1})"));
}

static void testCoverPreview(void) {
    TestStore store = {0};
    PMOSProgress cb = {&store, storeRead, storeCommit};
    const char *src = "progress.set('scratch',progress.get('scratch')+1);"
        "if progress.get('scratch')==1 then chapterCover('base.png') end;"
        "if progress.get('piece')==1 then chapterCover('piece.JPEG') end;"
        "if challengeProgress('gate').cleared then chapterCover('clear.webp') end";
    char cover[256];
    assert(PMOSPreviewCover(src,strlen(src),1,cb,cover) && !strcmp(cover,"base.png"));
    assert(store.commits==0 && !store.count);
    PMOSProgressChange flags[]={{"piece",1},{"door.gate.clear",1}};
    assert(storeCommit(&store,flags,1));
    assert(PMOSPreviewCover(src,strlen(src),1,cb,cover) && !strcmp(cover,"piece.JPEG"));
    assert(storeCommit(&store,flags+1,1));
    assert(PMOSPreviewCover(src,strlen(src),1,cb,cover) && !strcmp(cover,"clear.webp"));
    assert(store.commits==2 && store.count==2);
    const char *bad[]={"chapterCover('../x.png')","chapterCover('x.mp4')","chapterCover('x.gif')",
        "chapterCover('x.png','y.png')","chapterCover('a\\0.jpg')","chapterCover('x.png');oops()"};
    for(size_t i=0;i<sizeof(bad)/sizeof(*bad);++i)
        assert(!PMOSPreviewCover(bad[i],strlen(bad[i]),1,cb,cover) && !cover[0]);
    assert(PMOSPreviewCover("return",6,1,cb,cover) && !cover[0]);
    store.failRead=1;
    assert(!PMOSPreviewCover(src,strlen(src),1,cb,cover) && !cover[0] && store.commits==2);
    store.failRead=0; PMOSSession *live=startProgress(src,&store);
    assert(live && store.commits==3 && !strcmp(p.chapterCover,"clear.webp")); PMOSStop(live);
}

static void testChallengeProgress(void) {
    TestStore store = {0};
    store.entries[0] = (PMOSProgressChange){"door.gate.clear", 1};
    store.entries[1] = (PMOSProgressChange){"door.gate.fail", 4};
    store.count = 2;
    PMOSSession *s = startProgress(CHALLENGE_FIXTURE
        "local before=challengeProgress('gate'); local fresh=challengeProgress('fresh');"
        "if before.cleared==true and before.failures==4 and fresh.cleared==false and fresh.failures==0 "
        "then card(1,'history') end;"
        "d.unlocked=false; local state,n,info=challenge(d);"
        "if state=='clear' and n==4 and info.available==true and info.cleared==true and info.failures==4 "
        "then card(2,'replay') end;"
        "d.id='fresh'; local _,_,locked=challenge(d);"
        "if locked.available==false and locked.cleared==false and locked.failures==0 then card(3,'locked') end;"
        "hotspot{challenge='gate'}; hotspot{onClick=function() progress.set('door.gate.fail',-2);"
        "local now=challengeProgress('gate'); if now.cleared and now.failures==0 then return {open=3} end end}",
        &store);
    assert(s && p.count == 3 && !strcmp(p.cards[0].title, "history"));
    assert(!strcmp(p.cards[1].title, "replay") && !strcmp(p.cards[2].title, "locked"));
    PMOSAction action;
    assert(p.elements[0].handler && PMOSClick(s, 0, &action) && action.challenge == 1);
    expectAction(s, 1, 3, -1);
    assert(store.commits == 1 && store.entries[1].value == -2);
    PMOSStop(s);
    assert(!run("challengeProgress()"));
    assert(!run("challengeProgress('a','b')"));
    assert(!run("challengeProgress('bad/id')"));
    assert(!run("challengeProgress(7)"));
    store.failRead = 1;
    assert(!startProgress("progress.set('pending',1); challengeProgress('gate')", &store));
    assert(strstr(p.error, "progress read failed") && store.commits == 1);
}

/* A single loaded chapter must keep puzzle callbacks, sequence metadata and
   page-owned cue slices alive together, including across a VM restart. */
static void testPuzzleChallengeSequence(void) {
    const char *script = CHALLENGE_FIXTURE
        "puzzle.define{id='key',mode='ordered',pieces={'A'}};"
        "local _,_,solved=puzzle.status('key'); d.unlocked=solved;"
        "d.showDetail=false; d.intro={'entry.gif'}; d.nextSongs={{song=2,difficulty='IN'}};"
        "d.cues={{at=0,duration=1,text='go'}}; challenge(d);"
        "hotspot{onClick=function() puzzle.submit('key','A') end}; hotspot{challenge='gate'}";
    TestStore store = {0};
    PMOSSession *vm = startProgress(script, &store);
    assert(vm && p.challenges[0].state == PMOSChallengeLocked);
    expectAction(vm, 0, 0, -1);
    PMOSStop(vm);
    vm = startProgress(script, &store);
    assert(vm && store.commits == 1 && p.challengeCount == 1);
    const PMOSChallenge *gate = &p.challenges[0];
    assert(gate->state == PMOSChallengeClosed && !gate->showDetail);
    assert(gate->introCount == 1 && !strcmp(gate->intro[0], "entry.gif"));
    assert(gate->nextSongCount == 1 && gate->nextSongs[0].song == 2 && !strcmp(gate->nextSongs[0].difficulty, "IN"));
    assert(p.cueCount == 1 && gate->cueStart == 0 && gate->cueCount == 1 && !strcmp(p.cues[0].text, "go"));
    PMOSAction action;
    assert(PMOSClick(vm, 1, &action) && action.challenge == 1);
    PMOSStop(vm);
}

static void testChallengeCues(void) {
    assert(run(CHALLENGE_FIXTURE
        "challenge(d); d.id='empty'; d.cues={}; challenge(d); d.id='first';"
        "d.cues[2]={at=0,duration=.5,blockPause=true};"
        "d.cues[1]={at=8.25,duration=1.5,text='hello',src='card.JpEg',blockPause=false};"
        "challenge(d); d.id='next'; d.cues={{at=0,duration=2,src='art.WeBp'}}; challenge(d)"));
    assert(p.challengeCount == 4 && p.cueCount == 3);
    assert(!p.challenges[0].cueCount && !p.challenges[1].cueCount);
    assert(p.challenges[2].cueStart == 0 && p.challenges[2].cueCount == 2);
    assert(p.challenges[3].cueStart == 2 && p.challenges[3].cueCount == 1);
    assert(p.cues[0].at == 8.25 && p.cues[0].duration == 1.5 && !p.cues[0].blockPause);
    assert(!strcmp(p.cues[0].text,"hello") && !strcmp(p.cues[0].src,"card.JpEg"));
    assert(!p.cues[1].text[0] && !p.cues[1].src[0] && p.cues[1].blockPause);
    assert(!strcmp(p.cues[2].src,"art.WeBp") && !p.cues[2].blockPause);

    char source[768];
    const char *bad[] = {
        "d.cues=false", "d.cues.extra=c", "d.cues[3]=c", "d.cues[0]=c", "d.cues[1]=1",
        "c.at=nil", "c.at=-1", "c.at='0'", "c.at=0/0", "c.duration=nil", "c.duration=0",
        "c.duration=-1", "c.duration=1/0", "c.at=1e308; c.duration=1e308", "c.blockPause=1",
        "c.text=nil; c.blockPause=false", "c.text=''", "c.text=2", "c.text='a\\0b'",
        "for i=1,8 do c.text=c.text..c.text end", "c.src='.a.png'", "c.src='../a.png'",
        "c.src='dir\\\\a.jpg'", "c.src='C:a.png'", "c.src='a\\nb.png'", "c.src='a.gif'"
    };
    for (size_t i = 0; i < sizeof(bad)/sizeof(bad[0]); ++i) {
        snprintf(source, sizeof(source), CHALLENGE_FIXTURE
            "local c={at=0,duration=1,text='x'}; d.cues={c}; %s; challenge(d)", bad[i]);
        assert(!run(source) && p.error[0] && !p.challengeCount && !p.cueCount);
    }
    snprintf(source, sizeof(source), CHALLENGE_FIXTURE
        "d.cues={{at=0,duration=1,text='first'}}; challenge(d); d.id='second';"
        "for i=%d,1,-1 do d.cues[i]={at=i,duration=1,blockPause=true} end; challenge(d);"
        "d.id='full'; d.cues={}; challenge(d)", PMOSMaxChallengeCues - 1);
    assert(run(source) && p.cueCount == PMOSMaxChallengeCues);
    assert(!strcmp(p.cues[0].text, "first"));
    assert(p.challenges[1].cueStart == 1 && p.challenges[1].cueCount == PMOSMaxChallengeCues - 1);
    assert(p.challenges[2].cueStart == PMOSMaxChallengeCues && !p.challenges[2].cueCount);
    for (int i = 1; i < p.cueCount; ++i) assert(p.cues[i].at == i);
    strcat(source, "; d.id='overflow'; d.cues={{at=0,duration=1,text='extra'}}; challenge(d)");
    assert(!run(source) && strstr(p.error, "too many challenge cues"));
    snprintf(source, sizeof(source), CHALLENGE_FIXTURE
        "d.cues={}; for i=1,%d do d.cues[i]={at=i,duration=1,text='x'} end; challenge(d)",
        PMOSMaxChallengeCues + 1);
    assert(!run(source) && strstr(p.error, "too many challenge cues"));
}

static void testChallengeValidation(void) {
    assert(run(CHALLENGE_FIXTURE "challenge(d); d.id='full'; d.showDetail=false;"
        "d.intro={'first.GiF','clip 2.MP4','third.gif','last.mp4'};"
        "d.nextSongs={{song=3,difficulty='IN'},{song=2}}; challenge(d);"
        "d.id='empty'; d.intro={}; d.nextSongs={}; d.showDetail=true; challenge(d)"));
    const PMOSChallenge *c = &p.challenges[1];
    assert(p.challengeCount == 3 && c->song == 1 && !c->showDetail && c->introCount == 4);
    assert(!strcmp(c->intro[0], "first.GiF") && !strcmp(c->intro[1], "clip 2.MP4") &&
           !strcmp(c->intro[2], "third.gif") && !strcmp(c->intro[3], "last.mp4"));
    assert(c->nextSongCount == 2 && c->nextSongs[0].song == 3 && !strcmp(c->nextSongs[0].difficulty, "IN"));
    assert(c->nextSongs[1].song == 2 && !c->nextSongs[1].difficulty[0]);
    assert(p.challenges[0].showDetail && !p.challenges[0].introCount && !p.challenges[0].nextSongCount);
    assert(p.challenges[2].showDetail && !p.challenges[2].introCount && !p.challenges[2].nextSongCount);
    assert(run(CHALLENGE_FIXTURE "d.intro={'@stock/c8/321-unlock','local.mp4','@stock/c9/to-phase-2',"
        "'@stock/c9/after-deduction'}; challenge(d)"));
    assert(p.challenges[0].introCount == 4 && !strcmp(p.challenges[0].intro[2], "@stock/c9/to-phase-2"));
    assert(!run("image{src='@stock/c9/to-phase-2'}"));
    const char *bad[] = {
        "d.intro={'@stock/c9/to-phase-2.mp4'}", "d.intro={'@stock/c9/../to-phase-2'}",
        "d.intro={'@stock/c9/after-deduction\\0.mp4'}", "d.intro={'@stock/C8/321-unlock'}",
        "d.showDetail=0", "d.showDetail='false'", "d.intro='a.gif'", "d.intro={false}",
        "d.intro={'a.gif','a.gif','a.gif','a.gif','a.gif'}", "d.intro={[2]='a.gif'}", "d.intro={x='a.gif'}",
        "d.intro={'../a.gif'}", "d.intro={'.a.gif'}", "d.intro={'a/b.gif'}", "d.intro={'a\\\\b.mp4'}",
        "d.intro={'C:a.gif'}", "d.intro={'a.png'}", "d.intro={'a.gif.tmp'}", "d.intro={'a\\0.gif'}",
        "d.intro={'a\\n.gif'}", "d.intro={'\\255.gif'}", "local a=''; for i=1,252 do a=a..'a' end; d.intro={a..'.gif'}",
        "d.nextSongs=false", "d.nextSongs={{song=1},{song=2},{song=3}}", "d.nextSongs={[2]={song=1}}",
        "d.nextSongs={x={song=1}}", "d.nextSongs={2}", "d.nextSongs={{}}", "d.nextSongs={{song='2'}}",
        "d.nextSongs={{song=0}}", "d.nextSongs={{song=4}}", "d.nextSongs={{song=1.5}}",
        "d.nextSongs={{song=2,diff='IN'}}", "d.nextSongs={{song=2,difficulty=false}}", "d.nextSongs={{song=2,difficulty=''}}",
        "d.nextSongs={{song=2,difficulty='I\\0N'}}", "local a=''; for i=1,96 do a=a..'a' end; d.nextSongs={{song=2,difficulty=a}}",
        "d.id=nil", "d.id=''", "d.id='a/b'", "d.id='a\\0b'", "challenge(d)",
        "d.song=nil", "d.song=4", "d.song=1.5", "d.song='1'", "d.unlocked=0",
        "d.difficulty=''", "d.difficulty=false", "d.tiers=nil", "d.tiers={}",
        "d.tiers[3]=t", "d.tiers.extra=t", "d.tiers[1]=false", "d.tiers[2]=t",
        "d.tiers[2]={after=3,hp=1,perfect=0,good=0,bad=0,miss=0}; d.tiers[3]=t",
        "t.after=1", "t.after=-1", "t.after=.5", "t.after=2147483648", "t.after=1/0",
        "t.hp=nil", "t.hp=.999", "t.hp=10000.001", "t.hp=0/0", "t.perfect=1/0",
        "t.good=-1/0", "t.bad=-10000.001", "t.miss=10000.001", "t.miss='0'"
    };
    char source[640];
    for (size_t i = 0; i < sizeof(bad)/sizeof(bad[0]); ++i) {
        snprintf(source, sizeof(source), CHALLENGE_FIXTURE "%s; challenge(d)", bad[i]);
        assert(!run(source) && p.error[0] && !p.challengeCount);
    }
    for (int extra = 0; extra <= 1; ++extra) {
        snprintf(source, sizeof(source), CHALLENGE_FIXTURE
            "d.id=''; for i=1,%d do d.id=d.id..'a' end; challenge(d)", PMOSChallengeIdMax + extra);
        assert(run(source) == !extra);
        snprintf(source, sizeof(source), CHALLENGE_FIXTURE
            "for i=1,%d do d.tiers[i]={after=i-1,hp=1,perfect=0,good=0,bad=0,miss=0} end; challenge(d)",
            PMOSMaxChallengeTiers + extra);
        assert(run(source) == !extra);
        snprintf(source, sizeof(source), CHALLENGE_FIXTURE
            "for i=1,%d do d.id='g'..i; challenge(d) end", PMOSMaxChallenges + extra);
        assert(run(source) == !extra);
    }
    TestStore store = {0};
    store.failRead = 1;
    assert(!startProgress(CHALLENGE_FIXTURE "progress.set('staged',1); challenge(d)", &store));
    assert(strstr(p.error,"progress read failed") && !p.challengeCount && !store.commits);
    store.failRead = 0;
    snprintf(source, sizeof(source), CHALLENGE_FIXTURE
        "for i=1,%d do progress.get('x') end; challenge(d)", PMOSProgressAccessLimit - 1);
    assert(!startProgress(source, &store) && strstr(p.error,"progress access limit"));
}

static void testSwitchAndCourse(void) {
    TestStore store={0}; PMOSAction a;
    const char *script="home('list'); listSwitchAfter('story.done');"
        "hotspot{onClick=function() progress.set('story.done',1) end};"
        "hotspot{onClick=function() progress.set('story.done',0); return {open=99} end}";
    PMOSSession *s=startProgress(script,&store);
    assert(s && p.listFirst && p.listSwitchHidden);
    store.failCommit=1; assert(!PMOSClick(s,0,&a) && a.listSwitchHidden);
    store.failCommit=0; assert(PMOSClick(s,0,&a) && !a.listSwitchHidden);
    assert(!PMOSClick(s,1,&a) && !a.listSwitchHidden);
    PMOSStop(s); s=startProgress(script,&store); assert(s && !p.listSwitchHidden); PMOSStop(s);
    assert(run("home('list')") && p.listFirst && !p.listSwitchHidden);
    assert(!run("listSwitchAfter('')"));
    s=startProgress("challenge{id='c',secretCourse={{song=1},{song=2},{song=3}}};hotspot{onClick=function() chapterLife(0);return {challenge='c'} end}",&store);
    assert(s && p.selectedLifeTier==1 && PMOSClick(s,0,&a) && a.selectedLifeTier==0 && a.challenge==1); PMOSStop(s);
    assert(run("challenge{id='course',secretCourse={{song=2,difficulty='SP'},{song=1},{song=3}}}"));
    PMOSChallenge *c=&p.challenges[0]; assert(c->courseCount==3 && c->lifeTier==-1 && c->song==2 && !strcmp(c->difficulty,"SP"));
    assert(run("challenge{id='course',lifeTier=0,showDetail=false,secretCourse={{song=1},{song=2},{song=3},{song=1,difficulty='HD'}}}"));
    assert(c->courseCount==4 && c->lifeTier==0 && !c->showDetail && !strcmp(c->course[3].difficulty,"HD"));
    const char *bad[]={"secretCourse={}","secretCourse={{song=1},{song=1}}", "secretCourse={{song=1},{song=4},{song=2}}", "secretCourse={{song=1},{song=2},{song=1}},tiers={}","secretCourse={{song=1},{song=2},{song=1}},nextSongs={}", "secretCourse={{song=1},{song=2},{song=1}},lifeTier=-2", "song=1,lifeTier=1"};
    for(size_t i=0;i<sizeof(bad)/sizeof(*bad);++i){char src[256];snprintf(src,sizeof(src),"challenge{id='bad',%s}",bad[i]);assert(!run(src));}
}

static void testProgressTransactions(void) {
    TestStore store = {0};
    PMOSSession *s = startProgress("card(progress.get('missing')+1);"
        "progress.set('Act_1.key-A',-1); progress.set('second',progress.get('Act_1.key-A'));"
        "progress.set('Act_1.key-A',2); card(progress.get('Act_1.key-A'));"
        "hotspot{onClick=function() progress.set('second',3); progress.set('Act_1.key-A',1);"
        "return {checkpoint={mode='session',song=progress.get('second')}} end};"
        "hotspot{onClick=function() progress.set('second',99); return {open=9} end};"
        "hotspot{onClick=function() progress.set('second',42); progress.get('missing') end};"
        "hotspot{onClick=function() return {open=progress.get('Act_1.key-A')} end}", &store);
    assert(s && p.count == 2 && p.cards[0].song == 1 && p.cards[1].song == 2);
    assert(store.reads == 1 && store.commits == 1 && store.lastBatch == 2 && store.count == 2);
    assert(store.entries[storeIndex(&store, "second")].value == -1);
    expectFailure(s, 1, "song");
    store.failRead = 1;
    expectFailure(s, 2, "progress read");
    store.failRead = 0;
    assert(store.commits == 1);
    store.failCommit = 1;
    expectFailure(s, 0, "progress commit");
    store.failCommit = 0;
    assert(store.commits == 2 && store.entries[storeIndex(&store, "second")].value == -1);
    expectAction(s, 3, 2, -1);
    assert(store.commits == 2);
    PMOSAction a;
    assert(PMOSClick(s, 0, &a) && a.checkpoint == 1 && a.song == 3);
    assert(store.commits == 3 && store.lastBatch == 2);
    PMOSStop(s);
    assert(!startProgress("progress.set('second',77); hotspot{to='missing'}", &store));
    assert(strstr(p.error, "unknown target") && store.commits == 3);
    store.failCommit = 1;
    assert(!startProgress("progress.set('second',77); card(1)", &store));
    assert(strstr(p.error, "progress commit") && p.count == 0);
    s = startProgress("card(progress.get('Act_1.key-A')); card(progress.get('second'))", &store);
    assert(s && p.cards[0].song == 1 && p.cards[1].song == 3 && store.commits == 4);
    PMOSStop(s);
}

static void testProgressValidation(void) {
    TestStore store = {0};
    const char *bad[] = {
        "get('')", "get(1)", "get('a/b')", "set('a b',1)", "set('a\\0b',1)",
        "get('\\195\\169')", "set('a', 1.5)", "set('a', '1')", "set('a', false)",
        "set('a',2147483648)", "set('a',-2147483649)", "get()", "set('a')", "get('a',1)"
    };
    char src[512];
    for (size_t i = 0; i < sizeof(bad)/sizeof(bad[0]); ++i) {
        snprintf(src, sizeof(src), "progress.set('first',1); progress.%s", bad[i]);
        assert(!startProgress(src, &store) && p.error[0]);
    }
    assert(store.reads == 0 && store.commits == 0);
    assert(!startProgress("local k=''; for i=1,65 do k=k..'x' end; progress.get(k)", &store));
    PMOSSession *s = startProgress("local k=''; for i=1,64 do k=k..'x' end;"
        "progress.set(k,-2147483648); progress.set('max',2147483647)", &store);
    assert(s && store.count == 2 && strlen(store.entries[0].key) == 64);
    assert(store.entries[0].value == (-2147483647-1) && store.entries[1].value == 2147483647);
    PMOSStop(s);
    assert(run("card(1+progress.get('missing'))") && p.cards[0].song == 1);
    assert(!run("progress.set('a',0)") && strstr(p.error, "commit unavailable"));
}

static void testProgressBudget(void) {
    TestStore store = {0};
    char src[512];
    snprintf(src, sizeof(src), "for i=1,%d do progress.set('k'..i,i) end;"
        "hotspot{onClick=function() progress.set('k1',2); for i=1,%d do progress.get('k2') end end};"
        "hotspot{onClick=function() return {open=progress.get('k1')} end}",
        PMOSProgressAccessLimit, PMOSProgressAccessLimit);
    PMOSSession *s = startProgress(src, &store);
    assert(s && store.lastBatch == PMOSProgressAccessLimit);
    expectFailure(s, 0, "progress access limit");
    assert(store.reads == PMOSProgressAccessLimit - 1 && store.commits == 1);
    expectAction(s, 1, 1, -1);
    PMOSStop(s);
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

static void testReveal(void) {
    PMOSAction a;
    PMOSSession *s = start("screen('first'); frame{id='node'}; screen('second');"
        "hotspot{onClick=function() return {reveal={target='node',title='Focus',text='Read',song=3}} end};"
        "frame{id='box'}; frame{id='node',parent='box',onClick=function() "
        "return {reveal={target='node',title='Again',text='Resume'}} end}");
    assert(s && PMOSClick(s, 1, &a));
    assert(a.element == 3 && a.song == 3 && !strcmp(a.revealTitle,"Focus") && !strcmp(a.revealText,"Read"));
    assert(PMOSClick(s, 3, &a) && a.element == 3 && !a.song && !strcmp(a.revealText,"Resume"));
    PMOSStop(s);

    const char *bad[] = {
        "false", "{}", "{title='t',text='x'}", "{target='node',title='',text='x'}",
        "{target='node',title=7,text='x'}", "{target='node',title='t'}",
        "{target='other',title='t',text='x'}", "{target='node',title='t',text='x',more=true}",
        "{target='node',title='t',text='x',song=0}", "{target='node',title='t',text='x',song=4}",
        "{target='node',title='t',text='x',song='1'}", "{target='node',title='t',text='x',song=1.5}",
        "{target='node',title='t',text='\\0'}", "{target='node',title='t',text='\\255'}",
        "{target='node',title='t',text='x'},open=1"
    };
    for (size_t i=0; i<sizeof(bad)/sizeof(*bad); ++i) {
        char source[512];
        snprintf(source,sizeof(source),"screen('a');frame{id='other'};screen('b');frame{id='node',"
                 "onClick=function() progress.set('seen',1);return {reveal=%s} end}",bad[i]);
        TestStore store = {0};
        s = startProgress(source, &store);
        assert(s && !PMOSClick(s, 1, &a) && a.error[0]);
        assert(!store.commits && a.element == -1 && !a.song && !a.revealTitle[0] && !a.revealText[0]);
        PMOSStop(s);
    }
}

static void testPauseAndReplay(void){
 const char *base="challenge{id='x',secretCourse={{song=1},{song=2},{song=3}},";
 const char *cases[]={"noPause=true,replaySongs={{song=2,difficulty='IN'},{song=2,difficulty='AT'}}", "noPause=false", "", "noPause=1", "replaySongs={[2]={song=1}}", "replaySongs={{song=4}}", "replaySongs={{song=1,bogus=true}}", "replaySongs={{song=1},{song=1},{song=1},{song=1},{song=1},{song=1},{song=1},{song=1},{song=1}}"};
 for(size_t i=0;i<sizeof(cases)/sizeof(*cases);++i){char code[512];snprintf(code,sizeof code,"%s%s}",base,cases[i]);assert(!!run(code)==(i<3));if(i<3){assert(p.challenges[0].noPause==(i==0));assert(p.challenges[0].replayCount==(i==0?2:0));if(i==0){assert(p.challenges[0].replaySongs[0].song==2&&!strcmp(p.challenges[0].replaySongs[0].difficulty,"IN"));assert(p.challenges[0].replaySongs[1].song==2&&!strcmp(p.challenges[0].replaySongs[1].difficulty,"AT"));}}}
}
static void testEntryMovie(void){
 assert(run("onEnterMovie{key='center',src='center.mp4'}"));
 assert(!strcmp(p.entryMovieKey,"movie.center") && !strcmp(p.entryMovieName,"center.mp4") && !p.entryMovieSeen);
 assert(!run("onEnterMovie{key='a/b',src='center.mp4'}"));
 assert(!run("onEnterMovie{key='center',src='../other.mp4'}"));
 assert(!run("onEnterMovie{key='a',src='a.mp4'};onEnterMovie{key='b',src='b.mp4'}"));
}
int main(void){testEntryMovie();assert(run("home('os')") && p.nativeChapter==9);assert(run("nativeChapter(8)") && p.nativeChapter==8);assert(run("nativeChapter(9)") && p.nativeChapter==9);assert(!run("nativeChapter(7)"));assert(!run("nativeChapter('8')"));testPauseAndReplay();testSwitchAndCourse();testCoverPreview();testReveal();testPuzzleChallengeSequence();testChallengeCues();testChallengeBindings();testChallengeProgress();testChallengeActions();testChallengeValidation();testLayout();testPersistentClicks();testHandlerFailures();testCheckpoints();testProgressTransactions();testProgressValidation();testProgressBudget();testNodeTiming();testVisibility();testClickBudgets();assert(run("return {}")&&!p.listFirst&&!p.count);assert(run("home('list'); for i=1,song_count do card(i,'Title','Body') end"));assert(p.listFirst&&p.count==3&&p.cards[2].song==3&&!strcmp(p.cards[1].caption,"Body"));
 assert(!run("card(4)")&&strstr(p.error,"os.lua:1:"));assert(!run("home('bad')"));assert(!run("while true do end")&&strstr(p.error,"limit"));assert(!run("local t='a';for i=1,30 do t=t..t end"));assert(!run("require('os')"));assert(!run("for i=1,129 do card(1) end"));assert(!run("card("));assert(!run("\033Lua"));assert(run("card(2)")&&p.count==1);puts("chapter OS Lua tests passed");return 0;}
