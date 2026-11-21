// Included in pmcontent, next to the shared checked selector path.
static BOOL startSecretCourse(NSString *chapter,NSString *door,NSArray *members,NSInteger tier,bool noPause){
 using pmsecretcourse::Pin;
 if(!runtime||!pmsecretcourse::backendReady()||playing||PMDoorActive()||pmchallenge::variable()||pmsecretcourse::active()||
    ![chapter isKindOfClass:NSString.class]||![chapter hasPrefix:@"pm_"]||
    ![door isKindOfClass:NSString.class]||!door.length||door.length>53||
    [door rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-"] invertedSet]].location!=NSNotFound||
    ![members isKindOfClass:NSArray.class]||(members.count!=3&&members.count!=4)||tier < -1||tier>4)return NO;
 auto &r=*runtime;P selector=target(r,loadingSelector);if(!r.alive(selector))return NO;
 P control=r.get<P>(selector,"challengeSongSelectorControl");if(!r.alive(control))return NO;
 P pick=r.get<P>(control,"selectButton");
 if(r.alive(pick)&&r.unbox<bool>(r.call(r.call(pick,"get_gameObject"),"get_activeInHierarchy")))return NO;
 P templateList=r.get<P>(control,"challengeSongItems");if(!templateList)return NO;
 struct Cleanup { Runtime &r; ~Cleanup(){if(!pmsecretcourse::active())pmsecretcourse::clearBindings(r);} } cleanup{r};
 Pin list(r,r.object_new(r.object_get_class(templateList)));r.call(list.get(),".ctor");
 NSUInteger revision=PMContentStore.shared.revision;
 P queue=list.get();
 for(id member in members){
  if(![member isKindOfClass:NSDictionary.class])return NO;
  NSString *sid=member[@"songID"],*diff=member[@"difficulty"];
  if(![sid isKindOfClass:NSString.class]||!sid.length||(diff&&(![diff isKindOfClass:NSString.class]||!diff.length)))return NO;
  if(!checkedSong(r,selector,chapter,sid,diff,nil,^BOOL(P item,P song,int slot,NSDictionary *chart,NSString *){
   Pin row(r,r.call(item,"MemberwiseClone")),data(r,r.call(song,"MemberwiseClone"));
   Pin numbers(r,r.call(r.get<P>(song,"difficulty"),"Clone"));r.put(data.get(),"difficulty",numbers.get());
   if(chart){r.arrayPutFloat(numbers.get(),slot,PMDifficultyNumber(chart[@"difficulty"]));r.put(row.get(),"sortIndex",-2147483000);r.put(data.get(),"songsId",r.managedString(chart[@"id"]));r.put(row.get(),"coverBlurAssetCode",r.managedString(selectorThumbnailKey(chart[@"id"])));}
   r.put(row.get(),"songInfo",data.get());
   // A private chart binding for this clone, never a mutable AT slot. Stock
   // clones are marked explicitly so a later AT rebind cannot replace them.
   pmsecretcourse::bindChart(r,data.get(),chart);
   Pin entry(r,r.object_new(r.type("Phigros2.SongSelector.Scripts","ChallengeSongItem")));r.call(entry.get(),".ctor");
   r.put(entry.get(),"songInfo",row.get());r.put(entry.get(),"levelIndex",slot);
   r.call(queue,"Add",{"Phigros2.SongSelector.Scripts.ChallengeSongItem"},{entry.get()});return YES;
  }))return NO;
 }
 return revision==PMContentStore.shared.revision && pmsecretcourse::launch(r,list.get(),chapter,door,tier,noPause);
}
