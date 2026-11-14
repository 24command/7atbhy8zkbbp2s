// Keep all native indexes in 0..3. Extra charts use AT as a transport slot;
// chart ID remains unique and the displayed name/color belongs to that chart.
struct DifficultyCell{P button=nullptr,label=nullptr,graphic=nullptr;uint32_t root=0;int entry=-1;};
std::vector<DifficultyCell>difficultyCells;
uint32_t difficultyOwner=0,difficultyItem=0,difficultyRoot=0;
NSString*difficultyGroup=nil;size_t difficultyPage=0;bool difficultyDirty=true;
std::vector<NSDictionary*>difficultyEntries;
struct FrozenDifficulty{uint32_t root;NSDictionary*chart;};std::vector<FrozenDifficulty>frozenDifficulties;
NSDictionary*frozenDifficulty(Runtime&r,P song){for(auto&v:frozenDifficulties)if(target(r,v.root)==song)return v.chart;return nil;}
P difficultyComponent(Runtime&r,P go,const char*ns,const char*name){return r.call(go,"AddComponent",{"System.Type"},{r.type_get_object(r.class_get_type(r.type(ns,name)))});}
P difficultyObject(Runtime&r,const char*name,P parent){P go=r.object_new(r.type("UnityEngine","GameObject"));uint32_t root=r.gchandle_new(go,false);try{r.call(go,".ctor",{"System.String"},{r.string_new(name)});P tr=difficultyComponent(r,go,"UnityEngine","RectTransform");bool no=false;r.call(tr,"SetParent",{"UnityEngine.Transform","System.Boolean"},{parent,&no});int layer=r.unbox<int>(r.call(r.call(parent,"get_gameObject"),"get_layer"));r.call(go,"set_layer",{"System.Int32"},{&layer});}catch(...){r.gchandle_free(root);throw;}r.gchandle_free(root);return go;}
bool hasDifficultyPager(P selector){return runtime&&target(*runtime,difficultyOwner)==selector&&difficultyGroup.length;}
void clearDifficultyPager(Runtime&r){P root=target(r,difficultyRoot);if(r.alive(root))r.stat(r.type("UnityEngine","Object"),"Destroy",{"UnityEngine.Object"},{root});for(auto&cell:difficultyCells)if(cell.root)r.gchandle_free(cell.root);difficultyCells.clear();for(uint32_t*handle:{&difficultyOwner,&difficultyItem,&difficultyRoot})if(*handle){r.gchandle_free(*handle);*handle=0;}difficultyEntries.clear();difficultyGroup=nil;difficultyPage=0;difficultyDirty=true;}
NSDictionary*selectedDifficulty(NSString*group,int slot){return songFor(group,slot);}
NSDictionary*difficultyForSong(Runtime&r,void*song,int slot){return frozenDifficulty(r,song)?:songFor(r.string(r.get<P>(song,"songsId")),slot);}
void bindTransport(Runtime&r,P selector,P item,NSString*group,NSDictionary*chart){
 auto&members=variants[group.UTF8String];members[3]=chart;
 P song=r.get<P>(item,"songInfo"),d=r.get<P>(song,"difficulty");float number=std::max(.1,PMDifficultyNumber(chart[@"difficulty"]));r.arrayPutFloat(d,3,number);
 pmunlock::difficultyChanged(r);recordSlot=-1;sparseSlot=-1;initializedSlot=-1;
 refreshVariantRecords(r,selector,item,group);
}
void rebuildDifficultyEntries(NSString*group){
 difficultyEntries.clear();auto&members=variants[group.UTF8String];
 for(int slot=0;slot<3;++slot)difficultyEntries.push_back(members.count(slot)?members[slot]:nil);
 auto at=stockAT.find(group.UTF8String);if(at!=stockAT.end())difficultyEntries.push_back(at->second);
 for(NSDictionary*chart:extraDifficulties[group.UTF8String])difficultyEntries.push_back(chart);
}
void prepareDifficultyGroup(Runtime&r,P selector){
 if(r.get<bool>(selector,"exit")||r.get<bool>(selector,"isMoving"))return;
 P items=r.call(selector,"get_SongItems");int index=r.get<int>(selector,"nowSong");if(index<0||index>=r.count(items))return;
 P item=r.at(items,index),song=r.get<P>(item,"songInfo");NSString*group=r.string(r.get<P>(song,"songsId"));
 auto extras=extraDifficulties.find(group.UTF8String?:"");
 if(extras==extraDifficulties.end()||extras->second.empty()){
  if(difficultyRoot){clearDifficultyPager(r);int in=2;r.put(selector,"nowLevel",in);r.call(selector,"SetLevel",{"System.Int32"},{&in});}
  return;
 }
 if(target(r,difficultyOwner)==selector&&target(r,difficultyItem)==item)return;
 clearDifficultyPager(r);difficultyOwner=r.gchandle_new(selector,false);difficultyItem=r.gchandle_new(item,false);difficultyGroup=group;
 rebuildDifficultyEntries(group);NSDictionary*first=pendingSong.length?variants[group.UTF8String][3]:extras->second.front();bindTransport(r,selector,item,group,first);
 size_t firstIndex=stockAT.count(group.UTF8String)?4:3;for(size_t i=0;i<difficultyEntries.size();++i)if(difficultyEntries[i]&&[difficultyEntries[i][@"id"]isEqualToString:first[@"id"]]){firstIndex=i;break;}difficultyPage=phimod::difficultyPageFor(firstIndex);
 int slot=3;r.put(selector,"nowLevel",slot);r.call(selector,"SetLevel",{"System.Int32"},{&slot});difficultyDirty=true;
}
DifficultyCell makeDifficultyCell(Runtime&r,P parent,P font,int entry){
 DifficultyCell c;c.entry=entry;P go=difficultyObject(r,"PhiMod Difficulty",parent);c.root=r.gchandle_new(go,false);
 P tr=r.call(go,"get_transform");c.graphic=difficultyComponent(r,go,"Lean.Gui","LeanPolygon");float fill=-1;r.call(c.graphic,"set_Thickness",{"System.Single"},{&fill});bool yes=true,no=false;
 P points=r.call(c.graphic,"get_Points");r.call(points,"Clear");struct Quad{float x,y,z,w;};for(Quad q: {Quad{0,0,0,0},Quad{12,0,0,1},Quad{0,0,1,1},Quad{-12,0,1,0}})r.call(points,"Add",{"UnityEngine.Vector4"},{&q});r.call(c.graphic,"SetVerticesDirty");
 r.call(c.graphic,"set_raycastTarget",{"System.Boolean"},{&yes});r.call(c.graphic,"set_maskable",{"System.Boolean"},{&no});
 c.button=difficultyComponent(r,go,"UnityEngine.UI","Button");r.call(c.button,"set_targetGraphic",{"UnityEngine.UI.Graphic"},{c.graphic});
 P caption=difficultyObject(r,"Caption",tr);c.label=difficultyComponent(r,caption,"UnityEngine.UI","Text");P labelTr=r.call(caption,"get_transform");V2 zero{0,0},one{1,1},pad{-10,-8};r.call(labelTr,"set_anchorMin",{"UnityEngine.Vector2"},{&zero});r.call(labelTr,"set_anchorMax",{"UnityEngine.Vector2"},{&one});r.call(labelTr,"set_sizeDelta",{"UnityEngine.Vector2"},{&pad});r.call(labelTr,"set_anchoredPosition",{"UnityEngine.Vector2"},{&zero});
 r.call(c.label,"set_font",{"UnityEngine.Font"},{font});int size=24,center=4;r.call(c.label,"set_fontSize",{"System.Int32"},{&size});r.call(c.label,"set_alignment",{"UnityEngine.TextAnchor"},{&center});r.call(c.label,"set_raycastTarget",{"System.Boolean"},{&no});r.call(c.label,"set_maskable",{"System.Boolean"},{&no});
 Color white{1,1,1,1};r.call(c.label,"set_color",{"UnityEngine.Color"},{&white});return c;
}
void difficultyPager(Runtime&r,P selector){
 if(target(r,difficultyOwner)!=selector||!difficultyGroup.length)return;
 P item=target(r,difficultyItem),bar=r.get<P>(selector,"levelBarController"),infos=r.get<P>(bar,"levelInfos"),slider=r.get<P>(selector,"levelSliderController");
 if(!r.alive(item)||!r.alive(bar))return;
 if(!difficultyRoot){P parent=r.get<P>(bar,"selectorPanel"),go=difficultyObject(r,"PhiMod Difficulty Pages",parent);difficultyRoot=r.gchandle_new(go,false);P overlayGroup=difficultyComponent(r,go,"UnityEngine","CanvasGroup");bool yes=true;r.call(overlayGroup,"set_ignoreParentGroups",{"System.Boolean"},{&yes});r.call(overlayGroup,"set_interactable",{"System.Boolean"},{&yes});r.call(overlayGroup,"set_blocksRaycasts",{"System.Boolean"},{&yes});P tr=r.call(go,"get_transform"),tip=r.get<P>(r.arrayAt(infos,0),"level"),font=r.call(tip,"get_font");
  V2 center{.5f,.5f},size{520,94},zero{0,0};r.call(tr,"set_anchorMin",{"UnityEngine.Vector2"},{&center});r.call(tr,"set_anchorMax",{"UnityEngine.Vector2"},{&center});r.call(tr,"set_sizeDelta",{"UnityEngine.Vector2"},{&size});r.call(tr,"set_anchoredPosition",{"UnityEngine.Vector2"},{&zero});
  for(int i=0;i<6;++i)difficultyCells.push_back(makeDifficultyCell(r,tr,font,i));difficultyDirty=true;
 }
 bool no=false;for(uintptr_t i=0;i<r.array_length(infos);++i)r.call(r.arrayAt(infos,int(i)),"SetActive",{"System.Boolean"},{&no});r.call(slider,"Hide");
 // No global colors/materials/transforms are changed, including RPE HUD/shader bindings.
 int slot=r.get<int>(selector,"nowLevel");NSDictionary*current=variants[difficultyGroup.UTF8String].count(slot)?variants[difficultyGroup.UTF8String][slot]:nil;static NSString*lastChart=nil;static int lastSlot=-1;if(!difficultyDirty&&lastSlot==slot&&[lastChart isEqualToString:current[@"id"]])return;lastSlot=slot;lastChart=current[@"id"];size_t count=phimod::difficultyPageSize(difficultyEntries.size(),difficultyPage);
 P colors=r.get<P>(slider,"levelColor");Color at=r.unbox<Color>(r.arrayAt(colors,3));
 for(int i=0;i<6;++i){auto&c=difficultyCells[i];bool previous=i==4,next=i==5;size_t entry=difficultyPage*4+i;bool show=previous?phimod::difficultyPrevious(difficultyPage):next?phimod::difficultyNext(difficultyEntries.size(),difficultyPage):size_t(i)<count;
  P go=target(r,c.root);r.call(go,"SetActive",{"System.Boolean"},{&show});if(!show)continue;
  NSDictionary*chart=previous||next?nil:difficultyEntries[entry];NSString*name=previous?@"←":next?@"→":chart?PMDifficultyName(chart[@"level"]):@[@"EZ",@"HD",@"IN"][entry];
  NSString*text=previous||next?name:[NSString stringWithFormat:@"%@\n%@",name,chart?PMDifficultyText(chart):@"—"];
  if(![r.string(r.call(c.label,"get_text"))isEqualToString:text])r.call(c.label,"set_text",{"System.String"},{r.managedString(text)});
  bool selected=chart&&chart==current;bool enabled=previous||next||(chart&&!selected);r.call(c.button,"set_interactable",{"System.Boolean"},{&enabled});
  Color color{.12f,.13f,.16f,.92f};if(selected){int stock=PMStockDifficulty(chart[@"level"]);color=stock>=0?r.unbox<Color>(r.arrayAt(colors,stock)):at;NSArray*rgb=PMDifficultyRGB(chart[@"difficultyRGB"]?:@"");if(rgb.count==3){color.r=[rgb[0]floatValue]/255.f;color.g=[rgb[1]floatValue]/255.f;color.b=[rgb[2]floatValue]/255.f;}}r.call(c.graphic,"set_color",{"UnityEngine.Color"},{&color});
  P tr=r.call(go,"get_transform");V2 size{previous||next?44.f:96.f,78},pos{previous?-float(count)*50-28:next?float(count)*50+28:(float(i)-float(count-1)*.5f)*100,0};r.call(tr,"set_sizeDelta",{"UnityEngine.Vector2"},{&size});r.call(tr,"set_anchoredPosition",{"UnityEngine.Vector2"},{&pos});
 }
 if(current){P label=r.get<P>(selector,"level");if(r.alive(label))r.call(label,"set_text",{"System.String"},{r.managedString(PMDifficultyName(current[@"level"]))});P number=r.get<P>(selector,"difficulty");if(r.alive(number))r.call(number,"set_text",{"System.String"},{r.managedString(PMDifficultyText(current))});}
 difficultyDirty=false;
}
bool ownsDifficultyButton(void*button){for(auto&c:difficultyCells)if(c.button==button)return true;return false;}
bool pressDifficultyButton(Runtime&r,void*button){
 if(!ownsDifficultyButton(button))return false;if(!r.unbox<bool>(r.call(button,"IsActive"))||!r.unbox<bool>(r.call(button,"IsInteractable")))return true;
 P selector=target(r,difficultyOwner),item=target(r,difficultyItem);if(!r.alive(selector)||!r.alive(item))return true;
 for(auto&c:difficultyCells)if(c.button==button){if(c.entry==4){if(difficultyPage)--difficultyPage;}else if(c.entry==5){if(phimod::difficultyNext(difficultyEntries.size(),difficultyPage))++difficultyPage;}else{
  freezeChallengeDifficulties(r);size_t index=difficultyPage*4+c.entry;if(index>=difficultyEntries.size())return true;NSDictionary*chart=difficultyEntries[index];if(!chart)return true;int slot=PMStockDifficulty(chart[@"level"]);if(slot<0||slot==3){bindTransport(r,selector,item,difficultyGroup,chart);slot=3;}
  r.put(selector,"nowLevel",slot);r.call(selector,"SetLevel",{"System.Int32"},{&slot});recordSlot=-1;sparseSlot=-1;
 }difficultyDirty=true;break;}return true;
}
void difficultySelectorOff(Runtime&r){
 if(difficultyOwner){P owner=target(r,difficultyOwner);if(r.alive(owner)){int in=2;r.put(owner,"nowLevel",in);}}
 clearDifficultyPager(r);
}
void freezeChallengeDifficulties(Runtime&r){
 P owner=target(r,difficultyOwner);if(!r.alive(owner))return;P controller=r.get<P>(owner,"challengeSongSelectorControl");if(!r.alive(controller))return;P queue=r.get<P>(controller,"challengeSongItems");
 std::set<P>queuedSongs;for(int i=0,n=r.count(queue);i<n;++i){P item=r.get<P>(r.at(queue,i),"songInfo");queuedSongs.insert(r.get<P>(item,"songInfo"));}
 for(auto it=frozenDifficulties.begin();it!=frozenDifficulties.end();){if(!queuedSongs.count(target(r,it->root))){r.gchandle_free(it->root);it=frozenDifficulties.erase(it);}else ++it;}
 for(int i=0,n=r.count(queue);i<n;++i){P entry=r.at(queue,i),item=r.get<P>(entry,"songInfo"),song=r.get<P>(item,"songInfo");int slot=r.get<int>(entry,"levelIndex");NSString*group=r.string(r.get<P>(song,"songsId"));if(r.get<int>(item,"sortIndex")==-2147483000)continue;NSDictionary*chart=songFor(group,slot);if(!chart||[chart[@"pmOfficial"]boolValue])continue;
  // Snapshot the chosen chart so later page changes cannot alter a queued course.
  P copy=r.call(item,"MemberwiseClone"),songCopy=r.call(song,"MemberwiseClone");uint32_t root=r.gchandle_new(copy,false),songRoot=r.gchandle_new(songCopy,false);
  try{r.put(songCopy,"songsId",r.managedString(chart[@"id"]));P numbers=r.get<P>(song,"difficulty"),cloned=r.call(numbers,"Clone");r.put(songCopy,"difficulty",cloned);float number=PMDifficultyNumber(chart[@"difficulty"]);r.arrayPutFloat(cloned,slot,number);r.put(copy,"sortIndex",-2147483000);r.put(copy,"songInfo",songCopy);r.put(entry,"songInfo",copy);frozenDifficulties.push_back({r.gchandle_new(songCopy,false),chart});}catch(...){r.gchandle_free(root);r.gchandle_free(songRoot);throw;}r.gchandle_free(root);r.gchandle_free(songRoot);
 }
}
static NSString*difficultyLabeledID=nil;
void difficultyGameplayLabel(Runtime&r,void*progress){
 if([difficultyLabeledID isEqualToString:levelID])return;
 if(!levelID.length)return;NSDictionary*chart=nil;for(NSDictionary*s in [PMContentStore.shared snapshot][@"songs"])if([s[@"id"]isEqualToString:levelID]){chart=s;break;}if(!chart)return;
 // Only replace Text content once after native Start. RPE owns subsequent geometry/colors.
 P level=target(r,hudLevel);if(!r.alive(level))return;P ui=r.get<P>(level,"levelUICont"),go=r.get<P>(ui,"songsLevel"),texts=r.children(go,r.type("UnityEngine.UI","Text"));
 NSString*caption=[NSString stringWithFormat:@"%@  %@",PMDifficultyName(chart[@"level"]),PMDifficultyText(chart)];if(texts&&r.array_length(texts)){r.call(r.arrayAt(texts,0),"set_text",{"System.String"},{r.managedString(caption)});difficultyLabeledID=levelID;}(void)progress;
}
