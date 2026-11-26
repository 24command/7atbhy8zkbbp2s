/* Included after layout/presentation and entry-transition helpers. This is a
   declaration-only plan for the existing native map renderer, not an overlay. */
static void enterSceneText(lua_State *L, int index, const char *field,
                           char *out, size_t cap) {
    if (lua_type(L, index) != LUA_TSTRING)
        luaL_error(L, "onEnterScene %s must be a string", field);
    size_t n;
    const char *text = lua_tolstring(L, index, &n);
    if (!n || n >= cap || memchr(text, 0, n))
        luaL_error(L, "onEnterScene %s is empty, oversized or contains NUL", field);
    if (!presentationUTF8((const unsigned char *)text))
        luaL_error(L, "onEnterScene %s must be valid UTF-8", field);
    memcpy(out, text, n + 1);
}

static int declareEnterScene(lua_State *L) {
    PMOSPage *page = declarationPage(L);
    if (page->enterScene.declared)
        return luaL_error(L, "only one onEnterScene per declaration");
    if (lua_gettop(L) != 1 || !lua_istable(L, 1))
        return luaL_error(L, "onEnterScene expects one table");
    PMOSEnterScene value = {0};
    value.declared = 1;
    value.sourceScreen = value.toScreen = value.initialScreen = -1;
    lua_pushnil(L);
    while (lua_next(L, 1)) {
        char field[32];
        enterSceneText(L, -2, "field name", field, sizeof(field));
        if (!strcmp(field, "key")) {
            char key[PMOSEnterSceneKeyMax + 1];
            enterSceneText(L, -1, field, key, sizeof(key));
            validateKeyChars(L, key, strlen(key));
            strcpy(value.key, "scene.");
            strcat(value.key, key);
        } else if (!strcmp(field, "screen")) {
            enterSceneText(L, -1, field, value.sourceScreenName, sizeof(value.sourceScreenName));
        } else if (!strcmp(field, "to")) {
            enterSceneText(L, -1, field, value.toName, sizeof(value.toName));
        } else if (!strcmp(field, "duration")) {
            if (lua_type(L, -1) != LUA_TNUMBER)
                return luaL_error(L, "onEnterScene duration must be a number");
            value.duration = lua_tonumber(L, -1);
            if (!isfinite(value.duration) || value.duration <= 0 || value.duration > PMOSEnterSceneMaxSeconds)
                return luaL_error(L, "onEnterScene duration must be finite and in (0,600]");
        } else return luaL_error(L, "unknown onEnterScene field: %s", field);
        lua_pop(L, 1);
    }
    if (!value.key[0] || !value.sourceScreenName[0] || !value.toName[0] || !value.duration)
        return luaL_error(L, "onEnterScene requires key, screen, to and duration");
    page->enterScene = value;
    return 0;
}

/* Resolve after entryTransition: names may be forward references, and neither
   endpoint may use that transition's reserved timeline screen. */
static void resolveEnterScene(lua_State *L, PMOSPage *page) {
    PMOSEnterScene *scene = &page->enterScene;
    if (!scene->declared) return;
    scene->sourceScreen = findScreen(page->names, page->screens, scene->sourceScreenName);
    scene->toScreen = findScreen(page->names, page->screens, scene->toName);
    if (scene->sourceScreen < 0) luaL_error(L, "unknown onEnterScene screen: %s", scene->sourceScreenName);
    if (scene->toScreen < 0) luaL_error(L, "unknown onEnterScene to: %s", scene->toName);
    if (scene->sourceScreen == scene->toScreen)
        luaL_error(L, "onEnterScene screen and to must be distinct");
    if (scene->sourceScreen == page->entryTransition.screen || scene->toScreen == page->entryTransition.screen)
        luaL_error(L, "onEnterScene cannot use the reserved entryTransition screen");
    scene->seen = readProgress(L, session(L), scene->key) != 0;
    if (!scene->seen && page->entryMovieKey[0] && !page->entryMovieSeen)
        luaL_error(L, "unseen onEnterScene and onEnterMovie cannot both be active");
    scene->initialScreen = scene->seen ? scene->toScreen : scene->sourceScreen;
}
