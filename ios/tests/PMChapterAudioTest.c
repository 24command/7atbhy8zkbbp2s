#include "../PhiMod/Core/PMChapterVM.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static PMOSPage p;
static void ok(const char *s){int b=PMBuildOSPage(s,strlen(s),3,&p);if(!b)fprintf(stderr,"%s\n",p.error);assert(b);}
static void bad(const char *s){assert(!PMBuildOSPage(s,strlen(s),3,&p));assert(!p.audioCueCount);}
int main(void){
 ok("screen('main');audio{src='map.m4a',channel='bgm',loop=true};hotspot{id='door',open=1};audio{src='tap.wav',event='tap',target='door'};screen('return');audio{src='clear.m4a',start=3.2,duration=2,volume=.7}");
 assert(p.audioCueCount==3);assert(p.audioCues[0].screen==0 && p.audioCues[0].loop && p.audioCues[0].channel==PMOSAudioBGM);
 assert(p.audioCues[0].volume==1 && p.audioCues[0].event==PMOSAudioPage);
 assert(p.audioCues[1].event==PMOSAudioTap && !strcmp(p.audioCues[1].target,"door"));
 assert(p.audioCues[2].screen==1 && p.audioCues[2].start==3.2 && p.audioCues[2].duration==2 && p.audioCues[2].volume==.7);
 ok("screen('x');hotspot{id='door',open=1};audio{event='tap',src='all.wav'};audio{event='tap',target='door',src='door.wav'}");
 ok("screen('x');audio{src='a.wav'};audio{src='b.wav',start=1};screen('y');audio{src='a.wav'}");
 ok("screen('x');audio{src='loop.m4a',introSrc='intro.m4a',loop=true,channel='bgm'}");
 assert(!strcmp(p.audioCues[0].introSrc,"intro.m4a"));
 bad("screen('x');audio{src='loop.m4a',introSrc='intro.m4a'}");
 bad("screen('x');audio{src='loop.m4a',introSrc='../intro.m4a',loop=true}");
 bad("audio{src='a.wav'}");
 const char *invalid[]={"src='../a.wav'","src='/a.wav'","src='a.ogg'","src='a.wav',volume=2","src='a.wav',volume=0/0","src='a.wav',start=-1","src='a.wav',duration=1/0","src='a.wav',loop=1","src='a.wav',event='click'","src='a.wav',channel='music'","src='a.wav',target='door'","src='a.wav',event='tap',target='missing'","src='a.wav',event='tap',loop=true","src='a.wav',event='tap',start=1","src='a.wav',unknown=1"};
 char s[512];for(unsigned i=0;i<sizeof(invalid)/sizeof(*invalid);++i){snprintf(s,sizeof(s),"screen('x');audio{%s}",invalid[i]);bad(s);}
 bad("screen('x');audio{src='a.wav'};audio{src='b.wav'}");
 bad("screen('x');audio{src='a.wav',event='tap'};audio{src='b.wav',event='tap'}");
 bad("screen('x');for i=1,65 do audio{src='a.wav',start=i} end");
 ok("screen('x');for i=1,64 do audio{src='a.wav',start=i} end");assert(p.audioCueCount==64);
 puts("OS audio declarations: defaults, timed cues, targets, channels, invalid/conflicting config passed");
}
