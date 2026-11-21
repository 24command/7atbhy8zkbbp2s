/* One LIFE ladder per author chapter. The native result writer includes this file
   without PM_CHAPTER_LIFE_LUA; no Lua, game runtime, or file I/O is needed. */
#ifndef PM_CHAPTER_LIFE_RULES
#define PM_CHAPTER_LIFE_RULES
#define PMChapterLifeCeilingKey "life.ceiling"
#define PMChapterLifeChoiceKey  "life.choice"
enum { PMChapterLifeInitial = 1, PMChapterLifeMax = 4 };
typedef struct { int ceiling, selected; } PMChapterLifeState;

/* Missing keys read as zero. Ceiling is a raw index; choice is index + 1,
   so choosing tier zero survives a reload and is distinct from no choice. */
static inline PMChapterLifeState PMChapterLifeRead(int ceiling, int choice) {
    PMChapterLifeState s;
    s.ceiling = ceiling < PMChapterLifeInitial ? PMChapterLifeInitial :
                ceiling > PMChapterLifeMax ? PMChapterLifeMax : ceiling;
    s.selected = choice <= 0 || choice > s.ceiling + 1 ? s.ceiling : choice - 1;
    return s;
}

/* Call exactly once per natural authored course result, using the tier captured
   at launch, not the current UI selection. Zero means no LIFE keys to write;
   the caller can still record the ordinary door clear/failure in that batch. */
static inline int PMChapterLifeApplyOutcome(PMChapterLifeState *s, int runTier, int cleared) {
    if (runTier < 0 || runTier > PMChapterLifeMax) return 0;
    if (cleared) {
        int ceiling = runTier > PMChapterLifeInitial ? runTier - 1 : PMChapterLifeInitial;
        if (ceiling == s->ceiling) return 0;
        s->ceiling = ceiling;
        if (s->selected > ceiling) s->selected = ceiling;
    } else {
        if (runTier != s->ceiling || runTier == PMChapterLifeMax) return 0;
        s->selected = ++s->ceiling;
    }
    return 1;
}
#endif

#ifdef PM_CHAPTER_LIFE_LUA
/* chapterLife() is a pure read; chapterLife(index) stages a player choice in
   the current VM transaction. Example: lifeTier = chapterLife().selected. */
static int chapterLife(lua_State *L) {
    static const int hp[] = {1, 10, 50, 100, 200};
    int argc = lua_gettop(L);
    if (argc > 1 || (argc == 1 && !lua_isinteger(L, 1)))
        return luaL_error(L, "chapterLife expects zero arguments or one integer tier");
    PMOSSession *vm = session(L);
    int ceiling = readProgress(L, vm, PMChapterLifeCeilingKey);
    int choice = readProgress(L, vm, PMChapterLifeChoiceKey);
    PMChapterLifeState s = PMChapterLifeRead(ceiling, choice);
    if (argc) {
        lua_Integer tier = lua_tointeger(L, 1);
        if (tier < 0 || tier > s.ceiling) return luaL_error(L, "LIFE tier is outside the unlocked range");
        s.selected = (int)tier;
        if (choice != s.selected + 1) {
            lua_settop(L, 0);
            lua_pushliteral(L, PMChapterLifeChoiceKey);
            lua_pushinteger(L, s.selected + 1);
            progressSet(L); /* Same quota, read-your-writes and rollback as progress.set. */
        }
    }
    lua_createtable(L, 0, 3);
    lua_pushinteger(L, s.selected); lua_setfield(L, -2, "selected");
    lua_pushinteger(L, s.ceiling); lua_setfield(L, -2, "ceiling");
    lua_pushinteger(L, hp[s.selected]); lua_setfield(L, -2, "hp");
    return 1;
}
#endif
