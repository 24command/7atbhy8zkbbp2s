// Extra difficulties have logical names, not the native AT transport index.
// Mask only row labels/rating visuals; never edit saves, native chart arrays or locks.
namespace {
struct RowRatingBinding{uint32_t controller=0,object=0;bool masked=false,wasActive=false;};
struct ListRowBinding{uint32_t row=0,label=0;bool masked=false,wasActive=false;std::vector<RowRatingBinding>ratings;};
std::map<P,ListRowBinding>listRowBindings;
std::map<std::string,uint32_t>listRowRecords;NSUInteger listRowRecordRevision=NSUIntegerMax;NSString*listLogicalKey=nil;
void restoreRowMask(Runtime&r,ListRowBinding&binding){
 if(binding.masked){P label=target(r,binding.label);if(r.alive(label)){P object=r.call(label,"get_gameObject");r.call(object,"SetActive",{"System.Boolean"},{&binding.wasActive});}binding.masked=false;}
 for(auto&rating:binding.ratings)if(rating.masked){P object=target(r,rating.object);if(r.alive(object))r.call(object,"SetActive",{"System.Boolean"},{&rating.wasActive});rating.masked=false;}
}
void clearSelectorRowPresentation(Runtime&r){for(auto&entry:listRowBindings){auto&b=entry.second;restoreRowMask(r,b);for(auto&v:b.ratings){if(v.controller)r.gchandle_free(v.controller);r.gchandle_free(v.object);}r.gchandle_free(b.row);r.gchandle_free(b.label);}listRowBindings.clear();for(auto&record:listRowRecords)r.gchandle_free(record.second);listRowRecords.clear();listRowRecordRevision=NSUIntegerMax;listLogicalKey=nil;}
ListRowBinding&listRowBinding(Runtime&r,P row){
 auto found=listRowBindings.find(row);if(found!=listRowBindings.end())return found->second;
 ListRowBinding value;P label=r.get<P>(row,"difficulty");value.row=r.gchandle_new(row,false);value.label=r.gchandle_new(label,false);
 P controllers=r.children(r.call(row,"get_gameObject"),r.klass("RatingDisplayController"));
 for(uintptr_t i=0;controllers&&i<r.array_length(controllers);++i){P c=r.arrayAt(controllers,int(i));value.ratings.push_back({r.gchandle_new(c,false),r.gchandle_new(r.call(c,"get_gameObject"),false),false,false});}
 // Some native list prefabs store rating objects directly, without a
 // RatingDisplayController component. Probe only real fields with exact types.
 P type=r.object_get_class(row);
 auto addObject=[&](P object){if(!r.alive(object))return;for(auto&existing:value.ratings)if(target(r,existing.object)==object)return;value.ratings.push_back({0,r.gchandle_new(object,false),false,false});};
 for(const char*name:{"ratingObjects","ratings","rating"}){P field=r.class_get_field_from_name(type,name);if(!field||(r.field_get_flags(field)&0x10))continue;
  if(r.typeIs(r.field_get_type(field),"UnityEngine.GameObject[]")){P array=r.get<P>(row,name);for(uintptr_t i=0;array&&i<r.array_length(array);++i)addObject(r.arrayAt(array,int(i)));}
  else if(r.typeIs(r.field_get_type(field),"UnityEngine.GameObject"))addObject(r.get<P>(row,name));
 }
 return listRowBindings.emplace(row,std::move(value)).first->second;
}
void maskRow(Runtime&r,ListRowBinding&binding){
 bool no=false;P label=target(r,binding.label);if(r.alive(label)){P object=r.call(label,"get_gameObject");if(!binding.masked)binding.wasActive=r.unbox<bool>(r.call(object,"get_activeSelf"));binding.masked=true;r.call(object,"SetActive",{"System.Boolean"},{&no});}
 for(auto&rating:binding.ratings){P object=target(r,rating.object);if(!r.alive(object))continue;if(!rating.masked)rating.wasActive=r.unbox<bool>(r.call(object,"get_activeSelf"));rating.masked=true;r.call(object,"SetActive",{"System.Boolean"},{&no});}
}
void reconcileLogicalRows(Runtime&r,P selector){
 P items=r.call(selector,"get_SongItems");int count=r.count(items),slot=r.get<int>(selector,"nowLevel"),selected=r.get<int>(selector,"nowSong");if(slot<0||slot>3||selected<0||selected>=count)return;
 NSUInteger revision=PMContentStore.shared.revision;if(listRowRecordRevision!=revision){for(auto&record:listRowRecords)r.gchandle_free(record.second);listRowRecords.clear();listRowRecordRevision=revision;}
 P selectedItem=r.at(items,selected),selectedSong=r.get<P>(selectedItem,"songInfo");NSString*group=r.string(r.get<P>(selectedSong,"songsId"));NSDictionary*chosen=songFor(group,slot);
 NSString*extra=slot==3&&chosen&&PMStockDifficulty(chosen[@"level"])<0?PMDifficultyName(chosen[@"level"]):nil;
 NSString*logical=[NSString stringWithFormat:@"%@/%d/%d/%lu",extra?:@"native",slot,count,(unsigned long)revision];bool logicalChanged=![listLogicalKey isEqualToString:logical];listLogicalKey=logical;

 for(int i=0;i<count;++i){P item=r.at(items,i);if(logicalChanged)r.call(item,"SetText",{"System.Int32"},{&slot});P song=r.get<P>(item,"songInfo");NSString*id=r.string(r.get<P>(song,"songsId"));auto members=variants.find(id.UTF8String?:"");NSDictionary*chart=nil;bool present=false;
  if(extra){if(i==selected)chart=chosen;else{auto entries=extraDifficulties.find(id.UTF8String?:"");if(entries!=extraDifficulties.end())chart=PMMatchingExtraDifficulty(entries->second,extra);}present=chart!=nil;}
  else if(members!=variants.end()){if(slot==3&&extraDifficulties.count(id.UTF8String?:"")){auto at=stockAT.find(id.UTF8String);if(at!=stockAT.end())chart=at->second;}else if(members->second.count(slot))chart=members->second.at(slot);present=chart!=nil;}
  else{P values=r.get<P>(song,"difficulty");present=values&&uintptr_t(slot)<r.array_length(values)&&r.unbox<float>(r.arrayAt(values,slot))>0;}
  NSString*grade=chart?PMDifficultyText(chart):nil;P record=nullptr;
  if(chart){NSString*level=PMDifficultyRecordLevel(chart);std::string key=std::string([chart[@"id"]UTF8String])+"/"+level.UTF8String;auto saved=listRowRecords.find(key);if(saved==listRowRecords.end()){record=r.call(r.mainGame(),"GetSongRecord",{"System.String","System.String"},{r.managedString(chart[@"id"]),r.managedString(level)});saved=listRowRecords.emplace(key,r.gchandle_new(record,false)).first;}record=target(r,saved->second);
   P records=r.get<P>(item,"records");if(records&&slot<r.count(records)&&r.at(records,slot)!=record){r.call(records,"set_Item",{"System.Int32","LevelRecord"},{&slot,record});r.call(item,"SetText",{"System.Int32"},{&slot});}
  }
  else{P records=r.get<P>(item,"records");if(records&&slot<r.count(records))record=r.at(records,slot);}
  for(const char*field:{"selectorItemUpside","selectorItemDownside"}){P row=r.get<P>(item,field);if(!r.alive(row))continue;auto&binding=listRowBinding(r,row);if(!present){maskRow(r,binding);continue;}restoreRowMask(r,binding);
   P label=target(r,binding.label);if(grade&&r.alive(label)&&![r.string(r.call(label,"get_text"))isEqualToString:grade])r.call(label,"set_text",{"System.String"},{r.managedString(grade)});
   // Native item.SetText uses the refreshed per-chart record for both rating
   // implementations; never map rank letters ourselves or write saved scores.
  }
 }
}
}
void restoreSelectorRowVisibility(Runtime&r){for(auto&entry:listRowBindings)restoreRowMask(r,entry.second);}
