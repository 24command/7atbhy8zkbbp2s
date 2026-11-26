#include "../PhiMod/Core/PMChapterVM.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static PMOSPage page;
static void accepts(const char *source) {
    int ok = PMBuildOSPage(source, strlen(source), 3, &page);
    if (!ok) fprintf(stderr, "Unexpected rejection: %s\n%s\n", page.error, source);
    assert(ok);
}
static void rejects(const char *source, const char *message) {
    int ok = PMBuildOSPage(source, strlen(source), 3, &page);
    if (ok || !strstr(page.error, message))
        fprintf(stderr, "Expected %s; got %s\n%s\n", message, page.error, source);
    assert(!ok && strstr(page.error, message));
    assert(!page.nodes && !page.trackKeyCount);
}
static void declarations(void) {
    accepts("frame{};image{src='test.png'};hotspot{open=1}");
    for (int i = 0; i < 3; ++i) {
        const PMOSNode *node = &page.elements[i];
        assert(node->rotation == 0 && node->scaleX == 1 && node->scaleY == 1 && node->opacity == 1);
        assert(!node->trackLoop);
        for (int j = 0; j < PMOSTrackPropertyCount; ++j) assert(!node->tracks[j].count);
    }
    accepts("frame{x=-8,y=8,w=8,h=8,rotation=-1000000,scaleX=0,scaleY=-16,opacity=0,trackLoop=2,"
            "color='#00000000',tracks={rotation={{time=0,value=-10,ease='cubic',outTangent=3},"
            "{time=2,value=90,inTangent=-4}},opacity={{time=1,value=0},{time=2,value=1}}}};"
            "image{src='test.png',tracks={scaleX={{time=0,value=-1}}}};"
            "hotspot{open=1,tracks={w={{time=0,value=0}},red={{time=0,value=1}}}}");
    assert(page.trackKeyCount == 7);
    const PMOSNode *n = &page.elements[0];
    assert(n->numericFlags == (PMOSHasScaleX | PMOSHasScaleY | PMOSHasOpacity | PMOSHasColor));
    assert(n->scaleX == 0 && n->scaleY == -16 && n->opacity == 0 && n->trackLoop == 2);
    const PMOSTrack *track = &n->tracks[PMOSTrackRotation];
    assert(track->count == 2 && track->offset + track->count <= page.trackKeyCount);
    const PMOSTrackKey *keys = page.trackKeys + track->offset;
    assert(keys[0].ease == PMOSTrackCubic && keys[0].outTangent == 3 && keys[1].inTangent == -4);
    assert(keys[1].time == 2 && keys[1].value == 90);
    accepts("screen('intro');frame{rotation=20,scaleX=0,scaleY=-1,opacity=.5,trackLoop=1,"
            "tracks={blue={{time=0,value=0},{time=1,value=1}}}};"
            "entryTransition{kind='timeline',screen='intro',duration=2};screen('map');frame{}");
    assert(page.entryTransition.screen == 0 && page.initialScreen == 1);
}
static void spriteSequences(void) {
    accepts("screen('map');image{id='clip',src='original-curves.pma',loop=true,"
            "tracks={opacity={{time=0,value=0,ease='step'},{time=1,value=1}}}};"
            "image{src='STILL-SEQUENCE.PMA'}");
    assert(page.nodes == 2 && page.elements[0].kind == PMOSImage);
    assert(!strcmp(page.elements[0].src, "original-curves.pma") && page.elements[0].loop);
    assert(page.elements[0].tracks[PMOSTrackOpacity].count == 2);
    assert(!strcmp(page.elements[1].src, "STILL-SEQUENCE.PMA"));
    rejects("image{src='../clip.pma'}", "local media filename");
    rejects("image{src='sub/clip.pma'}", "local media filename");
    rejects("image{src='C:clip.pma'}", "local media filename");
    rejects("image{src='clip.pma',cover=1}", "exactly one");
    rejects("screen('intro');image{src='clip.pma'};"
            "entryTransition{kind='timeline',screen='intro',duration=2}", "still image");
    rejects("entryTransition{kind='timeline',screen='intro',duration=2};"
            "screen('intro');image{src='clip.PMA'}", "still image");
    accepts("screen('intro');image{src='still.png'};"
            "entryTransition{kind='timeline',screen='intro',duration=2};"
            "screen('map');image{src='clip.pma'}");
    assert(page.entryTransition.screen == 0 && page.initialScreen == 1);
}
static void invalid(void) {
    const char *bad[] = {
        "rotation='1'", "scaleX=false", "scaleY={}", "opacity='0.5'", "x='1'", "w='1'",
        "rotation=1/0", "rotation=1000001", "scaleX=-17", "scaleY=17", "opacity=-.1",
        "opacity=1.1", "x=-8.1", "y=8.1", "w=0", "h=8.1",
        "trackLoop=0", "trackLoop=-1", "trackLoop='1'", "trackLoop=1/0", "trackLoop=0/0",
        "tracks=false", "tracks={wat={}}", "tracks={['x\\0bad']={}}", "tracks={[1]={}}",
        "tracks={x=1}", "tracks={x={}}", "tracks={x={[0]={time=0,value=0}}}",
        "tracks={x={{time=0,value=0},[3]={time=1,value=1}}}",
        "tracks={x={{time=0,value=0},extra=1}}", "tracks={x={false}}",
        "tracks={x={{value=0}}}", "tracks={x={{time=0}}}", "tracks={x={{time='0',value=0}}}",
        "tracks={x={{time=0,value='0'}}}", "tracks={x={{time=-1,value=0}}}",
        "tracks={x={{time=1/0,value=0}}}", "tracks={x={{time=0,value=0/0}}}",
        "tracks={x={{time=0,value=9}}}", "tracks={w={{time=0,value=-1}}}",
        "tracks={h={{time=0,value=9}}}", "tracks={rotation={{time=0,value=1000001}}}",
        "tracks={scaleX={{time=0,value=-17}}}", "tracks={scaleY={{time=0,value=17}}}",
        "tracks={opacity={{time=0,value=1.1}}}", "tracks={red={{time=0,value=-1}}}",
        "tracks={green={{time=0,value=2}}}", "tracks={blue={{time=0,value=1/0}}}",
        "tracks={x={{time=0,value=0,extra=1}}}", "tracks={x={{time=0,value=0,[1]=1}}}",
        "tracks={x={{time=0,value=0,ease='unknown'}}}", "tracks={x={{time=0,value=0,ease=1}}}",
        "tracks={x={{time=0,value=0,inTangent='1'}}}", "tracks={x={{time=0,value=0,outTangent=1/0}}}",
        "tracks={x={{time=0,value=0},{time=0,value=1}}}",
        "tracks={x={{time=2,value=0},{time=1,value=1}}}",
        "tracks={x={{time=0,value=0,ease='cubic'},{time=1,value=1,inTangent=0}}}",
        "tracks={x={{time=0,value=0,ease='cubic',outTangent=0},{time=1,value=1}}}",
        "tracks={x={{time=0,value=0,ease='cubic'}}}",
        "tracks={x={{time=0,value=0,ease='cubic',outTangent=1e308},{time=2,value=1,inTangent=0}}}"
    };
    for (size_t i = 0; i < sizeof(bad)/sizeof(*bad); ++i) {
        char source[512];
        snprintf(source, sizeof(source), "frame{%s}", bad[i]);
        rejects(source, "");
    }
}
static void budgets(void) {
    accepts("local k={};for i=1,8192 do k[i]={time=i-1,value=.5} end;"
            "frame{tracks={x=k,y=k,w=k,h=k}}");
    assert(page.trackKeyCount == PMOSMaxPageTrackKeys);
    for (int p = PMOSTrackX; p <= PMOSTrackH; ++p) assert(page.elements[0].tracks[p].count == 8192);
    rejects("local k={};for i=1,8193 do k[i]={time=i-1,value=.5} end;frame{tracks={x=k}}", "8192");
    rejects("local k={};for i=1,8192 do k[i]={time=i-1,value=.5} end;"
            "frame{tracks={x=k,y=k,w=k,h=k}};frame{tracks={opacity={{time=0,value=1}}}}", "32768");
}
static void callbacks(void) {
    const char *bodies[] = {"frame{tracks={x={{time=0,value=1}}}}", "return {tracks={}}", "return {rotation=2}"};
    for (int i = 0; i < 3; ++i) {
        char source[512];
        snprintf(source, sizeof(source), "frame{onClick=function() %s end,tracks={x={{time=0,value=.5}}}}", bodies[i]);
        PMOSSession *session = PMOSStart(source, strlen(source), 1, &page);
        assert(session);
        PMOSAction action;
        assert(!PMOSClick(session, 0, &action));
        assert(action.error[0] && page.trackKeyCount == 1 && page.nodes == 1);
        assert(page.trackKeys[0].value == .5);
        PMOSStop(session);
    }
}
int main(void) {
    declarations(); spriteSequences(); invalid(); budgets(); callbacks();
    puts("PMChapterNumericTracksTest passed");
    return 0;
}
