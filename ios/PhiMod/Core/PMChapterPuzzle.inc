/* os.lua: puzzle.define{id="gate.v1", mode="set", pieces={...}}.
   puzzle.status(id) -> count,total,solved; puzzle.submit(id,piece) -> result.
   puzzle.missing(id) -> fresh array of remaining tokens in declaration order.
   Reserve progress key puzzle.<id>. Positions are part of the save format:
   use a new id when changing mode, membership or order of a published puzzle.
   id: 1..57 ASCII key characters. Mode: "set" or "ordered". Pieces: 1..31
   nonempty strings, each at most 64 bytes with no embedded NUL.
   Results: advanced, solved (first finish), complete (known piece on replay),
   wrong (known but out of order), duplicate (set), invalid (missing/unknown).
   Ordered lists may repeat a token; sets may not. Definitions are copied.
   There is no implicit UI, action or reward: branch on "solved" for a one-shot
   action, or on status for presenting an already unlocked route.

   Legacy puzzle{...}, puzzleSubmit(id,piece) and puzzleSolved(id) keep G's
   per-piece keys puzzle.<id>.<piece> and boolean results. Only 1 is collected.
   Both declaration styles can coexist. A physical save key has one owner.

   Chapter 9, 4.0.4 dump signatures: Chapter9PuzzlePiece.Completed and
   Chapter9PuzzleControl.OnPieceCompleted/ConfirmNextStage separate input
   from presentation. Chapter9InputPasswordControl.Submit/PlayWrongPasswordOptics
   separate submission from feedback; ordered token input is an authoring option,
   not a claim about the original password algorithm. Chapter9Phase2Rules.
   AreKeyCollectionsComplete accepts requirements and an unlock predicate; set
   mode represents the same all-required gate, not the native collection store. */
enum { PuzzleMaxPieces = 31, PuzzleTokenBytes = 64, LegacyPuzzleLimit = 32,
       LegacyPieceLimit = 32, LegacyNameMax = (PMOSProgressKeyMax - (sizeof("puzzle..") - 1)) / 2 };
#define PUZZLE_PREFIX "puzzle."
typedef struct {
    int ordered, total;
    char key[PMOSProgressKeyMax + 1];
    char pieces[][PuzzleTokenBytes + 1];
} ChapterPuzzle;

static int puzzleToken(lua_State *L, int i) {
    if (lua_type(L, i) != LUA_TSTRING) return 0;
    size_t len;
    const char *s = lua_tolstring(L, i, &len);
    return len && len <= PuzzleTokenBytes && !memchr(s, 0, len);
}

static const char *legacyPuzzleName(lua_State *L, int index) {
    size_t len;
    luaL_checktype(L, index, LUA_TSTRING);
    const char *name = lua_tolstring(L, index, &len);
    if (!len || len > LegacyNameMax || memchr(name, '.', len))
        luaL_error(L, "invalid puzzle or piece name");
    validateKeyChars(L, name, len);
    return name;
}

static void reservePuzzleKey(lua_State *L, const char *key) {
    if (lua_getfield(L, lua_upvalueindex(2), key) != LUA_TNIL)
        luaL_error(L, "overlapping puzzle save key: %s", key);
    lua_pop(L, 1);
    lua_pushboolean(L, 1);
    lua_setfield(L, lua_upvalueindex(2), key);
}

static void legacyPieceKey(char key[PMOSProgressKeyMax + 1], const ChapterPuzzle *p, int i) {
    /* Both components were bounded by LegacyNameMax at declaration. */
    strcpy(key, p->key);
    strcat(key, ".");
    strcat(key, p->pieces[i]);
}

static int declarePuzzle(lua_State *L, int legacy) {
    declarationPage(L);
    if (lua_gettop(L) != 1) return luaL_error(L, "puzzle expects one declaration");
    luaL_checktype(L, 1, LUA_TTABLE);
    int definitions = 0;
    if (legacy) {
        lua_rawgeti(L, lua_upvalueindex(1), 0);
        definitions = (int)lua_tointeger(L, -1);
        lua_pop(L, 1);
        if (definitions >= LegacyPuzzleLimit) return luaL_error(L, "too many puzzles");
    }
    lua_getfield(L, 1, "id");
    luaL_checktype(L, -1, LUA_TSTRING);
    size_t len;
    const char *id = lua_tolstring(L, -1, &len);
    if (legacy) legacyPuzzleName(L, -1);
    else {
        if (!len || len > PMOSProgressKeyMax - (sizeof(PUZZLE_PREFIX) - 1))
            return luaL_error(L, "invalid puzzle id length");
        validateKeyChars(L, id, len);
    }
    if (lua_getfield(L, lua_upvalueindex(1), id) != LUA_TNIL)
        return luaL_error(L, "duplicate puzzle id: %s", id);
    lua_pop(L, 1);
    lua_getfield(L, 1, "mode");
    luaL_checktype(L, -1, LUA_TSTRING);
    const char *mode = lua_tolstring(L, -1, &len);
    int ordered = len == 7 && !memcmp(mode, "ordered", 7);
    if (!ordered && !(len == 3 && !memcmp(mode, "set", 3)))
        return luaL_error(L, "puzzle mode must be ordered or set");
    lua_getfield(L, 1, "pieces");
    luaL_checktype(L, -1, LUA_TTABLE);
    int pieces = lua_gettop(L);
    size_t n = lua_rawlen(L, pieces);
    int limit = legacy ? LegacyPieceLimit : PuzzleMaxPieces;
    if (!n || n > (size_t)limit) return luaL_error(L, "puzzle expects 1..%d pieces", limit);
    ChapterPuzzle *p = lua_newuserdatauv(L, sizeof(*p) + n * sizeof(p->pieces[0]), 0);
    p->ordered = ordered;
    p->total = (int)n;
    snprintf(p->key, sizeof(p->key), PUZZLE_PREFIX "%s", id);
    /* rawlen alone does not establish that this is a dense array. */
    lua_pushnil(L);
    while (lua_next(L, pieces)) {
        if (!lua_isinteger(L, -2) || lua_tointeger(L, -2) < 1 || lua_tointeger(L, -2) > p->total)
            return luaL_error(L, "puzzle pieces must be a dense array");
        lua_pop(L, 1);
    }
    for (int i = 0; i < p->total; ++i) {
        lua_rawgeti(L, pieces, i + 1);
        if (legacy) legacyPuzzleName(L, -1);
        else if (!puzzleToken(L, -1)) return luaL_error(L, "invalid or missing puzzle piece");
        const char *token = lua_tostring(L, -1);
        if (legacy || !ordered) for (int j = 0; j < i; ++j)
            if (!strcmp(token, p->pieces[j])) return luaL_error(L, "duplicate puzzle piece");
        strcpy(p->pieces[i], token);
        lua_pop(L, 1);
    }
    if (legacy) {
        for (int i = 0; i < p->total; ++i) {
            char key[PMOSProgressKeyMax + 1];
            legacyPieceKey(key, p, i);
            reservePuzzleKey(L, key);
        }
        lua_pushinteger(L, definitions + 1);
        lua_rawseti(L, lua_upvalueindex(1), 0);
    } else reservePuzzleKey(L, p->key);
    lua_setfield(L, lua_upvalueindex(1), id); /* Private immutable copy. */
    return 0;
}

static int puzzleDefine(lua_State *L) { return declarePuzzle(L, 0); }

static int legacyPuzzleDeclare(lua_State *L) {
    lua_remove(L, 1); /* __call receives the API table before the user arguments. */
    return declarePuzzle(L, 1);
}

static ChapterPuzzle *puzzleById(lua_State *L) {
    luaL_checktype(L, 1, LUA_TSTRING);
    lua_pushvalue(L, 1);
    if (lua_rawget(L, lua_upvalueindex(1)) != LUA_TUSERDATA) luaL_error(L, "unknown puzzle id");
    return lua_touserdata(L, -1);
}

/* A single nonnegative progress integer is enough: prefix length or set bits.
   Never reinterpret out-of-range saved values as a successful solve. */
static int puzzleCount(lua_State *L, const ChapterPuzzle *p, int state) {
    unsigned bits = (unsigned)state;
    if (state < 0 || (p->ordered ? state > p->total : (bits >> p->total) != 0))
        return luaL_error(L, "invalid saved puzzle progress: %s", p->key);
    if (p->ordered) return state;
    int count = 0;
    for (; bits; bits &= bits - 1) ++count;
    return count;
}

static int puzzleStatus(lua_State *L) {
    if (lua_gettop(L) != 1) return luaL_error(L, "puzzle.status expects one id");
    const ChapterPuzzle *p = puzzleById(L);
    int count = puzzleCount(L, p, readProgress(L, session(L), p->key));
    lua_pushinteger(L, count);
    lua_pushinteger(L, p->total);
    lua_pushboolean(L, count == p->total);
    return 3;
}

static int puzzleMissing(lua_State *L) {
    if (lua_gettop(L) != 1) return luaL_error(L, "puzzle.missing expects one id");
    const ChapterPuzzle *p = puzzleById(L);
    int state = readProgress(L, session(L), p->key);
    int count = puzzleCount(L, p, state);
    lua_createtable(L, p->total - count, 0);
    int n = 0;
    for (int i = 0; i < p->total; ++i) {
        if (p->ordered ? i < count : (state & (1 << i)) != 0) continue;
        lua_pushstring(L, p->pieces[i]);
        lua_rawseti(L, -2, ++n);
    }
    return 1;
}

/* Both formats stage writes in the same VM transaction. The definition
   remains rooted in its private registry when we clear the argument stack. */
static void stagePuzzleValue(lua_State *L, const char *key, int value) {
    lua_settop(L, 0);
    lua_pushstring(L, key);
    lua_pushinteger(L, value);
    progressSet(L);
}

static int puzzleSubmit(lua_State *L) {
    int argc = lua_gettop(L);
    if (argc > 2) return luaL_error(L, "puzzle.submit expects id and piece");
    const ChapterPuzzle *p = puzzleById(L);
    const char *result = "invalid";
    if (argc == 2 && puzzleToken(L, 2)) {
        const char *token = lua_tostring(L, 2);
        int i = 0;
        while (i < p->total && strcmp(token, p->pieces[i])) ++i;
        if (i < p->total) {
            int state = readProgress(L, session(L), p->key);
            int count = puzzleCount(L, p, state);
            if (count == p->total) result = "complete";
            else if (p->ordered && strcmp(token, p->pieces[count])) result = "wrong";
            else if (!p->ordered && (state & (1 << i))) result = "duplicate";
            else {
                stagePuzzleValue(L, p->key, p->ordered ? count + 1 : (state | (1 << i)));
                result = count + 1 == p->total ? "solved" : "advanced";
            }
        }
    }
    lua_pushstring(L, result);
    return 1;
}

static ChapterPuzzle *legacyPuzzleById(lua_State *L, int argc) {
    if (lua_gettop(L) != argc) luaL_error(L, "wrong number of puzzle arguments");
    legacyPuzzleName(L, 1);
    return puzzleById(L);
}

static int legacyPuzzleSubmit(lua_State *L) {
    const ChapterPuzzle *p = legacyPuzzleById(L, 2);
    const char *piece = legacyPuzzleName(L, 2);
    char key[PMOSProgressKeyMax + 1];
    for (int i = 0; i < p->total; ++i) {
        int matches = !strcmp(piece, p->pieces[i]);
        if (!matches && !p->ordered) continue;
        legacyPieceKey(key, p, i);
        if (readProgress(L, session(L), key) != 1) {
            if (!matches) break;
            stagePuzzleValue(L, key, 1);
            lua_pushboolean(L, 1);
            return 1;
        }
        if (matches) break;
    }
    lua_pushboolean(L, 0);
    return 1;
}

static int legacyPuzzleSolved(lua_State *L) {
    const ChapterPuzzle *p = legacyPuzzleById(L, 1);
    char key[PMOSProgressKeyMax + 1];
    for (int i = 0; i < p->total; ++i) {
        legacyPieceKey(key, p, i);
        if (readProgress(L, session(L), key) != 1) {
            lua_pushboolean(L, 0);
            return 1;
        }
    }
    lua_pushboolean(L, 1);
    return 1;
}

static void registerPuzzle(lua_State *L) {
    static const luaL_Reg api[] = {
        {"define", puzzleDefine}, {"submit", puzzleSubmit}, {"status", puzzleStatus},
        {"missing", puzzleMissing}, {NULL, NULL}
    };
    static const luaL_Reg legacy[] = {
        {"puzzleSubmit", legacyPuzzleSubmit}, {"puzzleSolved", legacyPuzzleSolved}, {NULL, NULL}
    };
    lua_newtable(L);
    int keys = lua_gettop(L);
    luaL_newlibtable(L, api);
    lua_newtable(L); /* Modern definitions. */
    lua_pushvalue(L, keys);
    luaL_setfuncs(L, api, 2);

    lua_newtable(L); /* The callable puzzle table uses G's declaration contract. */
    lua_newtable(L); /* Legacy definitions, shared with both global functions. */
    lua_pushglobaltable(L);
    lua_pushvalue(L, -2);
    luaL_setfuncs(L, legacy, 1);
    lua_pop(L, 1);
    lua_pushvalue(L, keys);
    lua_pushcclosure(L, legacyPuzzleDeclare, 2);
    lua_setfield(L, -2, "__call");
    lua_setmetatable(L, -2);
    lua_setglobal(L, "puzzle");
    lua_pop(L, 1); /* keys */
}
