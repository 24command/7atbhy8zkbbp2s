#include "../PhiMod/Core/PMChapterVM.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static PMOSPage page;
static int build(const char *script) {
    return PMBuildOSPage(script, strlen(script), 3, &page);
}

int main(void) {
    assert(build("nativeChapter(8); local w={0,0.25,1};"
                 "card(1,'First','Signal',{waveform=w,seconds=4,heading='RX'});"
                 "w[2]=0.75; card(1,'Second','Echo',{challenge='gate',waveform=w});"
                 "card(1,'Third','Empty',{challenge='gate'});"
                 "challenge{id='gate',secretCourse={{song=1},{song=2},{song=3}}}"));
    assert(page.count == 3 && page.nativeChapter == 8);
    const PMOSCard *first = &page.cards[0], *second = &page.cards[1], *third = &page.cards[2];
    assert(first->speech && first->seconds == 4 && !strcmp(first->speechHeading,"RX"));
    assert(first->waveformCount == 3 && first->waveform[0] == 0 && first->waveform[1] == .25f && first->waveform[2] == 1);
    assert(second->speech && second->challenge == 1 && second->waveformCount == 3 && second->waveform[1] == .75f);
    assert(!third->speech && third->challenge == 1 && !third->waveformCount);

    assert(build("local w={}; for i=1,100 do w[i]=i/100 end; card(2,nil,nil,{waveform=w})"));
    assert(page.cards[0].waveformCount == 100 && page.cards[0].waveform[99] == 1);
    assert(build("card(1); card(2,nil,nil,{}); card(3,nil,nil,{waveform=nil,seconds=1})"));
    assert(!page.cards[0].speech && page.cards[1].speech && page.cards[2].speech);
    for (int i=0; i<3; ++i) assert(page.cards[i].waveformCount == 0);
    assert(!build("local w={}; for i=1,101 do w[i]=0 end; card(1,nil,nil,{waveform=w})"));
    const char *invalid[] = {"{}", "false", "0.5", "{[2]=1}", "{0,[3]=1}", "{0,label=1}",
                             "{'0.5'}", "{true}", "{-0.1}", "{1.01}", "{0/0}", "{1/0}"};
    for (size_t i=0; i<sizeof(invalid)/sizeof(*invalid); ++i) {
        char script[128];
        snprintf(script,sizeof(script),"card(1,nil,nil,{waveform=%s})",invalid[i]);
        assert(!build(script));
    }
    puts("C8 waveform VM tests passed");
    return 0;
}
