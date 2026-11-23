int PMOSSongVisible(const PMOSSession *s, int song) {
    if (!s || song < 1 || song > s->songs) return 0;
    unsigned index = (unsigned)(song - 1);
    return !s->hiddenSongs || !(s->hiddenSongs[index / 8] & (1u << (index % 8)));
}

static int declareSongVisible(lua_State *L) {
    declarationPage(L);
    PMOSSession *s = session(L);
    if (lua_gettop(L) != 2) return luaL_error(L, "songVisible expects a song and a boolean");
    luaL_checktype(L, 1, LUA_TNUMBER);
    lua_Integer song = luaL_checkinteger(L, 1);
    if (song < 1 || song > s->songs) return luaL_error(L, "invalid song number in songVisible");
    luaL_checktype(L, 2, LUA_TBOOLEAN);
    int visible = lua_toboolean(L, 2);
    if (!s->hiddenSongs) {
        if (visible) return 0;
        size_t bytes = ((size_t)s->songs + 7) / 8;
        s->hiddenSongs = lua_newuserdatauv(L, bytes, 0);
        memset(s->hiddenSongs, 0, bytes);
        luaL_ref(L, LUA_REGISTRYINDEX); // Keep the bitmap in the VM's allocation budget until stop.
    }
    unsigned index = (unsigned)(song - 1), mask = 1u << (index % 8);
    if (visible) s->hiddenSongs[index / 8] &= ~mask;
    else s->hiddenSongs[index / 8] |= mask;
    return 0;
}

static void resolveSongVisibility(PMOSSession *s, PMOSPage *page) {
    for (int i = 0; i < page->challengeCount; ++i) {
        PMOSChallenge *c = &page->challenges[i];
        c->songSuppressed = !PMOSSongVisible(s, c->song);
        if (c->state == PMOSChallengeClear && c->replayCount) {
            int count = 0;
            for (int j = 0; j < c->replayCount; ++j)
                if (PMOSSongVisible(s, c->replaySongs[j].song)) c->replaySongs[count++] = c->replaySongs[j];
            c->replayCount = count;
            if (!count) c->songSuppressed = 1;
        } else {
            // The story sequence starts each required leg automatically.
            for (int j = 0; j < c->nextSongCount; ++j)
                if (!PMOSSongVisible(s, c->nextSongs[j].song)) c->songSuppressed = 1;
        }
        for (int j = 0; j < c->courseCount; ++j)
            if (!PMOSSongVisible(s, c->course[j].song)) c->songSuppressed = 1;
    }
    for (int i = 0; i < page->count; ++i) {
        PMOSCard *card = &page->cards[i];
        card->songSuppressed = !PMOSSongVisible(s, card->song) ||
                               (card->challenge && page->challenges[card->challenge - 1].songSuppressed);
    }
    for (int i = 0; i < page->nodes; ++i) {
        PMOSNode *n = &page->elements[i];
        n->songSuppressed = (n->open && !PMOSSongVisible(s, n->open)) ||
                            (n->cover && !PMOSSongVisible(s, n->cover)) ||
                            (n->challenge && page->challenges[n->challenge - 1].songSuppressed) ||
                            (n->parent >= 0 && page->elements[n->parent].songSuppressed);
    }
}
