#include "PMStockIntroResolver.h"

/* Optional lists leave their table (or nil) on the stack for ordered reads. */
static int presentationArray(lua_State *L, const char *field, int limit) {
    lua_getfield(L, 1, field);
    if (lua_isnil(L, -1)) return 0;
    if (!lua_istable(L, -1)) return luaL_error(L, "%s must be an array", field);
    size_t length = lua_rawlen(L, -1);
    if (length > (size_t)limit) return luaL_error(L, "%s allows at most %d entries", field, limit);
    int count = 0;
    lua_pushnil(L);
    while (lua_next(L, -2)) {
        lua_Integer key = lua_tointeger(L, -2);
        if (!lua_isinteger(L, -2) || key < 1 || key > (lua_Integer)length)
            return luaL_error(L, "%s must be a dense array", field);
        ++count;
        lua_pop(L, 1);
    }
    if ((size_t)count != length) return luaL_error(L, "%s must be a dense array", field);
    return count;
}

/* Lua strings are bytes. Reject malformed UTF-8 before passing text to the player. */
static int presentationUTF8(const unsigned char *s) {
    while (*s) {
        unsigned lead = *s++;
        if (lead < 0x80) continue;
        if (lead < 0xc2 || lead > 0xf4) return 0;
        if ((lead == 0xe0 && *s < 0xa0) || (lead == 0xed && *s >= 0xa0) ||
            (lead == 0xf0 && *s < 0x90) || (lead == 0xf4 && *s >= 0x90)) return 0;
        int tail = lead < 0xe0 ? 1 : lead < 0xf0 ? 2 : 3;
        while (tail--) {
            if ((*s & 0xc0) != 0x80) return 0;
            ++s;
        }
    }
    return 1;
}

static void challengeIntroName(lua_State *L, char *name, size_t cap) {
    word(L, -1, name, cap);
    if (PMStockIntroForName(name)) return;
    if (name[0] == '.' || strpbrk(name, "/\\:") || !presentationUTF8((const unsigned char *)name))
        luaL_error(L, "intro expects a local media basename");
    for (const unsigned char *p = (const unsigned char *)name; *p; ++p) {
        if (*p < 32 || *p == 127 || (*p == 0xc2 && p[1] < 0xa0))
            luaL_error(L, "intro basename contains a control character");
    }
    const char *suffix = strrchr(name, '.');
    if (!suffix || strlen(suffix) != 4) luaL_error(L, "intro expects a GIF or MP4 basename");
    char ext[4] = {0};
    for (int i = 0; i < 3; ++i) {
        char c = suffix[i + 1];
        ext[i] = c >= 'A' && c <= 'Z' ? (char)(c + ('a' - 'A')) : c;
    }
    if (strcmp(ext, "gif") && strcmp(ext, "mp4")) luaL_error(L, "intro expects a GIF or MP4 basename");
}

static void challengeMember(lua_State *L, PMOSChallengeSong *song, int songs, const char *field) {
    if (!lua_istable(L, -1)) luaL_error(L, "%s entries must be tables", field);
    song->song = challengeInteger(L, -1, "song", 1, songs);
    lua_pushnil(L);
    while (lua_next(L, -2)) {
        char key[sizeof("difficulty")];
        word(L, -2, key, sizeof(key));
        if (!strcmp(key, "difficulty")) {
            word(L, -1, song->difficulty, sizeof(song->difficulty));
            if (!presentationUTF8((const unsigned char *)song->difficulty))
                luaL_error(L, "invalid UTF-8 in %s difficulty", field);
        } else if (strcmp(key, "song")) {
            luaL_error(L, "unknown %s field: %s", field, key);
        }
        lua_pop(L, 1);
    }
}

static void challengePresentation(lua_State *L, PMOSChallenge *c, int songs) {
    lua_getfield(L, 1, "showDetail");
    if (!lua_isnil(L, -1) && !lua_isboolean(L, -1)) luaL_error(L, "showDetail expects true or false");
    c->showDetail = lua_isnil(L, -1) || lua_toboolean(L, -1);
    lua_pop(L, 1);

    c->introCount = presentationArray(L, "intro", PMOSMaxChallengeIntro);
    for (int i = 0; i < c->introCount; ++i) {
        lua_rawgeti(L, -1, i + 1);
        challengeIntroName(L, c->intro[i], sizeof(c->intro[i]));
        lua_pop(L, 1);
    }
    lua_pop(L, 1);

    c->nextSongCount = presentationArray(L, "nextSongs", PMOSMaxChallengeNextSongs);
    for (int i = 0; i < c->nextSongCount; ++i) {
        lua_rawgeti(L, -1, i + 1);
        challengeMember(L, &c->nextSongs[i], songs, "nextSongs");
        lua_pop(L, 1);
    }
    lua_pop(L, 1);
}
