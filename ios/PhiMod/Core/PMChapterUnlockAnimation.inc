/* The key is shared with the presenter and is also the session lookup key. */
static void unlockKey(lua_State *L, const char *id, char key[PMOSProgressKeyMax + 1]) {
    validateKeyChars(L, id, strlen(id)); /* word() already enforced PMOSUnlockIdMax. */
    strcpy(key, "unlock.");
    strcat(key, id);
}

static PMOSUnlockStyle unlockStyle(lua_State *L) {
    static const char *const names[] = {"mod", "c5", "c6", "c7", "c8", "c9"};
    char name[sizeof("mod")];
    word(L, -1, name, sizeof(name));
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); ++i)
        if (!strcmp(name, names[i])) return (PMOSUnlockStyle)i;
    return (PMOSUnlockStyle)luaL_error(L, "invalid unlockAnimation style");
}

static double unlockSeconds(lua_State *L, const char *field) {
    luaL_checktype(L, -1, LUA_TNUMBER);
    double seconds = lua_tonumber(L, -1);
    if (!(seconds >= 0 && seconds <= 86400)) luaL_error(L, "invalid unlockAnimation %s", field);
    return seconds;
}

static int declareUnlockAnimation(lua_State *L) {
    PMOSPage *page = declarationPage(L);
    if (lua_gettop(L) != 1) return luaL_error(L, "unlockAnimation expects one table");
    luaL_checktype(L, 1, LUA_TTABLE);
    if (page->unlockAnimationCount >= PMOSMaxUnlockAnimations)
        return luaL_error(L, "too many unlock animations");
    PMOSUnlockAnimation *scene = &page->unlockAnimations[page->unlockAnimationCount];
    scene->once = 1;
    scene->infoAt = scene->infoUntil = -1;
    int hasStyle = 0;
    lua_pushnil(L);
    while (lua_next(L, 1)) {
        char key[sizeof("infoUntil")];
        word(L, -2, key, sizeof(key));
        if (!strcmp(key, "id")) {
            word(L, -1, scene->id, sizeof(scene->id));
            unlockKey(L, scene->id, scene->progressKey);
        } else if (!strcmp(key, "song")) {
            scene->song = actionSong(L, session(L), "unlockAnimation");
        } else if (!strcmp(key, "style")) {
            scene->style = unlockStyle(L);
            hasStyle = 1;
        } else if (!strcmp(key, "src")) {
            challengeIntroName(L, scene->src, sizeof(scene->src));
            if (!PMStockIntroForName(scene->src)) {
                const char *ext = strrchr(scene->src, '.');
                if (!ext || (ext[1] != 'm' && ext[1] != 'M') ||
                    (ext[2] != 'p' && ext[2] != 'P') || strcmp(ext + 3, "4"))
                    return luaL_error(L, "unlockAnimation src expects an MP4 or stock clip");
            }
        } else if (!strcmp(key, "when")) {
            char when[sizeof("enter")];
            word(L, -1, when, sizeof(when));
            if (!strcmp(when, "event")) scene->when = PMOSUnlockEvent;
            else if (strcmp(when, "enter")) return luaL_error(L, "unlockAnimation when expects enter or event");
        } else if (!strcmp(key, "once")) {
            luaL_checktype(L, -1, LUA_TBOOLEAN);
            scene->once = lua_toboolean(L, -1);
        } else if (!strcmp(key, "after")) scene->after = unlockSeconds(L, key);
        else if (!strcmp(key, "infoAt")) {
            scene->infoAt = unlockSeconds(L, key);
            scene->hasInfoAt = 1;
        } else if (!strcmp(key, "infoUntil")) {
            scene->infoUntil = unlockSeconds(L, key);
            scene->hasInfoUntil = 1;
        } else if (!strcmp(key, "duration")) {
            scene->duration = unlockSeconds(L, key);
            if (!scene->duration) return luaL_error(L, "unlockAnimation duration must be positive");
        } else return luaL_error(L, "unknown unlockAnimation field: %s", key);
        lua_pop(L, 1);
    }
    if (!scene->id[0] || !scene->song || !hasStyle) return luaL_error(L, "unlockAnimation requires id, song and style");
    if (scene->style == PMOSUnlockMod && !scene->src[0]) return luaL_error(L, "mod unlockAnimation requires src");
    if ((scene->hasInfoAt && scene->hasInfoUntil && scene->infoAt >= scene->infoUntil) ||
        (scene->duration && (scene->infoAt >= scene->duration || scene->infoUntil > scene->duration)))
        return luaL_error(L, "invalid unlockAnimation info window");
    for (int i = 0; i < page->unlockAnimationCount; ++i)
        if (!strcmp(page->unlockAnimations[i].id, scene->id)) return luaL_error(L, "duplicate unlockAnimation id: %s", scene->id);
    ++page->unlockAnimationCount;
    return 0;
}

/* Resolve after the entire script so even later staged writes affect entry. Keep
   only the information needed for clicks, as the caller may release the page. */
static void resolveUnlockAnimations(lua_State *L, PMOSSession *s, PMOSPage *page) {
    s->unlockAnimationCount = page->unlockAnimationCount;
    for (int i = 0; i < page->unlockAnimationCount; ++i) {
        PMOSUnlockAnimation *scene = &page->unlockAnimations[i];
        scene->seen = scene->once && readProgress(L, s, scene->progressKey) != 0;
        UnlockBinding *binding = &s->unlockBindings[i];
        strcpy(binding->progressKey, scene->progressKey);
        binding->when = scene->when;
        binding->once = scene->once;
    }
}

static int unlockAnimationAction(lua_State *L, PMOSSession *s) {
    char id[PMOSUnlockIdMax + 1], key[PMOSProgressKeyMax + 1];
    word(L, -1, id, sizeof(id));
    unlockKey(L, id, key);
    for (int i = 0; i < s->unlockAnimationCount; ++i) {
        const UnlockBinding *binding = &s->unlockBindings[i];
        if (strcmp(key, binding->progressKey)) continue;
        if (binding->when != PMOSUnlockEvent) return luaL_error(L, "unlockAnimation action requires an event scene");
        if (binding->once && readProgress(L, s, key)) return 0;
        return i + 1;
    }
    return luaL_error(L, "unknown unlockAnimation id: %s", id);
}
