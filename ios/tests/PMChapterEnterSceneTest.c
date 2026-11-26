#include "../PhiMod/Core/PMChapterVM.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

#define SPEC "{key='gate-red-return',screen='clear_return',to='kaleidoscope',duration=9}"
#define DECLARE "onEnterScene" SPEC ";"
#define BASE "local d=" SPEC ";"
#define SCREENS "screen('ordinary');frame{};screen('clear_return');image{src='clear.pma'};" \
    "screen('kaleidoscope');hotspot{open=1};"
#define MOVIE "onEnterMovie{key='intro',src='intro.mp4'};"
#define TRANSITION "entryTransition{kind='timeline',screen='intro',duration=1};screen('intro');frame{};"

static PMOSPage page;
typedef struct {
    int scene, movie, firstClear, reads, sceneReads, movieReads, commits, failRead;
    char sceneKey[PMOSProgressKeyMax + 1];
} Store;

static int readFlag(void *context, const char *key, int *value) {
    Store *store = context;
    ++store->reads;
    assert(strlen(key) <= PMOSProgressKeyMax);
    if (!strncmp(key, "scene.", 6)) {
        ++store->sceneReads;
        strcpy(store->sceneKey, key);
        *value = store->scene;
    } else if (!strcmp(key, "movie.intro")) {
        ++store->movieReads;
        *value = store->movie;
    } else if (!strcmp(key, "first-clear")) *value = store->firstClear;
    else *value = 0;
    return !store->failRead;
}
static int commit(void *context, const PMOSProgressChange *changes, size_t count) {
    (void)changes; (void)count;
    ++((Store *)context)->commits;
    return 1;
}
static PMOSSession *start(const char *source, Store *store) {
    PMOSProgress progress = {store, readFlag, commit};
    return PMOSStartWithProgress(source, strlen(source), 3, &page, progress);
}
static int build(const char *source, Store *store) {
    PMOSSession *session = start(source, store);
    int ok = session != NULL;
    PMOSStop(session);
    return ok;
}
static void accepts(const char *source, Store *store) {
    int ok = build(source, store);
    if (!ok) fprintf(stderr, "Unexpected rejection: %s\n%s\n", source, page.error);
    assert(ok && !page.error[0] && !store->commits);
}
static void rejects(const char *source, Store *store, const char *message) {
    int ok = build(source, store);
    if (ok || !strstr(page.error, message))
        fprintf(stderr, "Expected rejection containing '%s': %s\nActual: %s\n", message, source, page.error);
    assert(!ok && strstr(page.error, message) && !store->commits);
    assert(!page.enterScene.declared && !page.enterScene.key[0]);
    assert(page.enterScene.sourceScreen == -1 && page.enterScene.toScreen == -1);
    assert(page.enterScene.initialScreen == -1 && !page.nodes && !page.count);
}
static void rejectsEdit(const char *edit, const char *message) {
    char source[4096];
    int n = snprintf(source, sizeof(source), BASE "%s;onEnterScene(d);" SCREENS, edit);
    assert(n > 0 && (size_t)n < sizeof(source));
    Store store = {0};
    rejects(source, &store, message);
}

static void schemaAndOnceRouting(void) {
    Store store = {0};
    accepts(DECLARE SCREENS, &store); /* Forward screen references. */
    PMOSEnterScene scene = page.enterScene;
    assert(scene.declared && !scene.seen && scene.duration == 9);
    assert(!strcmp(scene.key, "scene.gate-red-return"));
    assert(!strcmp(scene.sourceScreenName, "clear_return") && !strcmp(scene.toName, "kaleidoscope"));
    assert(scene.sourceScreen == 1 && scene.toScreen == 2 && scene.initialScreen == 1);
    assert(page.initialScreen == 0 && page.screens == 3 && page.nodes == 3);
    assert(!strcmp(page.elements[1].src, "clear.pma"));
    assert(store.reads == 1 && store.sceneReads == 1 && !store.movieReads);
    assert(!strcmp(store.sceneKey, scene.key));
    accepts(SCREENS DECLARE, &store);
    assert(!page.enterScene.seen && page.enterScene.initialScreen == 1 && !store.commits);
    store.scene = 1; /* Simulate host completion, never a VM timing write. */
    accepts(DECLARE SCREENS, &store);
    assert(page.enterScene.seen && page.enterScene.initialScreen == 2 && page.initialScreen == 0);
    assert(!scene.seen && scene.initialScreen == 1); /* Values survive Lua teardown. */
    store.scene = -4; /* Same nonzero progress convention as the other plans. */
    accepts(DECLARE SCREENS, &store);
    assert(page.enterScene.seen && page.enterScene.initialScreen == 2);
    assert(PMBuildOSPage(DECLARE SCREENS, strlen(DECLARE SCREENS), 3, &page));
    assert(!page.enterScene.seen && page.enterScene.initialScreen == 1); /* No store defaults unseen. */
    accepts(BASE "d.duration=600;onEnterScene(d);" SCREENS, &store);
    assert(page.enterScene.duration == 600);
    accepts(BASE "d.duration=.125;onEnterScene(d);" SCREENS, &store);
    assert(page.enterScene.duration == .125);
    accepts(BASE "d.duration=1e-300;onEnterScene(d);" SCREENS, &store);
    assert(page.enterScene.duration > 0);
}

static void schemaErrors(void) {
    const char *required[] = {"key", "screen", "to", "duration"};
    char edit[256];
    for (size_t i = 0; i < sizeof(required)/sizeof(*required); ++i) {
        snprintf(edit, sizeof(edit), "d.%s=nil", required[i]);
        rejectsEdit(edit, "requires key, screen, to and duration");
    }
    const char *badCalls[] = {"onEnterScene()", "onEnterScene(nil)", "onEnterScene(false)",
        "onEnterScene(1)", "onEnterScene('x')", "onEnterScene(" SPEC ",{})"};
    Store store = {0};
    for (size_t i = 0; i < sizeof(badCalls)/sizeof(*badCalls); ++i)
        rejects(badCalls[i], &store, "expects one table");
    rejects("onEnterScene{}", &store, "requires");
    rejects(DECLARE SCREENS DECLARE, &store, "only one onEnterScene");
    store.scene = 1;
    rejects(DECLARE SCREENS DECLARE, &store, "only one onEnterScene");
    const char *numbers[] = {"true", "false", "'9'", "{}", "0", "-1", "600.0001", "1/0", "-1/0", "0/0"};
    for (size_t i = 0; i < sizeof(numbers)/sizeof(*numbers); ++i) {
        snprintf(edit, sizeof(edit), "d.duration=%s", numbers[i]);
        rejectsEdit(edit, i < 4 ? "must be a number" : "finite and in (0,600]");
    }
    const char *fields[] = {"key", "screen", "to"};
    const char *strings[] = {"true", "false", "9", "{}", "''", "'a\\0b'", "'\\255'", "'\\226\\130'"};
    for (size_t f = 0; f < sizeof(fields)/sizeof(*fields); ++f) {
        for (size_t i = 0; i < sizeof(strings)/sizeof(*strings); ++i) {
            snprintf(edit, sizeof(edit), "d.%s=%s", fields[f], strings[i]);
            rejectsEdit(edit, i < 4 ? "must be a string" : i < 6 ? "empty, oversized or contains NUL" : "valid UTF-8");
        }
    }
    rejectsEdit("d.extra=1", "unknown onEnterScene field");
    rejectsEdit("d.onComplete=function() end", "unknown onEnterScene field");
    rejectsEdit("d.once=false", "unknown onEnterScene field");
    rejectsEdit("d.seen=true", "unknown onEnterScene field");
    rejectsEdit("d[1]=1", "field name must be a string");
    rejectsEdit("d[false]=1", "field name must be a string");
    rejectsEdit("d['key\\0']=1", "contains NUL");
    rejectsEdit("d.screen='missing'", "unknown onEnterScene screen");
    rejectsEdit("d.to='missing'", "unknown onEnterScene to");
    rejectsEdit("d.to=d.screen", "must be distinct");
    rejects(DECLARE, &store, "unknown onEnterScene screen");
    store.failRead = 1;
    rejects(DECLARE SCREENS, &store, "progress read failed");
}

static void keyAndScreenBounds(void) {
    assert(PMOSEnterSceneKeyMax == 58 && sizeof(page.enterScene.key) == 65);
    char key[60], source[4096];
    memset(key, 'k', 58); key[58] = 0;
    Store store = {0};
    snprintf(source, sizeof(source), BASE "d.key='%s';onEnterScene(d);" SCREENS, key);
    accepts(source, &store);
    assert(strlen(page.enterScene.key) == PMOSProgressKeyMax);
    assert(strlen(store.sceneKey) == PMOSProgressKeyMax && !strcmp(page.enterScene.key, store.sceneKey));
    assert(!strncmp(store.sceneKey, "scene.", 6) && !strcmp(store.sceneKey + 6, key));
    key[58] = 'k'; key[59] = 0;
    snprintf(source, sizeof(source), "d.key='%s'", key);
    rejectsEdit(source, "oversized");
    accepts(BASE "d.key='AZaz09_.-';onEnterScene(d);" SCREENS, &store);
    const char *badKeys[] = {"a/b", "a\\\\b", "a:b", "a b", "a\\1b", "a\\127b", "返回"};
    for (size_t i = 0; i < sizeof(badKeys)/sizeof(*badKeys); ++i) {
        snprintf(source, sizeof(source), "d.key='%s'", badKeys[i]);
        rejectsEdit(source, "invalid progress key character");
    }
    char name[65]; memset(name, 's', 63); name[63] = 0;
    snprintf(source, sizeof(source), BASE "d.screen='%s';onEnterScene(d);screen('%s');screen('kaleidoscope')", name, name);
    accepts(source, &store);
    assert(strlen(page.enterScene.sourceScreenName) == 63 && page.enterScene.sourceScreen == 0);
    snprintf(source, sizeof(source), BASE "d.to='%s';onEnterScene(d);screen('clear_return');screen('%s')", name, name);
    accepts(source, &store);
    assert(strlen(page.enterScene.toName) == 63 && page.enterScene.toScreen == 1);
    name[63] = 's'; name[64] = 0;
    snprintf(source, sizeof(source), "d.screen='%s'", name); rejectsEdit(source, "oversized");
    snprintf(source, sizeof(source), "d.to='%s'", name); rejectsEdit(source, "oversized");
    accepts("onEnterScene{key='utf8',screen='返回',to='地图',duration=1};screen('返回');screen('地图')", &store);
    assert(!strcmp(page.enterScene.sourceScreenName, "返回") && !strcmp(page.enterScene.toName, "地图"));
}

static void transitionAndMovieConflicts(void) {
    Store store = {0};
    accepts(DECLARE TRANSITION SCREENS, &store);
    assert(page.entryTransition.screen == 0 && page.initialScreen == 1);
    assert(page.enterScene.sourceScreen == 2 && page.enterScene.toScreen == 3 && page.enterScene.initialScreen == 2);
    rejects(BASE "d.screen='intro';onEnterScene(d);" SCREENS TRANSITION, &store, "reserved entryTransition screen");
    rejects(TRANSITION SCREENS BASE "d.to='intro';onEnterScene(d)", &store, "reserved entryTransition screen");
    store.scene = 1;
    rejects(BASE "d.screen='intro';onEnterScene(d);" SCREENS TRANSITION, &store, "reserved entryTransition screen");
    rejects(BASE "d.to='intro';onEnterScene(d);" SCREENS TRANSITION, &store, "reserved entryTransition screen");
    accepts("entryTransition{kind='native'};" DECLARE SCREENS, &store);
    accepts("entryTransition{kind='video',src='intro.mp4'};" DECLARE SCREENS, &store);
    for (int scene = 0; scene <= 1; ++scene) {
        for (int movie = 0; movie <= 1; ++movie) {
            store.scene = scene; store.movie = movie;
            const char *sources[] = {DECLARE MOVIE SCREENS, MOVIE SCREENS DECLARE};
            for (size_t i = 0; i < 2; ++i) {
                if (!scene && !movie) rejects(sources[i], &store, "cannot both be active");
                else {
                    accepts(sources[i], &store);
                    assert(page.enterScene.seen == scene && page.entryMovieSeen == movie);
                    assert(page.enterScene.initialScreen == (scene ? 2 : 1));
                }
            }
        }
    }
    const char *conditional = "if progress.get('first-clear')~=0 then " DECLARE "else " MOVIE "end;" SCREENS;
    store.scene = store.movie = store.firstClear = 0;
    accepts(conditional, &store);
    assert(!page.enterScene.declared && page.entryMovieKey[0]);
    store.firstClear = 1;
    accepts(conditional, &store);
    assert(page.enterScene.declared && !page.entryMovieKey[0] && page.enterScene.initialScreen == 1);
}

static void callbacksAndLegacy(void) {
    const char *source = SCREENS
        "hotspot{onClick=function() progress.set('x',1);" DECLARE "end};"
        "hotspot{onClick=function() return {onEnterScene=" SPEC "} end};"
        "hotspot{onClick=function() return {to='ordinary'} end}";
    Store store = {0};
    PMOSSession *session = start(source, &store);
    assert(session && !page.enterScene.declared && store.reads == 0);
    PMOSAction action;
    assert(!PMOSClick(session, 3, &action) && strstr(action.error, "declarations are closed"));
    assert(!page.enterScene.declared && !store.commits && !store.sceneReads);
    assert(!PMOSClick(session, 4, &action)); /* No new callback action either. */
    assert(PMOSClick(session, 5, &action) && action.dest == 0);
    PMOSStop(session);
    session = start(DECLARE SCREENS, &store);
    assert(session && !page.enterScene.seen);
    store.scene = 1;
    assert(!page.enterScene.seen && page.enterScene.initialScreen == 1); /* No live timing/progress callbacks. */
    PMOSStop(session);
    store.reads = store.sceneReads = 0;
    accepts("home('list');card(1,'old title','old caption')", &store);
    assert(!page.enterScene.declared && page.enterScene.initialScreen == -1 && !store.reads);
    assert(page.initialScreen == -1 && page.listFirst && page.count == 1);
    accepts(SCREENS, &store);
    assert(!page.enterScene.declared && page.initialScreen == 0 && !store.reads);
    assert(page.enterScene.sourceScreen == -1 && page.enterScene.toScreen == -1);
    accepts(MOVIE SCREENS, &store);
    assert(!page.enterScene.declared && !page.entryMovieSeen && page.initialScreen == 0);
}

int main(void) {
    schemaAndOnceRouting(); schemaErrors(); keyAndScreenBounds();
    transitionAndMovieConflicts(); callbacksAndLegacy();
    puts("chapter on-enter scene VM tests passed");
    return 0;
}
