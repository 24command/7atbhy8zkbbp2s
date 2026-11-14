#include "../PhiMod/Core/PMSelectorDifficulty.hpp"
#include "../PhiMod/Core/PMDifficultyPages.hpp"
#include "../PhiMod/Core/PMUIInteraction.hpp"
#include <cassert>
#include <cstdio>
int main(){
 // Every sparse chart set, including only AT/extra, only EZ, and no IN.
 for(unsigned mask=1;mask<16;++mask)for(int requested=-2;requested<7;++requested){
  int chosen=phimod::availableDifficulty(mask,requested);assert(chosen>=0&&chosen<4);assert(mask&(1u<<chosen));
  if(requested>=0&&requested<4&&(mask&(1u<<requested)))assert(chosen==requested);
  assert(phimod::availableDifficulty(mask,chosen)==chosen);
 }
 assert(phimod::availableDifficulty(8,0)==3);assert(phimod::availableDifficulty(4,3)==2);assert(phimod::availableDifficulty(2,2)==1);assert(phimod::availableDifficulty(1,3)==0);
 // Return from each extra page to each official chart mask without carrying a page index as native slot.
 for(size_t extras=1;extras<=40;++extras)for(bool at:{false,true}){
  size_t entries=3+size_t(at)+extras,visited=0;for(size_t page=0;page<phimod::difficultyPages(entries);++page){size_t n=phimod::difficultyPageSize(entries,page);assert(n>0&&n<=4);visited+=n;assert(phimod::difficultyPrevious(page)==(page>0));assert(phimod::difficultyNext(entries,page)==(page+1<phimod::difficultyPages(entries)));for(unsigned mask=1;mask<16;++mask){int restored=phimod::availableDifficulty(mask,3);assert(mask&(1u<<restored));}}
  assert(visited==entries);
 }
 phimod::UITapGate tap;tap.begin(1,20,20);assert(tap.finish(1,21,20,12,true));assert(!tap.finish(1,21,20,12,true));tap.begin(1,20,20);tap.move(1,100,20,12);assert(!tap.finish(1,100,20,12,true));tap.begin(1,20,20);tap.reset();assert(!tap.finish(1,20,20,12,true));
 puts("PASS all sparse masks, AT fallback, extra-to-official transitions, page boundaries, tap/drag/cancel");
}
