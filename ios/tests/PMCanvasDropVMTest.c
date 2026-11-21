#include "../PhiMod/Core/PMChapterVM.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static PMOSPage page;
static const char board[] =
    "screen('board');local names={'a','b','c','d','e','f'};"
    "puzzle{id='board',mode='set',pieces=names};"
    "for i=1,6 do local id=names[i]; local x=i/8;"
    "if progress.get('puzzle.board.'..id)==1 then "
    " image{cover=1,x=x,y=.65,w=.1,h=.1} "
    "else image{cover=1,x=x,y=.15,w=.1,h=.1,dropTarget=id,alphaHit=true,"
    " onClick=function() puzzleSubmit('board',id) end} end;"
    "frame{id=id,x=x,y=.65,w=.1,h=.1} end;"
    "screen('other');frame{id='a'};hotspot{dropTarget='a',onClick=function() end}";

static int saved[6];
static int readFlag(void *ctx,const char *key,int *value) {
    (void)ctx;
    assert(!strncmp(key,"puzzle.board.",13) && strlen(key)==14);
    int i=key[13]-'a'; assert(i>=0 && i<6);
    *value=saved[i]; return 1;
}
static int commit(void *ctx,const PMOSProgressChange *c,size_t count) {
    assert(count==1); int prior; readFlag(ctx,c->key,&prior);
    assert(!prior && c->value==1); saved[c->key[13]-'a']=1; return 1;
}
int main(void) {
    PMOSProgress flags={NULL,readFlag,commit};
    PMOSSession *s=PMOSStartWithProgress(board,strlen(board),1,&page,flags);
    assert(s && page.nodes==14 && page.elements[13].dropIndex==12);
    for(int i=0;i<6;i++) {
        assert(page.elements[2*i].dropIndex==2*i+1 && page.elements[2*i].alphaHit);
        PMOSAction a; assert(PMOSClick(s,2*i,&a)); assert(saved[i]==1);
    }
    PMOSStop(s);
    s=PMOSStartWithProgress(board,strlen(board),1,&page,flags); assert(s);
    for(int i=0;i<6;i++) {
        const PMOSNode *n=&page.elements[2*i];
        assert(n->dropIndex==-1 && !n->handler && n->x==page.elements[2*i+1].x && n->y==.65);
    }
    PMOSStop(s);
    const char *invalid[]={
        "frame{id='p',dropTarget='p',onClick=function() end}",
        "frame{dropTarget='x',onClick=function() end};screen('other');frame{id='x'}",
        "frame{id='x'};frame{dropTarget='x',open=1}",
        "frame{id='x'};frame{dropTarget='x'}",
        "frame{id='p',dropTarget='child',onClick=function() end};frame{parent='p',id='child'}",
        "frame{alphaHit=true}"
    };
    for(size_t i=0;i<sizeof(invalid)/sizeof(*invalid);i++) {
        assert(!PMBuildOSPage(invalid[i],strlen(invalid[i]),1,&page) && page.error[0]);
    }
    puts("six-piece canvas drop contracts passed"); return 0;
}
