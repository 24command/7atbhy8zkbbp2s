/* Decode inside the click transaction. A reveal always resolves on the source
   screen, including forward references and IDs reused on other screens. */
static void revealText(lua_State *L, char *out, size_t capacity) {
    word(L, -1, out, capacity);
    /* UIKit needs UTF-8. Reject truncated, overlong and surrogate encodings. */
    const unsigned char *p = (const unsigned char *)out;
    while (*p) {
        unsigned c = *p++;
        if (c < 0x80) continue;
        if (c < 0xc2 || c > 0xf4 || (c == 0xe0 && *p < 0xa0) ||
            (c == 0xed && *p >= 0xa0) || (c == 0xf0 && *p < 0x90) ||
            (c == 0xf4 && *p >= 0x90)) luaL_error(L, "invalid UTF-8 in reveal");
        for (int n = c < 0xe0 ? 1 : c < 0xf0 ? 2 : 3; n; --n) {
            if ((*p++ & 0xc0) != 0x80) luaL_error(L, "invalid UTF-8 in reveal");
        }
    }
}

static void parseReveal(lua_State *L, const PMOSSession *s, int screen, PMOSAction *action) {
    char id[sizeof(s->clicks[0].id)] = {0};
    luaL_checktype(L, -1, LUA_TTABLE);
    lua_pushnil(L);
    while (lua_next(L, -2)) {
        char key[sizeof("target")];
        word(L, -2, key, sizeof(key));
        if (!strcmp(key, "target")) word(L, -1, id, sizeof(id));
        else if (!strcmp(key, "title")) revealText(L, action->revealTitle, sizeof(action->revealTitle));
        else if (!strcmp(key, "text")) revealText(L, action->revealText, sizeof(action->revealText));
        else if (!strcmp(key, "song")) action->song = actionSong(L, s, "reveal");
        else luaL_error(L, "unknown reveal field: %s", key);
        lua_pop(L, 1);
    }
    if (!id[0] || !action->revealTitle[0] || !action->revealText[0])
        luaL_error(L, "reveal requires target, title and text");
    for (int i = 0; i < s->nodes; ++i) {
        if (s->clicks[i].screen == screen && !strcmp(s->clicks[i].id, id)) {
            action->element = i;
            return;
        }
    }
    luaL_error(L, "unknown reveal target on clicked screen: %s", id);
}
