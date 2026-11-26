/* Included after layout scalar readers. All data is declaration-only; action
   callbacks cannot reach this parser because layoutNode checks declarationPage. */
static const char *const trackPropertyNames[PMOSTrackPropertyCount] = {
    "x", "y", "w", "h", "rotation", "scaleX", "scaleY", "opacity", "red", "green", "blue"
};
static int trackProperty(lua_State *L, int index) {
    char name[32];
    word(L, index, name, sizeof(name));
    for (int i = 0; i < PMOSTrackPropertyCount; ++i)
        if (!strcmp(name, trackPropertyNames[i])) return i;
    return luaL_error(L, "unknown track property: %s", name);
}
static int validTrackValue(int property, double value) {
    double low = 0, high = 1;
    switch (property) {
        case PMOSTrackX: case PMOSTrackY: low = -8; high = 8; break;
        case PMOSTrackW: case PMOSTrackH: high = 8; break;
        case PMOSTrackRotation: low = -1e6; high = 1e6; break;
        case PMOSTrackScaleX: case PMOSTrackScaleY: low = -16; high = 16; break;
        default: break;
    }
    return isfinite(value) && value >= low && value <= high;
}
static double trackNumber(lua_State *L, int table, const char *field, int required, int *present) {
    lua_getfield(L, table, field);
    int exists = !lua_isnil(L, -1);
    double value = 0;
    if (exists || required) {
        luaL_checktype(L, -1, LUA_TNUMBER);
        value = lua_tonumber(L, -1);
        if (!isfinite(value)) luaL_error(L, "track %s must be finite", field);
    }
    lua_pop(L, 1);
    if (present) *present = exists;
    return value;
}
static PMOSTrackKey readTrackKey(lua_State *L, int property, int *hasIn, int *hasOut) {
    luaL_checktype(L, -1, LUA_TTABLE);
    int table = lua_gettop(L);
    lua_pushnil(L);
    while (lua_next(L, table)) {
        char name[32];
        word(L, -2, name, sizeof(name));
        if (strcmp(name, "time") && strcmp(name, "value") && strcmp(name, "inTangent") &&
            strcmp(name, "outTangent") && strcmp(name, "ease"))
            luaL_error(L, "unknown track key field: %s", name);
        lua_pop(L, 1);
    }
    PMOSTrackKey key = {0};
    key.time = trackNumber(L, table, "time", 1, NULL);
    key.value = trackNumber(L, table, "value", 1, NULL);
    key.inTangent = trackNumber(L, table, "inTangent", 0, hasIn);
    key.outTangent = trackNumber(L, table, "outTangent", 0, hasOut);
    if (key.time < 0) luaL_error(L, "track time must be nonnegative");
    if (!validTrackValue(property, key.value))
        luaL_error(L, "invalid track value in %s", trackPropertyNames[property]);
    lua_getfield(L, table, "ease");
    if (!lua_isnil(L, -1)) {
        char ease[16];
        word(L, -1, ease, sizeof(ease));
        if (!strcmp(ease, "linear")) key.ease = PMOSTrackLinear;
        else if (!strcmp(ease, "step")) key.ease = PMOSTrackStep;
        else if (!strcmp(ease, "cubic")) key.ease = PMOSTrackCubic;
        else luaL_error(L, "unknown track ease: %s", ease);
    }
    lua_pop(L, 1);
    return key;
}
static void readTrack(lua_State *L, PMOSPage *page, PMOSTrack *track, int property) {
    luaL_checktype(L, -1, LUA_TTABLE);
    int table = lua_gettop(L);
    size_t count = lua_rawlen(L, table), entries = 0;
    if (!count || count > PMOSMaxTrackKeys) luaL_error(L, "track requires 1..8192 keys");
    if (count > (size_t)(PMOSMaxPageTrackKeys - page->trackKeyCount))
        luaL_error(L, "page track key budget exceeds 32768");
    lua_pushnil(L);
    while (lua_next(L, table)) {
        if (!lua_isinteger(L, -2) || lua_tointeger(L, -2) < 1 ||
            (lua_Unsigned)lua_tointeger(L, -2) > count)
            luaL_error(L, "track keys must be a dense array");
        ++entries;
        lua_pop(L, 1);
    }
    if (entries != count) luaL_error(L, "track keys must be a dense array");
    track->offset = page->trackKeyCount;
    track->count = (int)count;
    int previousOut = 0;
    for (int i = 0; i < track->count; ++i) {
        lua_rawgeti(L, table, i + 1);
        int hasIn = 0, hasOut = 0;
        PMOSTrackKey key = readTrackKey(L, property, &hasIn, &hasOut);
        lua_pop(L, 1);
        if (i) {
            const PMOSTrackKey *previous = &page->trackKeys[page->trackKeyCount - 1];
            if (key.time <= previous->time) luaL_error(L, "track times must be strictly increasing");
            if (previous->ease == PMOSTrackCubic) {
                if (!previousOut || !hasIn)
                    luaL_error(L, "cubic segment requires outTangent and next inTangent");
                double dt = key.time - previous->time;
                if (!isfinite(dt * previous->outTangent) || !isfinite(dt * key.inTangent))
                    luaL_error(L, "cubic tangent span is too large");
            }
        }
        if (i + 1 == track->count && key.ease == PMOSTrackCubic)
            luaL_error(L, "cubic key requires a following key");
        page->trackKeys[page->trackKeyCount++] = key;
        previousOut = hasOut;
    }
}
static void readNumericTracks(lua_State *L, PMOSPage *page, PMOSNode *node) {
    node->rotation = motionField(L, "rotation", 0, -1e6, 1e6);
    node->scaleX = motionField(L, "scaleX", 1, -16, 16);
    node->scaleY = motionField(L, "scaleY", 1, -16, 16);
    node->opacity = motionField(L, "opacity", 1, 0, 1);
    /* Parsed nodes have explicit defaults. Aggregate-zero legacy/sheet nodes
       have no flags, so the shared sampler supplies unit scale/opacity. */
    node->numericFlags = PMOSHasScaleX | PMOSHasScaleY | PMOSHasOpacity;
    node->trackLoop = secondsField(L, "trackLoop");
    lua_getfield(L, 1, "trackLoop");
    if (!lua_isnil(L, -1) && node->trackLoop <= 0) luaL_error(L, "trackLoop must be positive");
    lua_pop(L, 1);
    lua_getfield(L, 1, "tracks");
    if (!lua_isnil(L, -1)) {
        luaL_checktype(L, -1, LUA_TTABLE);
        int table = lua_gettop(L);
        lua_pushnil(L);
        while (lua_next(L, table)) {
            int property = trackProperty(L, -2);
            readTrack(L, page, &node->tracks[property], property);
            lua_pop(L, 1);
        }
    }
    lua_pop(L, 1);
}
