#include "../PhiMod/Core/PMChapterVM.h"
#include <assert.h>
#include <string.h>

static PMOSPage page;
static int build(const char *s) { return PMBuildOSPage(s,strlen(s),1,&page); }

int main(void) {
    assert(build("home('os')") && page.nativeChapter == 9 && page.nativePhase == 1);
    assert(build("nativeChapter(9,2); nativeChapter(8)") && page.nativeChapter == 8 && page.nativePhase == 1);
    assert(build("nativeChapter(9,2); nativeChapter(9)") && page.nativeChapter == 9 && page.nativePhase == 1);
    assert(build("nativeChapter(9,1)") && page.nativePhase == 1);
    const char *invalid[] = {"", "8,1", "8,2", "9,0", "9,3", "9,2.0", "9,'2'", "9,nil", "9,2,1", "'9',2"};
    for (unsigned i = 0; i < sizeof(invalid)/sizeof(invalid[0]); ++i) {
        char call[64] = "nativeChapter(";
        strcat(call,invalid[i]); strcat(call,")");
        assert(!build(call));
    }
    const char *script = "nativeChapter(9,2); onEnterMovie{key='arrival',src='arrival.mp4'};"
        "hotspot{onClick=function() nativeChapter(9) end}; hotspot{onClick=function() return {open=1} end}";
    PMOSSession *session = PMOSStart(script,strlen(script),1,&page);
    assert(session && page.nativeChapter == 9 && page.nativePhase == 2);
    assert(!strcmp(page.entryMovieKey,"movie.arrival") && !strcmp(page.entryMovieName,"arrival.mp4"));
    PMOSAction action;
    assert(!PMOSClick(session,0,&action) && strstr(action.error,"declarations are closed"));
    assert(PMOSClick(session,1,&action) && action.song == 1);
    PMOSStop(session);
    return 0;
}
