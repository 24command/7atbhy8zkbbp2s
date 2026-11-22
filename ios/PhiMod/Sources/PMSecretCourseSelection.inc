// A detail row carries the resolved installed ID and slot. Its SongsItem is a
// display snapshot. ChallengeMode also needs the native song's music flags,
// levelMods and judgeLineImages, so take the gameplay data from the same group.
static BOOL checkedOwnedCourseMember(Runtime &r, NSString *sid, NSString *difficulty,
                                     NSDictionary *library, NSDictionary *officialSongs,
                                     CheckedCourseMember collect) {
    pmnativeosrows::Row saved;
    if (!pmnativeosrows::lookup(sid, difficulty, saved) || !saved.row || saved.slot < 0 || saved.slot > 3) return NO;
    P displaySong = r.get<P>(saved.row, "songInfo");
    if (!displaySong || ![r.string(r.get<P>(displaySong, "songsId")) isEqualToString:sid]) return NO;

    NSDictionary *chart = nil;
    for (NSDictionary *candidate in library[@"songs"]) {
        if (![candidate[@"id"] isEqualToString:sid]) continue;
        if (chart) return NO;
        chart = candidate;
    }
    NSString *label = [difficulty stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (difficulty && !label.length) return NO;
    NSString *group = [chart[@"groupId"] length] ? chart[@"groupId"] : sid;
    NSDictionary *official = officialSongs[group];
    if (chart) {
        int stock = PMStockDifficulty(chart[@"level"]);
        if (officialSongs[sid] || saved.slot != (stock < 0 ? 3 : stock) ||
            (label.length && !checkpointLevelMatches(chart, label))) return NO;
    } else {
        NSArray *ratings = official[@"difficulty"];
        if (NSUInteger(saved.slot) >= ratings.count || !([ratings[saved.slot] doubleValue] > 0) ||
            (label.length && PMStockDifficulty(label) != saved.slot)) return NO;
    }
    P song = r.call(r.mainGame(), "GetSongInformation", {"System.String"}, {r.managedString(group)});
    if (!song || ![r.string(r.get<P>(song, "songsId")) isEqualToString:group]) return NO;
    P levels = r.get<P>(song, "levels"), numbers = r.get<P>(song, "difficulty");
    if (!levels || !numbers || uintptr_t(saved.slot) >= r.array_length(levels) ||
        uintptr_t(saved.slot) >= r.array_length(numbers) || (!chart && !(r.unbox<float>(r.arrayAt(numbers, saved.slot)) > 0))) return NO;
    if ((official && !checkpointOfficialOpen(r, song, official, saved.slot)) ||
        !pmunlock::courseMemberOpen(r, group, chart, false)) return NO;
    return collect(saved.row, song, saved.slot, chart, group);
}

// Included in pmcontent, next to the shared checked selector path.
static BOOL startSecretCourse(NSString *chapter,NSString *door,NSArray *members,NSInteger tier,bool noPause){
 using pmsecretcourse::Pin;
 if(!runtime||!pmsecretcourse::backendReady()||playing||PMDoorActive()||pmchallenge::variable()||pmsecretcourse::active()||
    ![chapter isKindOfClass:NSString.class]||![chapter hasPrefix:@"pm_"]||
    ![door isKindOfClass:NSString.class]||!door.length||door.length>53||
    [door rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-"] invertedSet]].location!=NSNotFound||
    ![members isKindOfClass:NSArray.class]||(members.count!=3&&members.count!=4)||tier < -1||tier>4)return NO;
 auto &r=*runtime;
 P root=pmnativeosscene::activeRoot(r),selector=nullptr;
 NSUInteger revision=PMContentStore.shared.revision;
 NSDictionary *library=nil,*officialSongs=nil;
 NSSet *chapterIDs=nil;
 if(root){
    NSString *current=r.string(r.staticValue<P>(r.klass("GameInformation"),"nowChapterCode","System.String"));
    if(![current isEqualToString:chapter]||pendingSong.length||PMUnlockMediaBusy())return NO;
    library=[PMContentStore.shared snapshot];
    officialSongs=PMOfficialSongMap(officialCache);
    chapterIDs=[NSSet setWithArray:PMChapterSongIDs(library,officialCache,chapter)];
 }else{
    selector=target(r,loadingSelector);if(!r.alive(selector))return NO;
    P control=r.get<P>(selector,"challengeSongSelectorControl");if(!r.alive(control))return NO;
    P pick=r.get<P>(control,"selectButton");
    if(r.alive(pick)&&r.unbox<bool>(r.call(r.call(pick,"get_gameObject"),"get_activeInHierarchy")))return NO;
 }
 struct Cleanup { Runtime &r; ~Cleanup(){if(!pmsecretcourse::active())pmsecretcourse::clearBindings(r);} } cleanup{r};
 // The declared field supplies the closed List<ChallengeSongItem> class even
 // on a cold launch when GameInformation has no previous challenge queue.
 P field=r.field(r.klass("GameInformation"),"challengeSongItems","System.Collections.Generic.List<Phigros2.SongSelector.Scripts.ChallengeSongItem>",false);
 P listClass=r.class_from_type(r.field_get_type(field));if(!listClass)return NO;
 Pin list(r,r.object_new(listClass));r.call(list.get(),".ctor");
 P queue=list.get();
 CheckedCourseMember collect=^BOOL(P item,P song,int slot,NSDictionary *chart,NSString *){
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
 };
 for(id member in members){
    if(![member isKindOfClass:NSDictionary.class])return NO;
    NSString *sid=member[@"songID"],*diff=member[@"difficulty"];
    if(![sid isKindOfClass:NSString.class]||!sid.length||(diff&&(![diff isKindOfClass:NSString.class]||!diff.length)))return NO;
    if(root){
        if(![chapterIDs containsObject:sid]||!checkedOwnedCourseMember(r,sid,diff,library,officialSongs,collect))return NO;
    }else if(!checkedSong(r,selector,chapter,sid,diff,nil,collect))return NO;
 }
 if(revision!=PMContentStore.shared.revision||(root&&root!=pmnativeosscene::activeRoot(r)))return NO;
 return pmsecretcourse::launch(r,list.get(),chapter,door,tier,noPause);
}
