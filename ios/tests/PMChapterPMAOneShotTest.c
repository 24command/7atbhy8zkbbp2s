#include "../PhiMod/Core/PMChapterVM.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static PMOSPage page;
static void accepts(const char *source) {
    int ok = PMBuildOSPage(source, strlen(source), 3, &page);
    if (!ok) fprintf(stderr, "Unexpected rejection: %s\n%s\n", page.error, source);
    assert(ok && !page.error[0]);
}
static void rejects(const char *source) {
    int ok = PMBuildOSPage(source, strlen(source), 3, &page);
    if (ok) fprintf(stderr, "Unexpected acceptance: %s\n", source);
    assert(!ok && page.error[0] && !page.nodes && !page.unlockAnimationCount);
}
static void srcForBoth(const char *expression, int valid) {
    char source[1200];
    snprintf(source, sizeof(source), "onEnterMovie{key='intro',src=%s}", expression);
    if (valid) accepts(source); else rejects(source);
    snprintf(source, sizeof(source), "unlockAnimation{id='clip',song=1,style='mod',src=%s}", expression);
    if (valid) accepts(source); else rejects(source);
}
static void namesAndLegacy(void) {
    srcForBoth("'clip.pma'", 1);
    srcForBoth("'clip.PmA'", 1);
    srcForBoth("'clip.mp4'", 1);
    srcForBoth("'\\233\\151\\168.pma'", 1); /* Valid UTF-8 local basename. */
    assert(!strcmp(page.unlockAnimations[0].src, "\xe9\x97\xa8.pma"));
    accepts("onEnterMovie{key='intro',src='clip.pma'};"
            "unlockAnimation{id='clip',song=2,style='mod',src='clip.pma',after=.5,"
            "duration=3,infoAt=0,infoUntil=2};"
            "unlockAnimation{id='stock',song=1,style='c8',src='@stock/c8/321-unlock'}");
    assert(!strcmp(page.entryMovieKey, "movie.intro") && !strcmp(page.entryMovieName, "clip.pma"));
    const PMOSUnlockAnimation *n = &page.unlockAnimations[0];
    assert(n->song == 2 && n->style == PMOSUnlockMod && n->once && !n->seen);
    assert(n->when == PMOSUnlockEnter && n->after == .5 && n->duration == 3);
    assert(n->hasInfoAt && n->infoAt == 0 && n->hasInfoUntil && n->infoUntil == 2);
    assert(!strcmp(page.unlockAnimations[1].src, "@stock/c8/321-unlock"));
    /* Existing MP4 case rules are intentionally unchanged for each API. */
    rejects("onEnterMovie{key='intro',src='clip.MP4'}");
    accepts("unlockAnimation{id='clip',song=1,style='mod',src='clip.Mp4'}");
    srcForBoth("'clip.gif'", 0);
    srcForBoth("'clip.mov'", 0);
    srcForBoth("'clip.png'", 0);
    rejects("onEnterMovie{key='intro',src='@stock/c8/321-unlock'}");
    rejects("unlockAnimation{id='clip',song=1,style='mod',src='@stock/unknown'}");
}
static void invalidNames(void) {
    const char *bad[] = {
        "nil", "false", "1", "{}", "''", "'.pma'", "'.hidden.pma'", "'../clip.pma'",
        "'sub/clip.pma'", "'sub\\\\clip.pma'", "'C:clip.pma'", "'/clip.pma'",
        "'https://host/clip.pma'", "'clip.pma/child.pma'", "'clip.pma.extra'", "'clip.pma '",
        "'clip\\0.pma'", "'clip.pma\\0suffix'", "'clip\\10.pma'", "'clip\\127.pma'",
        "'clip\\194\\128.pma'", "'clip\\255.pma'", "'clip\\192\\128.pma'",
        "'clip\\226.pma'", "'clip\\237\\160\\128.pma'", "'clip\\244\\144\\128\\128.pma'"
    };
    for (size_t i = 0; i < sizeof(bad)/sizeof(*bad); ++i) srcForBoth(bad[i], 0);
    char expression[265];
    expression[0] = '\'';
    memset(expression + 1, 'a', 251);
    memcpy(expression + 252, ".pma'", 6); /* Filename is exactly 255 bytes. */
    srcForBoth(expression, 1);
    memset(expression + 1, 'a', 252);
    memcpy(expression + 253, ".pma'", 6);
    srcForBoth(expression, 0);
    rejects("onEnterMovie{key='a',src='clip.pma'};onEnterMovie{key='b',src='clip.pma'}");
    rejects("unlockAnimation{id='clip',song=1,style='mod',src='clip.pma',duration=0}");
    rejects("unlockAnimation{id='clip',song=1,style='mod',src='clip.pma',duration=2,infoAt=2}");
}
typedef struct { int movie, unlock; } Store;
static int readProgress(void *ctx, const char *key, int *value) {
    Store *s = ctx;
    *value = !strcmp(key, "movie.intro") ? s->movie : !strcmp(key, "unlock.clip") ? s->unlock : 0;
    return 1;
}
static void onceAndCallbacks(void) {
    const char *source = "onEnterMovie{key='intro',src='clip.pma'};"
        "unlockAnimation{id='clip',song=1,style='mod',src='clip.pma',when='event'};"
        "hotspot{onClick=function() return {unlockAnimation='clip'} end}";
    Store store = {0};
    PMOSProgress callbacks = {&store, readProgress, NULL};
    PMOSSession *session = PMOSStartWithProgress(source, strlen(source), 1, &page, callbacks);
    assert(session && !page.entryMovieSeen && !page.unlockAnimations[0].seen);
    PMOSAction action;
    assert(PMOSClick(session, 0, &action) && action.unlockAnimation == 1);
    store.unlock = 1; /* Host marks completion; Lua sampling does not. */
    assert(PMOSClick(session, 0, &action) && !action.unlockAnimation);
    PMOSStop(session);
    store.movie = 1;
    session = PMOSStartWithProgress(source, strlen(source), 1, &page, callbacks);
    assert(session && page.entryMovieSeen && page.unlockAnimations[0].seen);
    PMOSStop(session);
    source = "unlockAnimation{id='clip',song=1,style='mod',src='clip.pma',when='event',once=false};"
             "hotspot{onClick=function() return {unlockAnimation='clip'} end}";
    session = PMOSStartWithProgress(source, strlen(source), 1, &page, callbacks);
    assert(session && !page.unlockAnimations[0].seen);
    assert(PMOSClick(session, 0, &action) && action.unlockAnimation == 1);
    assert(PMOSClick(session, 0, &action) && action.unlockAnimation == 1);
    PMOSStop(session);
    const char *closed[] = {
        "hotspot{onClick=function() onEnterMovie{key='intro',src='clip.pma'} end}",
        "hotspot{onClick=function() unlockAnimation{id='clip',song=1,style='mod',src='clip.pma'} end}"
    };
    for (size_t i = 0; i < sizeof(closed)/sizeof(*closed); ++i) {
        session = PMOSStart(closed[i], strlen(closed[i]), 1, &page);
        assert(session);
        assert(!PMOSClick(session, 0, &action) && strstr(action.error, "declarations are closed"));
        PMOSStop(session);
    }
}
static void entryTransitionUnchanged(void) {
    rejects("screen('intro');image{src='clip.pma'};"
            "entryTransition{kind='timeline',screen='intro',duration=2}");
    rejects("entryTransition{kind='timeline',screen='intro',duration=2};"
            "screen('intro');image{src='clip.PMA'}");
    rejects("entryTransition{kind='video',src='clip.pma'}");
    accepts("onEnterMovie{key='intro',src='clip.pma'};screen('intro');image{src='still.png'};"
            "entryTransition{kind='timeline',screen='intro',duration=2};screen('map');image{src='clip.pma'}");
    assert(page.entryTransition.screen == 0 && page.initialScreen == 1);
}
int main(void) {
    namesAndLegacy(); invalidNames(); onceAndCallbacks(); entryTransitionUnchanged();
    puts("PMChapterPMAOneShotTest passed");
    return 0;
}
