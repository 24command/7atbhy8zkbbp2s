#import "../PhiMod/Sources/PMDifficultyMetadata.h"
#include "../PhiMod/Core/PMDifficultyPages.hpp"
#include <cassert>
#include <cstdio>
int main(){@autoreleasepool{
 assert(PMStockDifficulty(@"at")==3);assert(PMStockDifficulty(@"SP")==-1);assert(PMStockDifficulty(@"Another INFINITY")==-1);
 assert([PMDifficultyName(@"  SP  ")isEqualToString:@"SP"]);
 assert(PMDifficultyNumber(@"16.7")==16.7);for(NSString*s in @[@"",@"?",@"SP",@"16+",@"nan",@"-1"])assert(PMDifficultyNumber(s)==0);
 assert([PMDifficultyText(@{@"difficulty":@0,@"difficultyText":@"∞"})isEqualToString:@"∞"]);
 assert(PMDifficultyRGB(@"").count==0);assert(PMDifficultyRGB(@"255, 128,0").count==3);
 for(NSString*s in @[@"256,0,0",@"1,2",@"1.2,2,3",@"-1,0,0",@"1,2,3x"])assert(PMDifficultyRGB(s)==nil);
 assert([PMDifficultyRecordLevel(@{@"level":@"SP"})isEqualToString:@"AT"]);
 for(size_t count=1;count<100;++count){size_t shown=0;for(size_t page=0;page<phimod::difficultyPages(count);++page){size_t n=phimod::difficultyPageSize(count,page);assert(n>=1&&n<=4);shown+=n;assert(phimod::difficultyPrevious(page)==(page>0));assert(phimod::difficultyNext(count,page)==(page+1<phimod::difficultyPages(count)));}assert(shown==count);}
 puts("PASS custom difficulty names/RGB/text/zero arithmetic and exact four-wide pages");
}return 0;}
