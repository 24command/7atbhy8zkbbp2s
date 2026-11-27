#import <Foundation/Foundation.h>
#import "../PhiMod/Sources/PMNativeOSInterruptionPlan.h"
#include <cassert>
#include <cstdio>
int main(){@autoreleasepool{
 NSDictionary *base=@{@"installedID":@"exact-IN",@"title":@"Song",@"group":@"merged"};
 __block int calls=0;NSObject *prepared=[NSObject new];
 NSDictionary *ok=PMOSBindInterruption(base,@"IN",@"in",^id(NSError **){++calls;return prepared;});
 assert(calls==1 && ok[@"interruption"]==prepared && !ok[@"interruptionError"]);
 NSDictionary *badImage=PMOSBindInterruption(base,@"IN",@"IN",^id(NSError **error){++calls;*error=[NSError errorWithDomain:@"fixture" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Missing KLD_BlueScreen.png"}];return nil;});
 assert(calls==2 && !badImage[@"interruption"] && [badImage[@"interruptionError"] isEqual:@"Missing KLD_BlueScreen.png"]);
 assert([badImage[@"installedID"] isEqual:base[@"installedID"]] && [badImage[@"title"] isEqual:base[@"title"]]);
 NSDictionary *wrong=PMOSBindInterruption(base,@"IN",@"AT",^id(NSError **){++calls;return prepared;});
 assert(calls==2 && wrong[@"interruptionError"] && !wrong[@"interruption"]);
 NSDictionary *duplicate=PMOSBindInterruption(ok,@"IN",@"IN",^id(NSError **){++calls;return prepared;});
 assert(calls==2 && duplicate[@"interruptionError"] && !duplicate[@"interruption"]);
 assert(!base[@"interruption"] && !base[@"interruptionError"]);
 NSDictionary *empty=PMOSBindInterruption(base,nil,@"IN",^id(NSError **){return nil;});assert(empty[@"interruptionError"]);
 puts("OS optional story failures isolated: success, missing image, wrong difficulty, duplicate, unchanged row");
}return 0;}