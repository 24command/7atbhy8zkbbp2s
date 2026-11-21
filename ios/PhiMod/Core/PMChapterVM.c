#include "PMChapterVM.h"
#include "../Vendor/lua54/lua.h"
#include "../Vendor/lua54/lauxlib.h"
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

enum { MemoryLimit = 8 * 1024 * 1024, SourceLimit = 2 * 1024 * 1024, InstructionLimit = 150000 };

typedef struct { int ref, song, dest, screen, challenge; char id[sizeof(((PMOSNode *)0)->id)]; } ClickTarget;
struct PMOSSession {
    lua_State *L;
    size_t bytes;
    int songs, nodes, screens;
    char names[PMOSMaxScreens][PMOSScreenNameSize];
    ClickTarget clicks[PMOSMaxNodes];
    int challengeCount;
    struct { char id[PMOSChallengeIdMax + 1]; PMOSChallengeState state; } challenges[PMOSMaxChallenges];
    PMOSPage *declaring;
    PMOSProgress progress;
    size_t accesses, changeCount;
    PMOSProgressChange changes[PMOSProgressAccessLimit];
};

static void *budget(void *ctx, void *ptr, size_t old, size_t size) {
    PMOSSession *s = ctx;
    if (!ptr) old = 0;
    size_t kept = s->bytes - old;
    if (!size) {
        free(ptr);
        s->bytes = kept;
        return NULL;
    }
    if (size > MemoryLimit - kept) return NULL;
    void *p = realloc(ptr, size);
    if (p) s->bytes = kept + size;
    return p;
}

static PMOSSession *session(lua_State *L) {
    void *ctx;
    lua_getallocf(L, &ctx);
    return ctx;
}

static void countProgressAccess(lua_State *L, PMOSSession *s) {
    if (s->accesses >= PMOSProgressAccessLimit) luaL_error(L, "progress access limit exceeded");
    ++s->accesses;
}

static void validateKeyChars(lua_State *L, const char *key, size_t len) {
    for (size_t i = 0; i < len; ++i) {
        char c = key[i];
        if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
              (c >= '0' && c <= '9') || c == '_' || c == '.' || c == '-'))
            luaL_error(L, "invalid progress key character");
    }
}

static const char *progressKey(lua_State *L, int argc) {
    if (lua_gettop(L) != argc) luaL_error(L, "wrong number of progress arguments");
    luaL_checktype(L, 1, LUA_TSTRING);
    size_t len;
    const char *key = lua_tolstring(L, 1, &len);
    if (!len || len > PMOSProgressKeyMax) luaL_error(L, "invalid progress key length");
    validateKeyChars(L, key, len);
    return key;
}

static PMOSProgressChange *stagedChange(PMOSSession *s, const char *key) {
    for (size_t i = 0; i < s->changeCount; ++i)
        if (!strcmp(s->changes[i].key, key)) return &s->changes[i];
    return NULL;
}

static int readProgress(lua_State *L, PMOSSession *s, const char *key) {
    countProgressAccess(L, s);
    PMOSProgressChange *change = stagedChange(s, key);
    int value = 0;
    if (change) value = change->value;
    else if (s->progress.read && s->progress.read(s->progress.context, key, &value) != 1)
        return luaL_error(L, "progress read failed");
    return value;
}

static int progressGet(lua_State *L) {
    lua_pushinteger(L, readProgress(L, session(L), progressKey(L, 1)));
    return 1;
}

static int progressSet(lua_State *L) {
    PMOSSession *s = session(L);
    const char *key = progressKey(L, 2);
    countProgressAccess(L, s);
    if (!lua_isinteger(L, 2)) return luaL_error(L, "progress value must be an integer");
    lua_Integer value = lua_tointeger(L, 2);
    if (value < INT_MIN || value > INT_MAX) return luaL_error(L, "progress integer out of range");
    if (!s->progress.commit) return luaL_error(L, "progress commit unavailable");
    PMOSProgressChange *change = stagedChange(s, key);
    if (!change) {
        change = &s->changes[s->changeCount++]; /* At most one new key per access. */
        memcpy(change->key, key, lua_rawlen(L, 1) + 1);
    }
    change->value = (int)value;
    return 0;
}

static PMOSPage *declarationPage(lua_State *L) {
    PMOSPage *page = session(L)->declaring;
    if (!page) luaL_error(L, "chapter declarations are closed");
    return page;
}

static void limit(lua_State *L, lua_Debug *ar) {
    (void)ar;
    luaL_error(L, "instruction limit exceeded");
}

static int findScreen(char names[][PMOSScreenNameSize], int count, const char *name) {
    for (int i = 0; i < count; ++i)
        if (!strcmp(names[i], name)) return i;
    return -1;
}

static int home(lua_State *L) {
    PMOSPage *page = declarationPage(L);
    size_t n;
    const char *mode = luaL_checklstring(L, 1, &n);
    if (n == 4 && !memcmp(mode, "list", 4)) page->listFirst = 1;
    else if (n == 2 && !memcmp(mode, "os", 2)) page->listFirst = 0;
    else return luaL_error(L, "home expects os or list");
    return 0;
}

static void text(lua_State *L, int i, char *dst, size_t cap) {
    if (lua_isnoneornil(L, i)) return;
    size_t n;
    const char *v = luaL_checklstring(L, i, &n);
    if (n >= cap || memchr(v, 0, n)) luaL_error(L, "invalid or oversized card text");
    memcpy(dst, v, n);
    dst[n] = 0;
}

/* During declaration the binding field holds a Lua registry reference so the
   ID survives until all challenges have been declared. Zero means absent. */
static int challengeBindingRef(lua_State *L, int table) {
    lua_getfield(L, table, "challenge");
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        return 0;
    }
    luaL_checktype(L, -1, LUA_TSTRING);
    size_t len;
    const char *id = lua_tolstring(L, -1, &len);
    if (!len || len > PMOSChallengeIdMax) return luaL_error(L, "invalid challenge id length");
    validateKeyChars(L, id, len);
    return luaL_ref(L, LUA_REGISTRYINDEX);
}

#include "PMChapterLayout.inc"

static int card(lua_State *L) {
    PMOSPage *page = declarationPage(L);
    lua_Integer index = luaL_checkinteger(L, 1);
    if (index < 1 || index > session(L)->songs) return luaL_error(L, "song number outside chapter order");
    if (page->count >= 128) return luaL_error(L, "too many cards");
    PMOSCard *c = &page->cards[page->count++];
    c->song = (int)index;
    text(L, 2, c->title, sizeof(c->title));
    text(L, 3, c->caption, sizeof(c->caption));
    if (!lua_isnoneornil(L, 4)) {
        luaL_checktype(L, 4, LUA_TTABLE);
        c->challenge = challengeBindingRef(L, 4);
        c->speech = !c->challenge; /* A legacy options table, even {}, enables speech. */
        if (c->challenge) {
            lua_pushnil(L);
            while (lua_next(L, 4)) {
                char key[sizeof("challenge")];
                word(L, -2, key, sizeof(key));
                if (!strcmp(key, "seconds") || !strcmp(key, "heading")) c->speech = 1;
                else if (strcmp(key, "challenge")) return luaL_error(L, "unknown card challenge option: %s", key);
                lua_pop(L, 1);
            }
            if (!c->speech) return 0;
        }
        lua_getfield(L, 4, "seconds");
        c->seconds = luaL_optnumber(L, -1, 0);
        lua_pop(L, 1);
        if (!(c->seconds >= 0 && c->seconds <= 86400)) return luaL_error(L, "invalid speech length");
        lua_getfield(L, 4, "heading");
        text(L, -1, c->speechHeading, sizeof(c->speechHeading));
        lua_pop(L, 1);
    }
    return 0;
}

#include "PMChapterChallenge.inc"

static int resolveChallengeBinding(lua_State *L, const PMOSPage *page, int ref) {
    lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
    const char *id = lua_tostring(L, -1);
    for (int i = 0; i < page->challengeCount; ++i) {
        if (!strcmp(id, page->challenges[i].id)) {
            luaL_unref(L, LUA_REGISTRYINDEX, ref);
            lua_pop(L, 1);
            return i + 1;
        }
    }
    return luaL_error(L, "unknown challenge: %s", id);
}

static void resolveChallengeBindings(lua_State *L, PMOSPage *page) {
    for (int i = 0; i < page->nodes; ++i) {
        PMOSNode *node = &page->elements[i];
        if (!node->challenge) continue;
        node->challenge = resolveChallengeBinding(L, page, node->challenge);
        node->handler = page->challenges[node->challenge - 1].state != PMOSChallengeLocked;
    }
    for (int i = 0; i < page->count; ++i) {
        PMOSCard *card = &page->cards[i];
        if (card->challenge) card->challenge = resolveChallengeBinding(L, page, card->challenge);
    }
}

typedef struct { const char *source; size_t length; } Script;

static int evaluate(lua_State *L) {
    const Script *script = lua_touserdata(L, 1);
    lua_pushcfunction(L, home);
    lua_setglobal(L, "home");
    lua_pushcfunction(L, card);
    lua_setglobal(L, "card");
    lua_pushinteger(L, session(L)->songs);
    lua_setglobal(L, "song_count");
    lua_createtable(L, 0, 2);
    lua_pushcfunction(L, progressGet);
    lua_setfield(L, -2, "get");
    lua_pushcfunction(L, progressSet);
    lua_setfield(L, -2, "set");
    lua_setglobal(L, "progress");
    lua_pushcfunction(L, declareChallenge);
    lua_setglobal(L, "challenge");
    lua_pushcfunction(L, challengeProgress);
    lua_setglobal(L, "challengeProgress");
    registerLayout(L);
    if (luaL_loadbufferx(L, script->source, script->length, "@os.lua", "t")) return lua_error(L);
    lua_call(L, 0, 0);
    resolveLinks(L);
    resolveChallengeBindings(L, declarationPage(L));
    return 0;
}

/* All allocating Lua operations, including action decoding, run inside pcall.
   The outer stack only receives a light C function and scalar arguments. */
static int runProtected(PMOSSession *s, int nargs, char *error, size_t cap) {
    lua_State *L = s->L;
    s->accesses = s->changeCount = 0;
    lua_sethook(L, limit, LUA_MASKCOUNT, InstructionLimit);
    int status = lua_pcall(L, nargs, 0, 0);
    lua_sethook(L, NULL, 0, 0);
    if (status == LUA_OK) {
        if (s->changeCount && s->progress.commit(s->progress.context, s->changes, s->changeCount) != 1) {
            snprintf(error, cap, "progress commit failed");
            return 0;
        }
        return 1;
    }
    const char *msg = lua_type(L, -1) == LUA_TSTRING ? lua_tostring(L, -1) : NULL;
    snprintf(error, cap, "%s", msg ? msg : "script failed");
    lua_pop(L, 1);
    return 0;
}

void PMOSStop(PMOSSession *s) {
    if (!s) return;
    if (s->L) lua_close(s->L);
    free(s);
}

PMOSSession *PMOSStart(const char *src, size_t len, int songs, PMOSPage *page) {
    PMOSProgress callbacks = {0};
    return PMOSStartWithProgress(src, len, songs, page, callbacks);
}

PMOSSession *PMOSStartWithProgress(const char *src, size_t len, int songs,
                                  PMOSPage *page, PMOSProgress callbacks) {
    if (!page) return NULL;
    memset(page, 0, sizeof(*page));
    if (!src || !len || len > SourceLimit || songs < 0) {
        snprintf(page->error, sizeof(page->error), "invalid OS input");
        return NULL;
    }
    PMOSSession *s = calloc(1, sizeof(*s));
    if (!s || !(s->L = lua_newstate(budget, s))) {
        snprintf(page->error, sizeof(page->error), "cannot create Lua state");
        PMOSStop(s);
        return NULL;
    }
    s->progress = callbacks;
    s->songs = songs;
    s->declaring = page;
    Script script = {src, len};
    lua_pushcfunction(s->L, evaluate);
    lua_pushlightuserdata(s->L, &script);
    int ok = runProtected(s, 1, page->error, sizeof(page->error));
    s->declaring = NULL;
    if (!ok) {
        page->count = page->nodes = page->screens = page->challengeCount = 0;
        PMOSStop(s);
        return NULL;
    }
    s->challengeCount = page->challengeCount;
    for (int i = 0; i < s->challengeCount; ++i) {
        strcpy(s->challenges[i].id, page->challenges[i].id);
        s->challenges[i].state = page->challenges[i].state;
    }
    s->nodes = page->nodes;
    s->screens = page->screens;
    memcpy(s->names, page->names, sizeof(s->names));
    for (int i = 0; i < s->nodes; ++i) {
        const PMOSNode *node = &page->elements[i];
        ClickTarget *target = &s->clicks[i];
        target->challenge = node->handler ? node->challenge : 0;
        target->song = node->open;
        target->dest = node->dest;
        target->screen = node->screen;
        memcpy(target->id, node->id, sizeof(target->id));
    }
    return s;
}

static int actionSong(lua_State *L, const PMOSSession *s, const char *action) {
    luaL_checktype(L, -1, LUA_TNUMBER);
    lua_Integer n = luaL_checkinteger(L, -1);
    if (n < 1 || n > s->songs) return luaL_error(L, "invalid song number in %s", action);
    return (int)n;
}

static int actionScreen(lua_State *L, PMOSSession *s) {
    char name[PMOSScreenNameSize];
    word(L, -1, name, sizeof(name));
    int dest = findScreen(s->names, s->screens, name);
    if (dest < 0) return luaL_error(L, "unknown target screen: %s", name);
    return dest;
}

static void parseCheckpoint(lua_State *L, PMOSSession *s, PMOSAction *action) {
    luaL_checktype(L, -1, LUA_TTABLE);
    int table = lua_gettop(L);
    lua_pushnil(L);
    while (lua_next(L, table)) {
        char key[sizeof("difficulty")];
        word(L, -2, key, sizeof(key));
        if (!strcmp(key, "mode")) {
            char mode[sizeof("relaunch")];
            word(L, -1, mode, sizeof(mode));
            if (!strcmp(mode, "session")) action->checkpoint = 1;
            else if (!strcmp(mode, "relaunch")) action->checkpoint = 2;
            else luaL_error(L, "checkpoint mode must be session or relaunch");
        } else if (!strcmp(key, "page")) {
            action->dest = actionScreen(L, s);
        } else if (!strcmp(key, "song")) {
            action->song = actionSong(L, s, "checkpoint");
        } else if (!strcmp(key, "difficulty")) {
            word(L, -1, action->difficulty, sizeof(action->difficulty));
        } else luaL_error(L, "unknown checkpoint field: %s", key);
        lua_pop(L, 1);
    }
    if (!action->checkpoint) luaL_error(L, "checkpoint requires a mode");
    if ((action->dest >= 0) == (action->song > 0))
        luaL_error(L, "checkpoint requires exactly one page or song");
    if (action->difficulty[0] && !action->song)
        luaL_error(L, "checkpoint difficulty requires a song");
}

static int invokeHandler(lua_State *L) {
    PMOSSession *s = session(L);
    PMOSAction *action = lua_touserdata(L, 1);
    const ClickTarget *target = lua_touserdata(L, 2);
    lua_settop(L, 0);
    lua_rawgeti(L, LUA_REGISTRYINDEX, target->ref);
    lua_call(L, 0, LUA_MULTRET);
    if (lua_gettop(L) <= 1 && lua_isnoneornil(L, 1)) return 0;
    if (lua_gettop(L) != 1 || !lua_istable(L, 1))
        return luaL_error(L, "onClick must return nil or one action table");

    lua_pushnil(L);
    if (!lua_next(L, 1)) return luaL_error(L, "empty onClick action");
    char key[sizeof("checkpoint")];
    word(L, -2, key, sizeof(key));
    if (!strcmp(key, "checkpoint")) {
        parseCheckpoint(L, s, action);
    } else if (!strcmp(key, "challenge")) {
        action->challenge = challengeAction(L, s);
    } else if (!strcmp(key, "open")) {
        action->song = actionSong(L, s, "open");
    } else if (!strcmp(key, "to")) {
        action->dest = actionScreen(L, s);
    } else if (!strcmp(key, "show") || !strcmp(key, "hide")) {
        char id[sizeof(target->id)];
        word(L, -1, id, sizeof(id));
        for (int i = 0; i < s->nodes; ++i) {
            if (s->clicks[i].screen == target->screen && !strcmp(s->clicks[i].id, id)) {
                action->element = i;
                break;
            }
        }
        if (action->element < 0) return luaL_error(L, "unknown element on clicked screen: %s", id);
        action->visible = !strcmp(key, "show");
    } else return luaL_error(L, "unknown onClick action: %s", key);
    lua_pop(L, 1);
    if (lua_next(L, 1)) return luaL_error(L, "onClick action must have exactly one field");
    return 0;
}

int PMOSClick(PMOSSession *s, int node, PMOSAction *out) {
    if (!out) return 0;
    memset(out, 0, sizeof(*out));
    out->dest = out->element = -1;
    if (!s || node < 0 || node >= s->nodes) {
        snprintf(out->error, sizeof(out->error), "invalid chapter node");
        return 0;
    }
    ClickTarget *target = &s->clicks[node];
    if (!target->ref) {
        out->challenge = target->challenge;
        out->song = target->song;
        out->dest = target->dest;
        return 1;
    }
    PMOSAction parsed = *out;
    lua_pushcfunction(s->L, invokeHandler);
    lua_pushlightuserdata(s->L, &parsed);
    lua_pushlightuserdata(s->L, target);
    if (!runProtected(s, 2, out->error, sizeof(out->error))) return 0;
    *out = parsed;
    return 1;
}

int PMBuildOSPage(const char *source, size_t len, int songs, PMOSPage *page) {
    PMOSSession *s = PMOSStart(source, len, songs, page);
    if (!s) return 0;
    PMOSStop(s);
    return 1;
}
