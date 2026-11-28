/* Included after entryLocalName and UTF-8 helpers. No host side effects. */
static int audioLocalName(const char *src) {
    if (!entryLocalName(src)) return 0;
    const char *ext = strrchr(src, '.');
    if (!ext) return 0;
    return !strcmp(ext,".m4a") || !strcmp(ext,".wav") || !strcmp(ext,".mp3") ||
           !strcmp(ext,".aac") || !strcmp(ext,".caf") || !strcmp(ext,".aiff");
}
static int declareAudio(lua_State *L) {
    PMOSPage *p = declarationPage(L);
    if (lua_gettop(L)!=1 || !lua_istable(L,1)) return luaL_error(L,"audio expects one table");
    if (p->screens<=0) return luaL_error(L,"audio requires a declared screen");
    if (p->audioCueCount>=PMOSMaxAudioCues) return luaL_error(L,"too many audio cues (maximum 64)");
    PMOSAudioCue cue={0};cue.screen=p->screens-1;cue.volume=1;cue.channel=PMOSAudioEffect;
    lua_pushnil(L);
    while(lua_next(L,1)) {
        char key[32];enterSceneText(L,-2,"audio field",key,sizeof(key));
        if(!strcmp(key,"src") || !strcmp(key,"introSrc")) {
            char *dst=!strcmp(key,"src")?cue.src:cue.introSrc;
            enterSceneText(L,-1,"audio src",dst,256);
            if(!audioLocalName(dst)) return luaL_error(L,"audio src requires a local m4a/wav/mp3/aac/caf/aiff basename");
        } else if(!strcmp(key,"target")) enterSceneText(L,-1,"audio target",cue.target,sizeof(cue.target));
        else if(!strcmp(key,"event")) {
            char value[16];enterSceneText(L,-1,"audio event",value,sizeof(value));
            if(!strcmp(value,"page"))cue.event=PMOSAudioPage;
            else if(!strcmp(value,"tap"))cue.event=PMOSAudioTap;
            else return luaL_error(L,"audio event must be page or tap");
        } else if(!strcmp(key,"channel")) {
            char value[16];enterSceneText(L,-1,"audio channel",value,sizeof(value));
            if(!strcmp(value,"bgm"))cue.channel=PMOSAudioBGM;
            else if(!strcmp(value,"effect"))cue.channel=PMOSAudioEffect;
            else return luaL_error(L,"audio channel must be bgm or effect");
        } else if(!strcmp(key,"loop")) {
            if(!lua_isboolean(L,-1))return luaL_error(L,"audio loop expects boolean");
            cue.loop=lua_toboolean(L,-1);
        } else if(!strcmp(key,"start") || !strcmp(key,"duration") || !strcmp(key,"volume")) {
            if(lua_type(L,-1)!=LUA_TNUMBER)return luaL_error(L,"audio timing/volume expects number");
            double value=lua_tonumber(L,-1);
            double limit=!strcmp(key,"volume")?1:86400;
            if(!isfinite(value)||value<0||value>limit)return luaL_error(L,"invalid audio timing/volume");
            if(!strcmp(key,"start"))cue.start=value;
            else if(!strcmp(key,"duration"))cue.duration=value;else cue.volume=value;
        } else return luaL_error(L,"unknown audio field: %s",key);
        lua_pop(L,1);
    }
    if(!cue.src[0])return luaL_error(L,"audio requires src");
    if(cue.introSrc[0] && (!cue.loop || cue.event!=PMOSAudioPage))return luaL_error(L,"audio introSrc requires a looping page cue");
    if(cue.event==PMOSAudioPage && cue.target[0])return luaL_error(L,"audio target is only valid for tap");
    if(cue.event==PMOSAudioTap && (cue.start!=0 || cue.loop))return luaL_error(L,"tap audio cannot delay or loop");
    for(int i=0;i<p->audioCueCount;++i) {
        const PMOSAudioCue *other=&p->audioCues[i];
        if(other->screen==cue.screen && other->event==cue.event && other->channel==cue.channel &&
           ((cue.event==PMOSAudioPage && other->start==cue.start) ||
            (cue.event==PMOSAudioTap && !strcmp(other->target,cue.target))))
            return luaL_error(L,"duplicate audio cue for screen/event/channel");
    }
    p->audioCues[p->audioCueCount++]=cue;return 0;
}
static void resolveAudio(lua_State *L, PMOSPage *p) {
    for(int i=0;i<p->audioCueCount;++i) {
        const PMOSAudioCue *cue=&p->audioCues[i];
        if(cue->screen==p->entryTransition.screen)return (void)luaL_error(L,"audio cannot target a reserved entry-transition screen");
        if(!cue->target[0])continue;
        int found=0;
        for(int j=0;j<p->nodes;++j)
            if(p->elements[j].screen==cue->screen && !strcmp(p->elements[j].id,cue->target)){found=1;break;}
        if(!found)return (void)luaL_error(L,"audio target does not exist on this screen: %s",cue->target);
    }
}
