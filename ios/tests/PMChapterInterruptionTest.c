#include "../PhiMod/Core/PMChapterVM.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

#define SPEC "{song=2,at=159,src='KLD_BlueScreen.png',title='stopped',message='restart',button='close',action='quit'}"
#define BASE "local d=" SPEC ";"
static PMOSPage page, copiedPage;

static int build(const char *source) {
    return PMBuildOSPage(source, strlen(source), 32, &page);
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
    assert(!page.songInterruptionCount && !page.count && !page.nodes && !page.challengeCount);
}
static void rejectsEdit(const char *edit, const char *message) {
    char source[4096];
    int n = snprintf(source, sizeof(source), BASE "%s;songInterruption(d)", edit);
    assert(n > 0 && (size_t)n < sizeof(source));
    rejects(source, message);
}

static void schemaAndOwnership(void) {
    const char *source = "songInterruption{song=2,difficulty='IN',at=159,"
        "src='KLD_BlueScreen.png',delay=2,title='7sRef.exe停止工作',"
        "message='请尝试重启',button='关闭应用',action='quit'}";
    accepts(source);
    assert(page.songInterruptionCount == 1 && !page.challengeCount && !page.count);
    const PMOSSongInterruption *value = &page.songInterruptions[0];
    assert(value->song == 2 && !strcmp(value->difficulty, "IN"));
    assert(value->at == 159 && value->delay == 2 && value->action == PMOSSongInterruptionQuit);
    assert(!strcmp(value->src, "KLD_BlueScreen.png"));
    assert(!strcmp(value->title, "7sRef.exe停止工作"));
    assert(!strcmp(value->message, "请尝试重启") && !strcmp(value->button, "关闭应用"));
    copiedPage = page; /* Build has already destroyed Lua; the values stay owned. */
    accepts(BASE "songInterruption(d);d.song=3;d.at=0;d.title='changed';"
        "d.difficulty='';d.delay=0;songInterruption(d)");
    assert(page.songInterruptionCount == 2 && !page.songInterruptions[0].difficulty[0]);
    assert(page.songInterruptions[0].delay == 2 && page.songInterruptions[0].at == 159);
    assert(!strcmp(page.songInterruptions[0].title, "stopped"));
    assert(page.songInterruptions[1].song == 3 && page.songInterruptions[1].at == 0);
    assert(!page.songInterruptions[1].difficulty[0] && page.songInterruptions[1].delay == 0);
    assert(!strcmp(copiedPage.songInterruptions[0].title, "7sRef.exe停止工作"));
    accepts(BASE "d.at=1e308;d.delay=600;d.song=32;songInterruption(d)");
    assert(page.songInterruptions[0].at == 1e308 && page.songInterruptions[0].delay == 600);
    accepts(BASE "d.song=1.0;d.at=.125;d.delay=.5;songInterruption(d)");
    assert(page.songInterruptions[0].song == 1 && page.songInterruptions[0].at == .125);
    assert(page.songInterruptions[0].delay == .5);
}

static void requiredAndTypes(void) {
    const char *required[] = {"song", "at", "src", "title", "message", "button", "action"};
    char edit[256];
    for (size_t i = 0; i < sizeof(required)/sizeof(*required); ++i) {
        snprintf(edit, sizeof(edit), "d.%s=nil", required[i]);
        rejectsEdit(edit, "requires song, at, src, title, message, button and action");
    }
    const char *calls[] = {"songInterruption()", "songInterruption(nil)",
        "songInterruption(false)", "songInterruption(1)", "songInterruption('x')",
        "songInterruption(" SPEC ",{})"};
    for (size_t i = 0; i < sizeof(calls)/sizeof(*calls); ++i) rejects(calls[i], "expects one table");
    rejects("songInterruption{}", "requires");
    const char *badSongs[] = {"true", "false", "'2'", "2.5", "0", "-1", "33", "1e100", "1/0", "0/0", "{}"};
    for (size_t i = 0; i < sizeof(badSongs)/sizeof(*badSongs); ++i) {
        snprintf(edit, sizeof(edit), "d.song=%s", badSongs[i]);
        rejectsEdit(edit, "integer within chapter order");
    }
    const char *times[] = {"at", "delay"};
    const char *badTimes[] = {"true", "false", "'2'", "{}", "-0.01", "1/0", "-1/0", "0/0"};
    for (size_t f = 0; f < 2; ++f) {
        for (size_t i = 0; i < sizeof(badTimes)/sizeof(*badTimes); ++i) {
            snprintf(edit, sizeof(edit), "d.%s=%s", times[f], badTimes[i]);
            rejectsEdit(edit, i < 4 ? "must be a number" : "finite nonnegative seconds");
        }
    }
    rejectsEdit("d.delay=600.0001", "delay must be in [0,600]");
    const char *strings[] = {"difficulty", "src", "title", "message", "button", "action"};
    const char *notStrings[] = {"true", "false", "2", "{}"};
    for (size_t f = 0; f < sizeof(strings)/sizeof(*strings); ++f) {
        for (size_t i = 0; i < sizeof(notStrings)/sizeof(*notStrings); ++i) {
            snprintf(edit, sizeof(edit), "d.%s=%s", strings[f], notStrings[i]);
            rejectsEdit(edit, "must be a string");
        }
        snprintf(edit, sizeof(edit), "d.%s='a\\0b'", strings[f]);
        rejectsEdit(edit, "contains NUL");
        if (f) {
            snprintf(edit, sizeof(edit), "d.%s=''", strings[f]);
            rejectsEdit(edit, "is empty");
        }
    }
    rejectsEdit("d.action='Quit'", "action must be quit");
    rejectsEdit("d.action='restart'", "action must be quit");
    rejectsEdit("d.extra=true", "unknown songInterruption field");
    rejectsEdit("d[1]=true", "field name must be a string");
    rejectsEdit("d[true]=true", "field name must be a string");
    rejectsEdit("d['at\\0']=0", "contains NUL");
    rejectsEdit("d['']=0", "is empty");
    assert(!PMBuildOSPage("songInterruption" SPEC, strlen("songInterruption" SPEC), 0, &page));
    assert(!page.songInterruptionCount && strstr(page.error, "chapter order"));
}

static void utf8AndBasenames(void) {
    const char *fields[] = {"difficulty", "src", "title", "message", "button"};
    /* Isolated continuation, overlong forms, surrogate, >U+10FFFF, truncated. */
    const char *invalid[] = {"\\128", "\\192\\175", "\\224\\128\\128",
        "\\237\\160\\128", "\\240\\128\\128\\128", "\\244\\144\\128\\128",
        "\\245\\128\\128\\128", "\\255", "\\226\\130", "\\240"};
    char edit[512];
    for (size_t f = 0; f < sizeof(fields)/sizeof(*fields); ++f) {
        for (size_t i = 0; i < sizeof(invalid)/sizeof(*invalid); ++i) {
            snprintf(edit, sizeof(edit), "d.%s='%s'", fields[f], invalid[i]);
            rejectsEdit(edit, "must be valid UTF-8");
        }
    }
    const char *badNames[] = {"../a.png", ".a.png", "/a.png", "dir/a.png", "dir\\\\a.png",
        "C:a.png", "https://a.png", "a.gif", "a.mp4", "a.pma", "a.svg", "a.png.exe",
        "a.png ", "a", "a\\1.png", "a\\127.png", "a\\194\\128.png", "a\\194\\159.png"};
    for (size_t i = 0; i < sizeof(badNames)/sizeof(*badNames); ++i) {
        snprintf(edit, sizeof(edit), "d.src='%s'", badNames[i]);
        rejectsEdit(edit, "local PNG/JPG/JPEG/WebP basename");
    }
    const char *goodNames[] = {"a.png", "a.JPG", "a.JpEg", "a.WeBp", "蓝屏.png"};
    char source[1024];
    for (size_t i = 0; i < sizeof(goodNames)/sizeof(*goodNames); ++i) {
        snprintf(source, sizeof(source), BASE "d.src='%s';songInterruption(d)", goodNames[i]);
        accepts(source);
        assert(!strcmp(page.songInterruptions[0].src, goodNames[i]));
    }
    accepts(BASE "d.title='\\194\\128\\224\\160\\128\\237\\159\\191"
        "\\240\\144\\128\\128\\244\\143\\191\\191';songInterruption(d)");
}

static void stringBounds(void) {
    struct { const char *name; size_t capacity; } fields[] = {
        {"difficulty", sizeof(page.songInterruptions[0].difficulty)},
        {"src", sizeof(page.songInterruptions[0].src)},
        {"title", sizeof(page.songInterruptions[0].title)},
        {"message", sizeof(page.songInterruptions[0].message)},
        {"button", sizeof(page.songInterruptions[0].button)}
    };
    char value[2048], source[4096];
    for (size_t f = 0; f < sizeof(fields)/sizeof(*fields); ++f) {
        for (int overflow = 0; overflow < 2; ++overflow) {
            size_t n = fields[f].capacity - 1 + overflow;
            memset(value, 'a', n); value[n] = 0;
            if (!strcmp(fields[f].name, "src")) memcpy(value + n - 4, ".png", 4);
            snprintf(source, sizeof(source), BASE "d.%s='%s';songInterruption(d)", fields[f].name, value);
            if (overflow) rejects(source, "oversized"); else accepts(source);
        }
    }
    /* Byte limits, not code-point limits; UTF-8 is never truncated to fit. */
    memset(value, 'a', 252);
    memcpy(value + 252, "\xe4\xb8\xad", 4);
    snprintf(source, sizeof(source), BASE "d.title='%s';songInterruption(d)", value);
    accepts(source);
    assert(strlen(page.songInterruptions[0].title) == 255);
    snprintf(source, sizeof(source), BASE "d.title='a%s';songInterruption(d)", value);
    rejects(source, "oversized");
}

static void duplicatesAndLimit(void) {
    rejects(BASE "songInterruption(d);songInterruption(d)", "duplicate songInterruption song+difficulty");
    rejects(BASE "songInterruption(d);d.difficulty='';songInterruption(d)", "duplicate songInterruption");
    rejects(BASE "d.difficulty='IN';songInterruption(d);d.at=1;d.src='other.jpg';songInterruption(d)", "duplicate songInterruption");
    accepts(BASE "songInterruption(d);d.difficulty='IN';songInterruption(d);"
        "d.difficulty='HD';songInterruption(d);d.song=3;songInterruption(d)");
    assert(page.songInterruptionCount == 4);
    assert(!page.songInterruptions[0].difficulty[0]);
    assert(!strcmp(page.songInterruptions[1].difficulty, "IN"));
    assert(!strcmp(page.songInterruptions[2].difficulty, "HD") && page.songInterruptions[2].song == 2);
    assert(page.songInterruptions[3].song == 3);
    char source[1024];
    assert(PMOSMaxSongInterruptions == 16);
    snprintf(source, sizeof(source), BASE "for i=1,%d do d.song=i;songInterruption(d) end", PMOSMaxSongInterruptions);
    accepts(source);
    assert(page.songInterruptionCount == PMOSMaxSongInterruptions);
    for (int i = 0; i < page.songInterruptionCount; ++i) assert(page.songInterruptions[i].song == i + 1);
    strcat(source, ";d.song=17;songInterruption(d)");
    rejects(source, "too many songInterruptions");
    rejects(BASE "songInterruption(d);d.song=3;d.delay=601;songInterruption(d)", "delay must be in [0,600]");
    rejects(BASE "songInterruption(d);notAFunction()", "nil value");
}

static int readFlag(void *context, const char *key, int *value) {
    (void)context; (void)key; *value = 0; return 1;
}
static int commit(void *context, const PMOSProgressChange *changes, size_t count) {
    (void)changes; (void)count; ++*(int *)context; return 1;
}
static void callbacksAndLegacy(void) {
    const char *source = BASE "songInterruption(d);screen('map');"
        "hotspot{onClick=function() progress.set('x',1);songInterruption(d) end};"
        "hotspot{onClick=function() return {songInterruption=d} end};"
        "hotspot{onClick=function() return {open=2} end}";
    int commits = 0;
    PMOSProgress progress = {&commits, readFlag, commit};
    PMOSSession *session = PMOSStartWithProgress(source, strlen(source), 3, &page, progress);
    assert(session && page.songInterruptionCount == 1);
    PMOSAction action;
    assert(!PMOSClick(session, 0, &action) && strstr(action.error, "declarations are closed"));
    assert(!commits && page.songInterruptionCount == 1);
    assert(!PMOSClick(session, 1, &action)); /* Not a new onClick action. */
    assert(PMOSClick(session, 2, &action) && action.song == 2);
    PMOSStop(session);
    accepts("home('list');card(1,'old title','old caption')");
    assert(!page.songInterruptionCount && !page.challengeCount);
    assert(page.listFirst && page.count == 1 && page.cards[0].song == 1);
    assert(!strcmp(page.cards[0].title, "old title") && !strcmp(page.cards[0].caption, "old caption"));
    accepts("screen('map');frame{};hotspot{open=1}");
    assert(!page.songInterruptionCount && page.nodes == 2 && page.elements[1].open == 1);
}

int main(void) {
    schemaAndOwnership(); requiredAndTypes(); utf8AndBasenames(); stringBounds();
    duplicatesAndLimit(); callbacksAndLegacy();
    puts("chapter song interruption VM tests passed");
    return 0;
}
