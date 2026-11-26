/* Included after presentation, cue and entry-transition validation helpers.
   Parsing owns values only: no host, filesystem or gameplay side effects. */
static void interruptionText(lua_State *L, int index, const char *field,
                             char *out, size_t cap, int allowEmpty) {
    if (lua_type(L, index) != LUA_TSTRING)
        luaL_error(L, "songInterruption %s must be a string", field);
    size_t n;
    const char *text = lua_tolstring(L, index, &n);
    if ((!n && !allowEmpty) || n >= cap || memchr(text, 0, n))
        luaL_error(L, "songInterruption %s is empty, oversized or contains NUL", field);
    if (!presentationUTF8((const unsigned char *)text))
        luaL_error(L, "songInterruption %s must be valid UTF-8", field);
    memcpy(out, text, n + 1);
}

static double interruptionSeconds(lua_State *L, const char *field) {
    if (lua_type(L, -1) != LUA_TNUMBER)
        luaL_error(L, "songInterruption %s must be a number", field);
    double value = lua_tonumber(L, -1);
    if (!isfinite(value) || value < 0)
        luaL_error(L, "songInterruption %s must be finite nonnegative seconds", field);
    return value;
}

static int declareSongInterruption(lua_State *L) {
    PMOSPage *page = declarationPage(L);
    if (lua_gettop(L) != 1 || !lua_istable(L, 1))
        return luaL_error(L, "songInterruption expects one table");
    if (page->songInterruptionCount >= PMOSMaxSongInterruptions)
        return luaL_error(L, "too many songInterruptions (maximum %d)", PMOSMaxSongInterruptions);
    PMOSSongInterruption value = {0};
    value.delay = 2;
    int hasAt = 0;
    lua_pushnil(L);
    while (lua_next(L, 1)) {
        char field[32];
        interruptionText(L, -2, "field name", field, sizeof(field), 0);
        if (!strcmp(field, "song")) {
            int isInteger = 0;
            lua_Integer song = lua_tointegerx(L, -1, &isInteger);
            if (lua_type(L, -1) != LUA_TNUMBER || !isInteger ||
                song < 1 || song > session(L)->songs)
                return luaL_error(L, "songInterruption song must be an integer within chapter order");
            value.song = (int)song;
        } else if (!strcmp(field, "difficulty")) {
            interruptionText(L, -1, field, value.difficulty, sizeof(value.difficulty), 1);
        } else if (!strcmp(field, "at")) {
            value.at = interruptionSeconds(L, field);
            hasAt = 1;
        } else if (!strcmp(field, "delay")) {
            value.delay = interruptionSeconds(L, field);
            if (value.delay > PMOSSongInterruptionMaxDelay)
                return luaL_error(L, "songInterruption delay must be in [0,600]");
        } else if (!strcmp(field, "src")) {
            interruptionText(L, -1, field, value.src, sizeof(value.src), 0);
            if (!entryLocalName(value.src) || !cueImageName(value.src))
                return luaL_error(L, "songInterruption src expects a local PNG/JPG/JPEG/WebP basename");
        } else if (!strcmp(field, "title")) {
            interruptionText(L, -1, field, value.title, sizeof(value.title), 0);
        } else if (!strcmp(field, "message")) {
            interruptionText(L, -1, field, value.message, sizeof(value.message), 0);
        } else if (!strcmp(field, "button")) {
            interruptionText(L, -1, field, value.button, sizeof(value.button), 0);
        } else if (!strcmp(field, "action")) {
            char action[16];
            interruptionText(L, -1, field, action, sizeof(action), 0);
            if (strcmp(action, "quit"))
                return luaL_error(L, "songInterruption action must be quit");
            value.action = PMOSSongInterruptionQuit;
        } else return luaL_error(L, "unknown songInterruption field: %s", field);
        lua_pop(L, 1);
    }
    if (!value.song || !hasAt || !value.src[0] || !value.title[0] ||
        !value.message[0] || !value.button[0] || !value.action)
        return luaL_error(L, "songInterruption requires song, at, src, title, message, button and action");
    for (int i = 0; i < page->songInterruptionCount; ++i) {
        const PMOSSongInterruption *other = &page->songInterruptions[i];
        if (other->song == value.song && !strcmp(other->difficulty, value.difficulty))
            return luaL_error(L, "duplicate songInterruption song+difficulty");
    }
    page->songInterruptions[page->songInterruptionCount++] = value;
    return 0;
}
