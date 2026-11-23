#include "../PhiMod/Core/PMChapterVM.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static PMOSPage page;
static int readFlag(void *ctx, const char *key, int *value) {
    *value = !strcmp(key, "visible") ? *(int *)ctx :
             !strcmp(key, "door.replay.clear") || !strcmp(key, "door.empty.clear");
    return 1;
}
static int commitFlags(void *ctx, const PMOSProgressChange *changes, size_t count) {
    (void)changes;
    *(int *)ctx += (int)count;
    return 1;
}
static PMOSSession *load(const char *src, int *writes) {
    PMOSProgress progress = { writes, readFlag, commitFlags };
    return PMOSStartWithProgress(src, strlen(src), 130, &page, progress);
}

int main(void) {
    int writes = 0;
    const char *invalid[] = {"songVisible(0,false)", "songVisible(131,true)", "songVisible(1.5,true)",
        "songVisible('2',false)", "songVisible(2,1)", "songVisible(2,nil)", "songVisible(2)", "songVisible(2,true,1)"};
    for (size_t i = 0; i < sizeof(invalid)/sizeof(*invalid); ++i) assert(!load(invalid[i], &writes));

    const char *script =
        "card(2); card(3,nil,nil,{challenge='bad'}); card(1,nil,nil,{challenge='good'}); card(1);"
        "frame{id='parent',open=2}; frame{id='nested',parent='parent'};"
        "hotspot{parent='nested',onClick=function() progress.set('clicked',1) end};"
        "image{id='cover',cover=2}; hotspot{open=2}; hotspot{open=130};"
        "hotspot{challenge='bad'}; hotspot{challenge='good'};"
        "hotspot{onClick=function() progress.set('clicked',1); return {open=2} end};"
        "hotspot{onClick=function() return {checkpoint={mode='session',song=2}} end};"
        "hotspot{onClick=function() return {checkpoint={mode='relaunch',song=2}} end};"
        "hotspot{onClick=function() return {reveal={target='ok',title='x',text='y',song=2}} end};"
        "hotspot{onClick=function() return {show='nested'} end};"
        "hotspot{onClick=function() return {reveal={target='cover',title='x',text='y'}} end};"
        "hotspot{onClick=function() songVisible(2,true) end};"
        "frame{id='ok',hidden=true}; hotspot{onClick=function() return {show='ok'} end};"
        "hotspot{onClick=function() return {challenge='bad'} end};"
        "local d={id='bad',song=2,tiers={{after=0,hp=1,perfect=0,good=0,bad=0,miss=0}}}; challenge(d);"
        "d.id='good'; d.song=1; challenge(d); d.id='sequence'; d.nextSongs={{song=2}}; challenge(d);"
        "challenge{id='course',secretCourse={{song=1},{song=3},{song=2}}};"
        "d.id='replay'; d.replaySongs={{song=2},{song=3}}; challenge(d);"
        "d.id='empty'; d.replaySongs={{song=2}}; challenge(d);"
        "songVisible(130,false); songVisible(2,progress.get('missing')~=0); songVisible(130,true);"
        "unlockAnimation{id='teaser',song=2,style='c8',when='event'};"
        "hotspot{onClick=function() return {unlockAnimation='teaser'} end}";
    PMOSSession *s = load(script, &writes);
    if (!s) fprintf(stderr, "%s\n", page.error);
    assert(s && writes == 0);
    for (int i = 0; i <= 131; ++i) assert(PMOSSongVisible(s,i) == (i >= 1 && i <= 130 && i != 2));
    assert(page.count == 4 && page.cards[0].songSuppressed && page.cards[1].songSuppressed);
    assert(!page.cards[2].songSuppressed && page.cards[2].challenge == 2 && !page.cards[3].songSuppressed);
    assert(page.nodes == 19 && page.elements[2].parent == 1);
    for (int i = 0; i <= 4; ++i) assert(page.elements[i].songSuppressed);
    assert(!page.elements[5].songSuppressed && page.elements[6].songSuppressed && !page.elements[7].songSuppressed);
    assert(page.challenges[2].songSuppressed && page.challenges[3].songSuppressed);
    assert(!page.challenges[4].songSuppressed && page.challenges[4].replayCount == 1 && page.challenges[4].replaySongs[0].song == 3);
    assert(page.challenges[5].songSuppressed && page.unlockAnimations[0].song == 2);
    memset(&page, 0, sizeof(page)); // Clicks use the session snapshot.
    PMOSAction a;
    for (int i = 0; i <= 4; ++i) assert(PMOSClick(s,i,&a) && !a.song && !a.challenge && a.dest == -1);
    assert(PMOSClick(s,5,&a) && a.song == 130);
    assert(PMOSClick(s,6,&a) && !a.challenge);
    assert(PMOSClick(s,7,&a) && a.challenge == 2);
    for (int i = 8; i <= 14; ++i) assert(!PMOSClick(s,i,&a) && a.error[0] && !a.song && !a.checkpoint && a.element == -1);
    assert(PMOSClick(s,16,&a) && a.element == 15 && a.visible);
    assert(PMOSClick(s,17,&a) && !a.challenge);
    assert(PMOSClick(s,18,&a) && a.unlockAnimation == 1 && !a.song);
    assert(writes == 0);
    // A progress write during a visit takes effect on the next declaration load.
    const char *conditional = "songVisible(2,progress.get('visible')~=0);"
                              "hotspot{onClick=function() progress.set('visible',1) end}";
    PMOSSession *before = load(conditional, &writes);
    assert(before && !PMOSSongVisible(before,2) && !page.count);
    assert(PMOSClick(before,0,&a) && writes == 1 && !PMOSSongVisible(before,2));
    PMOSSession *after = load(conditional, &writes);
    assert(after && PMOSSongVisible(after,2));
    PMOSStop(before);
    PMOSStop(after);
    PMOSSession *fresh = load("songVisible(1,false)", &writes);
    assert(fresh && !page.count && PMOSSongVisible(fresh,2) && !PMOSSongVisible(s,2));
    PMOSStop(fresh);
    PMOSStop(s);
    puts("Chapter song visibility passed");
}
