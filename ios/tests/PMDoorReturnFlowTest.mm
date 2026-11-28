#import "../PhiMod/Sources/PMDoorRun.h"
#import "../PhiMod/Sources/PMOSAuthorProgress.h"
#import "../PhiMod/Core/PMChapterVM.h"
#include <cassert>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <thread>
#include <memory>
static NSString *root;
NSString *PMDoorRunTestRoot(){return root;}
void PMDiagnosticsWrite(const char *msg){std::fprintf(stderr,"%s\n",msg);std::abort();}
static int read(void *ctx,const char *key,int *value){return [(__bridge PMOSAuthorProgress*)ctx readKey:@(key) value:value];}
static int write(void *ctx,const PMOSProgressChange *changes,size_t count){NSMutableDictionary*d=[NSMutableDictionary new];for(size_t i=0;i<count;i++)d[@(changes[i].key)]=@(changes[i].value);return [(__bridge PMOSAuthorProgress*)ctx commitValues:d];}
static const char *script=R"(
home('os');screen('main')
local h=challengeProgress('red')
local returning=h.cleared and progress.get('door.red.new')~=0 and progress.get('scene.red-return')==0
if returning then onEnterScene{key='red-return',screen='return',to='main',duration=9} end
challenge{id='red',song=1,tiers={{after=0,hp=10,perfect=0,good=-1,bad=-2,miss=-3}},replaySongs={{song=1,difficulty='IN'}}}
frame{id='door',start=returning and 0 or .3,enter=returning and 0 or .37,fade=returning and 0 or .17}
image{id='face',src=h.cleared and 'clear.png' or 'open.png'}
image{id='gem',src='gem.png',hidden=not h.cleared}
hotspot{id='play',challenge='red'}
if returning then screen('return');frame{duration=9} end
)";
static void check(int stage){
 PMDoorProgressBarrier(); // Same barrier as PMNativeOSProgram before reading author progress.
 std::thread([=]{@autoreleasepool{
  auto store=[[PMOSAuthorProgress alloc]initWithRoot:root chapter:@"chapter"];
  auto page=std::make_unique<PMOSPage>();
  auto vm=PMOSStartWithProgress(script,strlen(script),1,page.get(),{(__bridge void*)store,read,write});assert(vm);
  assert(page->challenges[0].state==(stage?PMOSChallengeClear:PMOSChallengeClosed));
  assert(!strcmp(page->elements[1].src,stage?"clear.png":"open.png"));assert(page->elements[2].hidden==!stage);
  assert(bool(page->enterScene.declared)==(stage==1));
  if(stage==1){assert(page->enterScene.duration==9 && !page->enterScene.seen);assert(page->elements[0].start==0 && page->elements[0].motion.enter==0 && page->elements[0].fade==0);}
  if(stage==2){int clear=0;assert([store readKey:@"door.red.clear" value:&clear]&&clear==1);}
  PMOSStop(vm);
 }}).join();
}
int main(){@autoreleasepool{
 root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];check(0);
 double hp=0,d[4]={};assert(PMDoorArm(@"chapter",@"red",@"group",2,@"chart-IN",10,@[@0,@(-1),@(-2),@(-3)]));
 assert(PMDoorBeginExactTrack(@"group",2,@"chart-IN",&hp,d));PMDoorFinish(YES);check(1);
 // Unfinished return presentation does not consume the real clear or its animation.
 check(1);
 std::thread([]{@autoreleasepool{auto store=[[PMOSAuthorProgress alloc]initWithRoot:root chapter:@"chapter"];assert([store commitValues:@{@"scene.red-return":@1}]);}}).join();check(2);
 assert(PMDoorArmReplay(@"group",2,@"chart-IN"));assert(PMDoorConsumeReplay(@"group",2,@"chart-IN"));PMDoorFinish(YES);check(2);
 assert([NSFileManager.defaultManager removeItemAtPath:root error:nil]);puts("Door outcome -> persisted clear/new -> real VM return scene -> clear/gem -> once completion passed");
}return 0;}