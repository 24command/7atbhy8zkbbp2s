/* Included after layout/presentation helpers. No host or filesystem access. */
static double entrySeconds(lua_State *L, const char *field) {
    if (lua_type(L, -1) != LUA_TNUMBER)
        luaL_error(L, "entryTransition %s must be a number", field);
    double value = lua_tonumber(L, -1);
    if (!isfinite(value) || value < 0)
        luaL_error(L, "entryTransition %s must be finite nonnegative seconds", field);
    if (value > PMOSEntryTransitionMaxSeconds)
        luaL_error(L, "entryTransition %s exceeds the %d-second transition limit", field, PMOSEntryTransitionMaxSeconds);
    return value;
}

static void entryText(lua_State *L, int index, const char *field, char *out, size_t cap) {
    if (lua_type(L, index) != LUA_TSTRING)
        luaL_error(L, "entryTransition %s must be a string", field);
    size_t n; const char *text = lua_tolstring(L, index, &n);
    if (!n || n >= cap || memchr(text, 0, n))
        luaL_error(L, "entryTransition %s is empty, oversized or contains NUL", field);
    memcpy(out, text, n + 1);
}

static int entryLocalName(const char *name) {
    if (!name[0] || name[0] == '.' || strpbrk(name, "/\\:") ||
        !presentationUTF8((const unsigned char *)name)) return 0;
    for (const unsigned char *p = (const unsigned char *)name; *p; ++p)
        if (*p < 32 || *p == 127 || (*p == 0xc2 && p[1] < 0xa0)) return 0;
    return 1;
}

static int entryVideoName(const char *name) {
    if (!entryLocalName(name)) return 0;
    const char *dot = strrchr(name, '.');
    if (!dot || strlen(dot) != 4) return 0;
    char suffix[5];
    for (int i = 0; i < 5; ++i) suffix[i] = (char)tolower((unsigned char)dot[i]);
    return !strcmp(suffix, ".mp4") || !strcmp(suffix, ".mov");
}

static int declareEntryTransition(lua_State *L) {
    PMOSPage *page = declarationPage(L);
    if (page->entryTransition.declared)
        return luaL_error(L, "only one entryTransition per declaration");
    if (lua_gettop(L) != 1 || !lua_istable(L, 1))
        return luaL_error(L, "entryTransition expects one table");
    PMOSEntryTransition value = {0};
    value.declared = 1;
    value.screen = -1;
    int hasKind = 0, hasLoad = 0, hasReveal = 0;
    lua_pushnil(L);
    while (lua_next(L, 1)) {
        char field[32];
        entryText(L, -2, "field name", field, sizeof(field));
        if (!strcmp(field, "kind")) {
            char kind[16]; entryText(L, -1, "kind", kind, sizeof(kind));
            if (!strcmp(kind, "native")) value.kind = PMOSEntryTransitionNative;
            else if (!strcmp(kind, "video")) value.kind = PMOSEntryTransitionVideo;
            else if (!strcmp(kind, "timeline")) value.kind = PMOSEntryTransitionTimeline;
            else return luaL_error(L, "entryTransition kind must be native, video or timeline");
            hasKind = 1;
        } else if (!strcmp(field, "load")) {
            char load[16]; entryText(L, -1, "load", load, sizeof(load));
            if (!strcmp(load, "covered")) value.load = PMOSEntryLoadCovered;
            else if (!strcmp(load, "end")) value.load = PMOSEntryLoadEnd;
            else if (!strcmp(load, "time")) value.load = PMOSEntryLoadTime;
            else return luaL_error(L, "entryTransition load must be covered, end or time");
            hasLoad = 1;
        } else if (!strcmp(field, "reveal")) {
            char reveal[16]; entryText(L, -1, "reveal", reveal, sizeof(reveal));
            if (!strcmp(reveal, "native")) value.reveal = PMOSEntryRevealNative;
            else if (!strcmp(reveal, "none")) value.reveal = PMOSEntryRevealNone;
            else return luaL_error(L, "entryTransition reveal must be native or none");
            hasReveal = 1;
        } else if (!strcmp(field, "src")) {
            entryText(L, -1, "src", value.src, sizeof(value.src));
        } else if (!strcmp(field, "screen")) {
            entryText(L, -1, "screen", value.screenName, sizeof(value.screenName));
            if (!presentationUTF8((const unsigned char *)value.screenName))
                return luaL_error(L, "entryTransition screen must be valid UTF-8");
        } else if (!strcmp(field, "duration")) {
            value.duration = entrySeconds(L, field); value.hasDuration = 1;
        } else if (!strcmp(field, "at")) {
            value.at = entrySeconds(L, field); value.hasAt = 1;
        } else return luaL_error(L, "unknown entryTransition field: %s", field);
        lua_pop(L, 1);
    }
    if (!hasKind) return luaL_error(L, "entryTransition requires kind");
    if (!hasLoad) value.load = value.kind == PMOSEntryTransitionNative ? PMOSEntryLoadCovered : PMOSEntryLoadEnd;
    if (value.kind == PMOSEntryTransitionNative && value.load != PMOSEntryLoadCovered)
        return luaL_error(L, "entryTransition native supports only load='covered'");
    if (value.kind == PMOSEntryTransitionNative && hasReveal)
        return luaL_error(L, "entryTransition reveal is only valid for video or timeline");
    if (value.kind == PMOSEntryTransitionVideo) {
        if (!entryVideoName(value.src))
            return luaL_error(L, "entryTransition video requires a local MP4 or MOV src basename");
    } else if (value.src[0]) return luaL_error(L, "entryTransition src is only valid for video");
    if (value.kind == PMOSEntryTransitionTimeline) {
        if (!value.screenName[0]) return luaL_error(L, "entryTransition timeline requires screen");
        if (!value.hasDuration) return luaL_error(L, "entryTransition timeline requires duration");
    } else if (value.screenName[0]) return luaL_error(L, "entryTransition screen is only valid for timeline");
    if (value.hasDuration && value.kind == PMOSEntryTransitionNative)
        return luaL_error(L, "entryTransition native uses host timing; omit duration");
    if (value.hasDuration && value.duration <= 0)
        return luaL_error(L, "entryTransition duration must be positive");
    int needsAt = value.load == PMOSEntryLoadTime ||
        (value.load == PMOSEntryLoadCovered && value.kind != PMOSEntryTransitionNative);
    if (needsAt && !value.hasAt) return luaL_error(L, "entryTransition load requires at");
    if (!needsAt && value.hasAt) return luaL_error(L, "entryTransition at conflicts with this load mode");
    if (value.hasAt && value.hasDuration && value.at > value.duration)
        return luaL_error(L, "entryTransition at exceeds duration");
    page->entryTransition = value;
    return 0;
}

static void resolveEntryTransition(lua_State *L, PMOSPage *page) {
    PMOSEntryTransition *entry = &page->entryTransition;
    if (entry->kind == PMOSEntryTransitionTimeline) {
        entry->screen = findScreen(page->names, page->screens, entry->screenName);
        if (entry->screen < 0) luaL_error(L, "unknown entryTransition screen: %s", entry->screenName);
        int count = 0;
        for (int i = 0; i < page->nodes; ++i) {
            const PMOSNode *node = &page->elements[i];
            if (node->screen != entry->screen) {
                if (node->dest == entry->screen)
                    luaL_error(L, "entryTransition screen is reserved: %s", entry->screenName);
                continue;
            }
            ++count;
            if (session(L)->entryUnsupported[i][0])
                luaL_error(L, "unsupported entryTransition timeline node field: %s (node %d)",
                           session(L)->entryUnsupported[i], i + 1);
            if (node->kind == PMOSHotspot || node->handler || node->open || node->to[0] ||
                node->challenge || node->dropTarget[0] || node->alphaHit)
                luaL_error(L, "entryTransition timeline nodes must be noninteractive (node %d)", i + 1);
            if (node->blend != PMOSBlendNormal)
                luaL_error(L, "entryTransition timeline does not support additive blend (node %d)", i + 1);
            if (node->loop || node->motion.tapTime || node->motion.tapFlash || node->tapFace[0] ||
                node->motion.tapScale != 1.06)
                luaL_error(L, "entryTransition timeline permits only still images and passive motion (node %d)", i + 1);
            if (node->kind == PMOSImage && node->src[0] &&
                (!entryLocalName(node->src) || !cueImageName(node->src)))
                luaL_error(L, "entryTransition timeline src must be a local PNG, JPG, JPEG or WebP still image (node %d)", i + 1);
        }
        if (!count) luaL_error(L, "entryTransition timeline screen requires frame or image nodes");
    }
    page->initialScreen = -1;
    for (int i = 0; i < page->screens; ++i) {
        if (i != entry->screen) { page->initialScreen = i; break; }
    }
}
