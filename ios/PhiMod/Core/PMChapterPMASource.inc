/* PMA is a manifest-backed sprite sequence, not a video extension alias.
   Keep its opt-in here instead of widening challenge intro or timeline rules.
   presentationUTF8 is defined by the presentation helpers later in this TU. */
static int presentationUTF8(const unsigned char *s);
static int readPMASource(lua_State *L, int index, char *out, size_t cap) {
    if (lua_type(L, index) != LUA_TSTRING) return 0;
    size_t n;
    const char *name = lua_tolstring(L, index, &n);
    if (n < 4 || name[n - 4] != '.' ||
        (name[n - 3] != 'p' && name[n - 3] != 'P') ||
        (name[n - 2] != 'm' && name[n - 2] != 'M') ||
        (name[n - 1] != 'a' && name[n - 1] != 'A')) return 0;
    if (n < 5 || n >= cap || name[0] == '.' || memchr(name, 0, n) ||
        strpbrk(name, "/\\:") || !presentationUTF8((const unsigned char *)name))
        luaL_error(L, "PMA src expects a UTF-8 local .pma basename");
    for (const unsigned char *p = (const unsigned char *)name; *p; ++p)
        if (*p < 32 || *p == 127 || (*p == 0xc2 && p[1] < 0xa0))
            luaL_error(L, "PMA basename contains a control character");
    memcpy(out, name, n + 1);
    return 1;
}
