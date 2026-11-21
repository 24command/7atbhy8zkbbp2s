/* Chapter challenge declarations and action lookup. Included by PMChapterVM.c. */
static int challengeInteger(lua_State *L, int table, const char *key, int min, int max) {
    lua_getfield(L, table, key);
    luaL_checktype(L, -1, LUA_TNUMBER);
    lua_Integer value = luaL_checkinteger(L, -1);
    if (value < min || value > max) luaL_error(L, "invalid challenge %s", key);
    lua_pop(L, 1);
    return (int)value;
}

/* Match Options::validate in PMGameplayCore.hpp before narrowing to engine floats. */
static float challengeHP(lua_State *L, const char *key, int min) {
    lua_getfield(L, -1, key);
    luaL_checktype(L, -1, LUA_TNUMBER);
    lua_Number value = lua_tonumber(L, -1);
    if (!(value >= min && value <= 10000)) luaL_error(L, "invalid challenge %s", key);
    lua_pop(L, 1);
    return (float)value;
}

static void challengeTiers(lua_State *L, PMOSChallenge *c) {
    lua_getfield(L, 1, "tiers");
    luaL_checktype(L, -1, LUA_TTABLE);
    int table = lua_gettop(L);
    size_t count = lua_rawlen(L, table);
    if (!count || count > PMOSMaxChallengeTiers) luaL_error(L, "invalid challenge tier count");
    /* rawlen alone can hide keys beyond a hole or non-array keys. */
    lua_pushnil(L);
    while (lua_next(L, table)) {
        lua_Integer key = lua_tointeger(L, -2);
        if (!lua_isinteger(L, -2) || key < 1 || key > (lua_Integer)count)
            luaL_error(L, "challenge tiers must be a dense array");
        lua_pop(L, 1);
    }
    c->tierCount = (int)count;
    for (int i = 0; i < c->tierCount; ++i) {
        lua_rawgeti(L, table, i + 1);
        luaL_checktype(L, -1, LUA_TTABLE);
        PMOSChallengeTier *tier = &c->tiers[i];
        tier->after = challengeInteger(L, -1, "after", 0, INT_MAX);
        if (i == 0 ? tier->after != 0 : tier->after <= c->tiers[i - 1].after)
            luaL_error(L, "challenge after thresholds must start at zero and increase");
        tier->hp = challengeHP(L, "hp", 1);
        tier->perfect = challengeHP(L, "perfect", -10000);
        tier->good = challengeHP(L, "good", -10000);
        tier->bad = challengeHP(L, "bad", -10000);
        tier->miss = challengeHP(L, "miss", -10000);
        lua_pop(L, 1);
    }
    lua_pop(L, 1);
}

/* Keep the installed key format behind an API so authored interfaces can use
   arbitrary artwork and query another challenge before declaring its widget. */
static void readChallengeHistory(lua_State *L, const char *id, int *cleared, int *failures) {
    char key[PMOSProgressKeyMax + 1];
    snprintf(key, sizeof(key), "door.%s.clear", id);
    *cleared = readProgress(L, session(L), key) > 0;
    snprintf(key, sizeof(key), "door.%s.fail", id);
    int count = readProgress(L, session(L), key);
    *failures = count > 0 ? count : 0;
}

static int challengeProgress(lua_State *L) {
    char id[PMOSChallengeIdMax + 1];
    if (lua_gettop(L) != 1) return luaL_error(L, "challengeProgress expects one id");
    word(L, 1, id, sizeof(id));
    validateKeyChars(L, id, strlen(id));
    int cleared, failures;
    readChallengeHistory(L, id, &cleared, &failures);
    lua_createtable(L, 0, 2);
    lua_pushboolean(L, cleared); lua_setfield(L, -2, "cleared");
    lua_pushinteger(L, failures); lua_setfield(L, -2, "failures");
    return 1;
}

#include "PMChapterPresentation.inc"
#include "PMChapterCues.inc"

static int declareChallenge(lua_State *L) {
    PMOSPage *page = declarationPage(L);
    PMOSSession *s = session(L);
    if (lua_gettop(L) != 1) return luaL_error(L, "challenge expects one table");
    luaL_checktype(L, 1, LUA_TTABLE);
    if (page->challengeCount >= PMOSMaxChallenges) return luaL_error(L, "too many challenges");
    PMOSChallenge *c = &page->challenges[page->challengeCount];
    lua_getfield(L, 1, "id");
    word(L, -1, c->id, sizeof(c->id));
    validateKeyChars(L, c->id, lua_rawlen(L, -1));
    lua_pop(L, 1);
    for (int i = 0; i < page->challengeCount; ++i)
        if (!strcmp(c->id, page->challenges[i].id)) return luaL_error(L, "duplicate challenge: %s", c->id);
    c->lifeTier = -1;
    c->courseCount = presentationArray(L, "secretCourse", 4);
    if (!lua_isnil(L, -1)) {
        if (c->courseCount < 3) return luaL_error(L, "secretCourse requires 3 or 4 members");
        for (int i=0; i<c->courseCount; ++i) {
            lua_rawgeti(L, -1, i+1);
            challengeMember(L, &c->course[i], s->songs, "secretCourse");
            lua_pop(L, 1);
        }
        c->song = c->course[0].song;
        strcpy(c->difficulty, c->course[0].difficulty);
        const char *incompatible[] = {"song", "difficulty", "tiers", "nextSongs", "cues"};
        for (size_t i=0; i<sizeof(incompatible)/sizeof(incompatible[0]); ++i) {
            lua_getfield(L, 1, incompatible[i]);
            if (!lua_isnil(L, -1)) return luaL_error(L, "secretCourse cannot use %s", incompatible[i]);
            lua_pop(L, 1);
        }
    } else {
        c->song = challengeInteger(L, 1, "song", 1, s->songs);
        fieldText(L, "difficulty", c->difficulty, sizeof(c->difficulty));
    }
    lua_pop(L, 1);
    lua_getfield(L, 1, "lifeTier");
    if (!lua_isnil(L, -1)) {
        if (!c->courseCount) return luaL_error(L, "lifeTier requires secretCourse");
        c->lifeTier = challengeInteger(L, 1, "lifeTier", -1, 4);
    }
    lua_pop(L, 1);
    lua_getfield(L, 1, "unlocked");
    if (!lua_isnil(L, -1)) luaL_checktype(L, -1, LUA_TBOOLEAN);
    int unlocked = lua_isnil(L, -1) || lua_toboolean(L, -1);
    lua_pop(L, 1);
    if (!c->courseCount) challengeTiers(L, c);
    challengePresentation(L, c, s->songs);
    challengeCues(L, page, c);

    int clear;
    readChallengeHistory(L, c->id, &clear, &c->failures);
    c->state = clear ? PMOSChallengeClear : unlocked ? PMOSChallengeClosed : PMOSChallengeLocked;
    ++page->challengeCount;
    lua_pushstring(L, c->state == PMOSChallengeClear ? "clear" : unlocked ? "closed" : "locked");
    lua_pushinteger(L, c->failures);
    lua_createtable(L, 0, 3);
    lua_pushboolean(L, c->state != PMOSChallengeLocked); lua_setfield(L, -2, "available");
    lua_pushboolean(L, clear); lua_setfield(L, -2, "cleared");
    lua_pushinteger(L, c->failures); lua_setfield(L, -2, "failures");
    return 3;
}

static int challengeAction(lua_State *L, PMOSSession *s) {
    char id[PMOSChallengeIdMax + 1];
    word(L, -1, id, sizeof(id));
    for (int i = 0; i < s->challengeCount; ++i)
        if (!strcmp(id, s->challenges[i].id))
            return s->challenges[i].state == PMOSChallengeLocked ? 0 : i + 1;
    return luaL_error(L, "unknown challenge: %s", id);
}
