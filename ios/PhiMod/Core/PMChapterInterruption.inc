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
    value.delay = 2; value.audioVolume = 1;
    int hasAt = 0, hasBlue = 0, hasAudioConfig = 0, audioDelayMask = 0;
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
        } else if (!strcmp(field, "effectDuration") || !strcmp(field, "blackDuration") || !strcmp(field, "blueDuration")) {
            double seconds=interruptionSeconds(L,field);
            if(seconds>600)return luaL_error(L,"songInterruption stage duration must be in [0,600]");
            value.staged=1;
            if(!strcmp(field,"effectDuration"))value.effectDuration=seconds;
            else if(!strcmp(field,"blackDuration"))value.blackDuration=seconds;
            else {value.blueDuration=seconds;hasBlue=1;}
        } else if (!strcmp(field,"audioTail")) {
            if(!lua_isboolean(L,-1))return luaL_error(L,"songInterruption audioTail expects boolean");
            value.audioTail=lua_toboolean(L,-1);hasAudioConfig=1;
        } else if (!strcmp(field,"effectAudioDelay") || !strcmp(field,"blackAudioDelay") || !strcmp(field,"blueAudioDelay")) {
            double seconds=interruptionSeconds(L,field);hasAudioConfig=1;
            if(seconds>600)return luaL_error(L,"songInterruption audio delay must be in [0,600]");
            if(!strcmp(field,"effectAudioDelay")){value.effectAudioDelay=seconds;audioDelayMask|=1;}
            else if(!strcmp(field,"blackAudioDelay")){value.blackAudioDelay=seconds;audioDelayMask|=2;}
            else {value.blueAudioDelay=seconds;audioDelayMask|=4;}
        } else if (!strcmp(field,"audioVolume")) {
            hasAudioConfig=1;
            value.audioVolume=interruptionSeconds(L,field);
            if(value.audioVolume>1)return luaL_error(L,"songInterruption audioVolume must be in [0,1]");
        } else if (!strcmp(field,"effectAudioSrc") || !strcmp(field,"blackAudioSrc") || !strcmp(field,"blueAudioSrc")) {
            hasAudioConfig=1;
            char *dst=!strcmp(field,"effectAudioSrc")?value.effectAudioSrc:
                      !strcmp(field,"blackAudioSrc")?value.blackAudioSrc:value.blueAudioSrc;
            interruptionText(L,-1,field,dst,256,0);
            if(!audioLocalName(dst))return luaL_error(L,"songInterruption audio expects a local audio basename");
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
    if(!hasBlue)value.blueDuration=value.delay;
    if(hasAudioConfig && !value.staged)return luaL_error(L,"songInterruption audio requires an enabled positive-duration stage");
    if(((audioDelayMask&1) && !value.effectAudioSrc[0]) || ((audioDelayMask&2) && !value.blackAudioSrc[0]) || ((audioDelayMask&4) && !value.blueAudioSrc[0]))
        return luaL_error(L,"songInterruption audio delay requires its source");
    if((value.effectAudioSrc[0] && value.effectAudioDelay>=value.effectDuration) ||
       (value.blackAudioSrc[0] && value.blackAudioDelay>=value.blackDuration) ||
       (value.blueAudioSrc[0] && value.blueAudioDelay>=value.blueDuration))
        return luaL_error(L,"songInterruption audio requires an enabled positive-duration stage with delay before its end");

    if((value.effectAudioSrc[0] && (!value.staged || value.effectDuration<=0)) ||
       (value.blackAudioSrc[0] && (!value.staged || value.blackDuration<=0)) ||
       (value.blueAudioSrc[0] && (!value.staged || value.blueDuration<=0)))
        return luaL_error(L,"songInterruption audio requires an enabled positive-duration stage");
    for (int i = 0; i < page->songInterruptionCount; ++i) {
        const PMOSSongInterruption *other = &page->songInterruptions[i];
        if (other->song == value.song && !strcmp(other->difficulty, value.difficulty))
            return luaL_error(L, "duplicate songInterruption song+difficulty");
    }
    page->songInterruptions[page->songInterruptionCount++] = value;
    return 0;
}
