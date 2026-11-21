/* Optional challenge cues, stored in a single page-owned array. */
#include <ctype.h>

static double cueSeconds(lua_State *L, const char *key) {
    lua_getfield(L, -1, key);
    luaL_checktype(L, -1, LUA_TNUMBER);
    double value = lua_tonumber(L, -1);
    lua_pop(L, 1);
    if (!isfinite(value) || value < 0) luaL_error(L, "invalid cue %s", key);
    return value;
}

static int cueImageName(const char *src) {
    if (src[0] == '.' || strpbrk(src, "/\\:")) return 0;
    for (const unsigned char *p = (const unsigned char *)src; *p; ++p)
        if (*p < 32 || *p == 127) return 0;
    const char *dot = strrchr(src, '.');
    char ext[6]; /* Longest supported suffix is .jpeg or .webp. */
    if (!dot || strlen(dot) >= sizeof(ext)) return 0;
    size_t i = 0;
    do { ext[i] = (char)tolower((unsigned char)dot[i]); } while (dot[i++]);
    return !strcmp(ext, ".png") || !strcmp(ext, ".jpg") ||
           !strcmp(ext, ".jpeg") || !strcmp(ext, ".webp");
}

static void readCue(lua_State *L, PMOSChallengeCue *cue) {
    luaL_checktype(L, -1, LUA_TTABLE);
    cue->at = cueSeconds(L, "at");
    cue->duration = cueSeconds(L, "duration");
    if (cue->duration == 0 || !isfinite(cue->at + cue->duration))
        luaL_error(L, "invalid cue duration");

    lua_getfield(L, -1, "text");
    if (!lua_isnil(L, -1)) word(L, -1, cue->text, sizeof(cue->text));
    lua_pop(L, 1);
    lua_getfield(L, -1, "src");
    if (!lua_isnil(L, -1)) {
        word(L, -1, cue->src, sizeof(cue->src));
        if (!cueImageName(cue->src)) luaL_error(L, "cue src expects a local static image filename");
    }
    lua_pop(L, 1);
    lua_getfield(L, -1, "blockPause");
    if (!lua_isnil(L, -1)) luaL_checktype(L, -1, LUA_TBOOLEAN);
    cue->blockPause = lua_toboolean(L, -1);
    lua_pop(L, 1);
    if (!cue->text[0] && !cue->src[0] && !cue->blockPause)
        luaL_error(L, "cue needs text, src or blockPause=true");
}

static void challengeCues(lua_State *L, PMOSPage *page, PMOSChallenge *challenge) {
    challenge->cueStart = page->cueCount;
    lua_getfield(L, 1, "cues");
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        return;
    }
    luaL_checktype(L, -1, LUA_TTABLE);
    int table = lua_gettop(L);
    size_t length = lua_rawlen(L, table), seen = 0;
    int remaining = PMOSMaxChallengeCues - page->cueCount;
    if (length > (size_t)remaining) luaL_error(L, "too many challenge cues");
    lua_pushnil(L);
    while (lua_next(L, table)) {
        lua_Integer key = lua_tointeger(L, -2);
        if (!lua_isinteger(L, -2) || key < 1 || key > (lua_Integer)length)
            luaL_error(L, "challenge cues must be a dense array");
        PMOSChallengeCue cue = {0};
        readCue(L, &cue);
        page->cues[challenge->cueStart + (int)key - 1] = cue;
        ++seen;
        lua_pop(L, 1);
    }
    if (seen != length) luaL_error(L, "challenge cues must be a dense array");
    lua_pop(L, 1);
    challenge->cueCount = (int)length;
    page->cueCount += challenge->cueCount;
}
