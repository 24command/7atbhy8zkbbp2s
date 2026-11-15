#include "../PhiMod/Core/PMSelectorRowRefresh.hpp"
#include <cassert>
#include <cstdio>
int main(){
 phimod::SelectorRowRefresh refresh;phimod::SelectorRowKey key{1,2,10,2000,2,7,"native"};
 assert(refresh.full(key));refresh.commit(key,100);assert(!refresh.full(key));
 unsigned work=0;
 for(uintptr_t song=100;song<700;++song){
  // Scroll/selection alone never scans all 2000 entries again.
  work+=refresh.full(key)?key.count:2;refresh.commit(key,song);assert(refresh.previousSelected()==song);
 }
 assert(work==1200);
 auto changes=[&](phimod::SelectorRowKey changed){assert(refresh.full(changed));refresh.commit(changed,200);assert(!refresh.full(changed));key=changed;};
 auto next=key;next.slot=3;changes(next);
 next=key;next.logical="SP";changes(next);
 next=key;next.logical="DP";changes(next);
 next=key;next.logical="native";next.slot=2;changes(next);
 next=key;++next.version;changes(next); // same-count sort/replacement
 next=key;++next.items;changes(next); // replacement list with same count/version
 next=key;++next.count;changes(next);
 next=key;++next.revision;changes(next); // records/unlock/import change
 next=key;++next.owner;changes(next);
 refresh.invalidate();assert(refresh.full(key));refresh.commit(key,300);assert(!refresh.full(key));
 refresh.reset();assert(refresh.previousSelected()==0&&refresh.full(key));
 puts("PASS selector rows: bounded scrolling work; difficulty/list/revision/scene invalidation");
}
