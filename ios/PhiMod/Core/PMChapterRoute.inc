/* nativeChapter(8), nativeChapter(9 [, 1|2]). Route declarations are
   evaluated before entry, including when Lua branches on author progress. */
static int nativeChapter(lua_State *L) {
    PMOSPage *page = declarationPage(L);
    int count = lua_gettop(L);
    if ((count != 1 && count != 2) || !lua_isinteger(L, 1))
        return luaL_error(L, "expected nativeChapter(8) or nativeChapter(9 [, 1|2])");
    lua_Integer chapter = lua_tointeger(L, 1);
    if (chapter != 8 && chapter != 9) return luaL_error(L, "nativeChapter expects 8 or 9");
    lua_Integer phase = 1;
    if (count == 2) {
        if (chapter != 9 || !lua_isinteger(L, 2))
            return luaL_error(L, "only chapter 9 accepts an integer phase (1 or 2)");
        phase = lua_tointeger(L, 2);
        if (phase != 1 && phase != 2) return luaL_error(L, "chapter 9 phase must be 1 or 2");
    }
    page->nativeChapter = (int)chapter;
    page->nativePhase = (int)phase;
    return 0;
}
