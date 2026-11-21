#include "PMChapterVM.h"
#include "../Vendor/lua54/lua.h"
#include "../Vendor/lua54/lauxlib.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

enum { MemoryLimit = 8 * 1024 * 1024, SourceLimit = 2 * 1024 * 1024, InstructionLimit = 150000 };

typedef struct { int ref, song, dest, screen; char id[sizeof(((PMOSNode *)0)->id)]; } ClickTarget;
struct PMOSSession {
    lua_State *L;
    size_t bytes;
    int songs, nodes, screens;
    char names[PMOSMaxScreens][PMOSScreenNameSize];
    ClickTarget clicks[PMOSMaxNodes];
    PMOSPage *declaring;
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
        c->speech = 1;
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

#include "PMChapterLayout.inc"

typedef struct { const char *source; size_t length; } Script;

static int evaluate(lua_State *L) {
    const Script *script = lua_touserdata(L, 1);
    lua_pushcfunction(L, home);
    lua_setglobal(L, "home");
    lua_pushcfunction(L, card);
    lua_setglobal(L, "card");
    lua_pushinteger(L, session(L)->songs);
    lua_setglobal(L, "song_count");
    registerLayout(L);
    if (luaL_loadbufferx(L, script->source, script->length, "@os.lua", "t")) return lua_error(L);
    lua_call(L, 0, 0);
    resolveLinks(L);
    return 0;
}

/* All allocating Lua operations, including action decoding, run inside pcall.
   The outer stack only receives a light C function and scalar arguments. */
static int runProtected(lua_State *L, int nargs, char *error, size_t cap) {
    lua_sethook(L, limit, LUA_MASKCOUNT, InstructionLimit);
    int status = lua_pcall(L, nargs, 0, 0);
    lua_sethook(L, NULL, 0, 0);
    if (status == LUA_OK) return 1;
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
    s->songs = songs;
    s->declaring = page;
    Script script = {src, len};
    lua_pushcfunction(s->L, evaluate);
    lua_pushlightuserdata(s->L, &script);
    int ok = runProtected(s->L, 1, page->error, sizeof(page->error));
    s->declaring = NULL;
    if (!ok) {
        page->count = page->nodes = page->screens = 0;
        PMOSStop(s);
        return NULL;
    }
    s->nodes = page->nodes;
    s->screens = page->screens;
    memcpy(s->names, page->names, sizeof(s->names));
    for (int i = 0; i < s->nodes; ++i) {
        const PMOSNode *node = &page->elements[i];
        ClickTarget *target = &s->clicks[i];
        target->song = node->open;
        target->dest = node->dest;
        target->screen = node->screen;
        memcpy(target->id, node->id, sizeof(target->id));
    }
    return s;
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
    char key[8];
    word(L, -2, key, sizeof(key));
    int song = 0, dest = -1, element = -1, visible = 0;
    if (!strcmp(key, "open")) {
        luaL_checktype(L, -1, LUA_TNUMBER);
        lua_Integer n = luaL_checkinteger(L, -1);
        if (n < 1 || n > s->songs) return luaL_error(L, "invalid song number in open");
        song = (int)n;
    } else if (!strcmp(key, "to")) {
        char name[PMOSScreenNameSize];
        word(L, -1, name, sizeof(name));
        dest = findScreen(s->names, s->screens, name);
        if (dest < 0) return luaL_error(L, "unknown target screen: %s", name);
    } else if (!strcmp(key, "show") || !strcmp(key, "hide")) {
        char id[sizeof(target->id)];
        word(L, -1, id, sizeof(id));
        for (int i = 0; i < s->nodes; ++i) {
            if (s->clicks[i].screen == target->screen && !strcmp(s->clicks[i].id, id)) {
                element = i;
                break;
            }
        }
        if (element < 0) return luaL_error(L, "unknown element on clicked screen: %s", id);
        visible = !strcmp(key, "show");
    } else return luaL_error(L, "unknown onClick action: %s", key);
    lua_pop(L, 1);
    if (lua_next(L, 1)) return luaL_error(L, "onClick action must have exactly one field");
    action->song = song;
    action->dest = dest;
    action->element = element;
    action->visible = visible;
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
        out->song = target->song;
        out->dest = target->dest;
        return 1;
    }
    lua_pushcfunction(s->L, invokeHandler);
    lua_pushlightuserdata(s->L, out);
    lua_pushlightuserdata(s->L, target);
    return runProtected(s->L, 2, out->error, sizeof(out->error));
}

int PMBuildOSPage(const char *source, size_t len, int songs, PMOSPage *page) {
    PMOSSession *s = PMOSStart(source, len, songs, page);
    if (!s) return 0;
    PMOSStop(s);
    return 1;
}
