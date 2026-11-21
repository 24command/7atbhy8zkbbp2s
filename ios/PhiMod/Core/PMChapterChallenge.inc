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
    c->song = challengeInteger(L, 1, "song", 1, s->songs);
    fieldText(L, "difficulty", c->difficulty, sizeof(c->difficulty));
    lua_getfield(L, 1, "unlocked");
    if (!lua_isnil(L, -1)) luaL_checktype(L, -1, LUA_TBOOLEAN);
    int unlocked = lua_isnil(L, -1) || lua_toboolean(L, -1);
    lua_pop(L, 1);
    challengeTiers(L, c);

    char key[PMOSProgressKeyMax + 1];
    snprintf(key, sizeof(key), "door.%s.clear", c->id);
    int clear = readProgress(L, s, key);
    snprintf(key, sizeof(key), "door.%s.fail", c->id);
    int failures = readProgress(L, s, key);
    c->failures = failures > 0 ? failures : 0;
    c->state = clear > 0 ? PMOSChallengeClear : unlocked ? PMOSChallengeClosed : PMOSChallengeLocked;
    ++page->challengeCount;
    lua_pushstring(L, c->state == PMOSChallengeClear ? "clear" : unlocked ? "closed" : "locked");
    lua_pushinteger(L, c->failures);
    return 2;
}

static int challengeAction(lua_State *L, PMOSSession *s) {
    char id[PMOSChallengeIdMax + 1];
    word(L, -1, id, sizeof(id));
    for (int i = 0; i < s->challengeCount; ++i)
        if (!strcmp(id, s->challenges[i].id))
            return s->challenges[i].state == PMOSChallengeLocked ? 0 : i + 1;
    return luaL_error(L, "unknown challenge: %s", id);
}
