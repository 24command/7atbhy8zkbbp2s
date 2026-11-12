// Included inside PMContentStore implementation. Metadata travels with resources.
- (void)cleanupExports:(NSArray<NSURL*>*)urls{
 NSString*base=[[self.root stringByAppendingPathComponent:@"exports"]stringByResolvingSymlinksInPath];
 for(NSURL*url in urls){NSString*path=url.path.stringByResolvingSymlinksInPath;
  if([path.stringByDeletingLastPathComponent isEqualToString:base]&&[path.pathExtension.lowercaseString isEqualToString:@"zip"])[NSFileManager.defaultManager removeItemAtPath:path error:nil];
 }
}
- (NSString*)trashPath:(NSString*)token{
 if(![token isKindOfClass:NSString.class]||!token.length||![token isEqualToString:token.lastPathComponent]||[token isEqualToString:@"."]||[token isEqualToString:@".."])return nil;
 NSString*base=[[self.root stringByAppendingPathComponent:@"trash"]stringByResolvingSymlinksInPath],*path=[[base stringByAppendingPathComponent:token]stringByResolvingSymlinksInPath];
 return [path.stringByDeletingLastPathComponent isEqualToString:base]?path:nil;
}
- (NSArray<NSDictionary*>*)trashItems{
 NSMutableArray*out=[NSMutableArray new];NSFileManager*f=NSFileManager.defaultManager;
 for(NSString*token in [f contentsOfDirectoryAtPath:[self.root stringByAppendingPathComponent:@"trash"] error:nil]){
  NSString*folder=[self trashPath:token];BOOL dir=NO;if(!folder||![f fileExistsAtPath:folder isDirectory:&dir]||!dir)continue;
  NSData*bytes=[NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:@"trash-entry.json"]];id meta=bytes?[NSJSONSerialization JSONObjectWithData:bytes options:NSJSONReadingMutableContainers error:nil]:nil;
  if(![meta isKindOfClass:NSDictionary.class]){
   meta=@{};
   // Old releases moved folders without metadata; recover exact identity from
   // the last library backup when available, never invent difficulty/conditions.
   NSData*backup=[NSData dataWithContentsOfFile:[self.root stringByAppendingPathComponent:@"library.backup.json"]];id old=backup?[NSJSONSerialization JSONObjectWithData:backup options:0 error:nil]:nil;
   for(NSDictionary*song in [old isKindOfClass:NSDictionary.class]?old[@"songs"]:@[])if([token hasPrefix:[song[@"id"]stringByAppendingString:@"-"]]){
    NSMutableArray*chapters=[NSMutableArray new];for(NSDictionary*c in old[@"chapters"])if([c[@"songs"]containsObject:song[@"id"]])[chapters addObject:c[@"id"]];meta=@{@"song":song,@"chapters":chapters};writeJSON(meta,[folder stringByAppendingPathComponent:@"trash-entry.json"],nil);break;
   }
  }
  NSMutableDictionary*entry=[meta mutableCopy];entry[@"token"]=token;entry[@"title"]=entry[@"song"][@"title"]?:token;
  entry[@"restorable"]=@([entry[@"song"]isKindOfClass:NSDictionary.class]&&safeID(entry[@"song"][@"id"]));[out addObject:entry];
 }
 return out;
}
- (BOOL)removeSongs:(NSArray<NSString*>*)identifiers error:(NSError**)error{
 @synchronized(self){
 NSFileManager*f=NSFileManager.defaultManager;NSMutableDictionary*db=clone([self snapshot]);NSMutableArray*moved=[NSMutableArray new];NSMutableSet*wanted=[NSMutableSet new];
 for(NSString*id in identifiers){if(!safeID(id)){if(error)*error=err(@"Invalid chart ID");return NO;}[wanted addObject:id];}
 for(NSDictionary*song in [db[@"songs"]copy])if([wanted containsObject:song[@"id"]]){
  NSString*id=song[@"id"],*from=[self asset:id],*token=[id stringByAppendingFormat:@"-%@",NSUUID.UUID.UUIDString],*to=[self trashPath:token];
  NSMutableArray*members=[NSMutableArray new];for(NSDictionary*c in db[@"chapters"])if([c[@"songs"]containsObject:id])[members addObject:c[@"id"]];
  NSDictionary*meta=@{@"song":song,@"chapters":members,@"deletedAt":@(NSDate.timeIntervalSinceReferenceDate)};
  if(![f fileExistsAtPath:from]){if(error)*error=err(@"Chart resources missing; deletion cancelled");goto rollback;}
  if(!writeJSON(meta,[from stringByAppendingPathComponent:@"trash-entry.json"],error)||![f moveItemAtPath:from toPath:to error:error])goto rollback;
  [moved addObject:@{@"from":from,@"to":to}];[db[@"songs"]removeObject:song];
  for(NSMutableDictionary*c in db[@"chapters"])[c[@"songs"]removeObject:id];
  NSMutableDictionary*choices=db[@"chartSelections"];for(NSString*key in [choices.allKeys copy])if([choices[key]isEqual:id])[choices removeObjectForKey:key];
 }
 if([self commit:db error:error])return YES;
 rollback:for(NSDictionary*entry in moved.reverseObjectEnumerator)[f moveItemAtPath:entry[@"to"] toPath:entry[@"from"] error:nil];return NO;
 }
}
- (BOOL)restoreTrash:(NSString*)token error:(NSError**)error{
 @synchronized(self){
 NSString*folder=[self trashPath:token];if(!folder){if(error)*error=err(@"Invalid trash path");return NO;}
 NSData*data=[NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:@"trash-entry.json"]];NSDictionary*meta=data?[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:error]:nil;
 NSMutableDictionary*song=[meta[@"song"]mutableCopy];NSString*id=song[@"id"];
 if(!safeID(id)){if(error)*error=err(@"This older trash entry has no song metadata. Export its folder and reimport it to recover.");return NO;}
 NSMutableDictionary*db=clone([self snapshot]);for(NSDictionary*existing in db[@"songs"])if([existing[@"id"]isEqual:id]){if(error)*error=err(@"A chart with this ID already exists");return NO;}
 NSString*target=[self asset:id];NSFileManager*f=NSFileManager.defaultManager;if([f fileExistsAtPath:target]){if(error)*error=err(@"Chart resource destination already exists");return NO;}
 BOOL parentExists=NO;for(NSDictionary*c in db[@"chapters"])if([c[@"id"]isEqual:song[@"targetChapter"]])parentExists=YES;
 if(!parentExists)song[@"targetChapter"]=@"pm_local";
 for(NSMutableDictionary*c in db[@"chapters"])if([meta[@"chapters"]containsObject:c[@"id"]]||[c[@"id"]isEqual:song[@"targetChapter"]])if(![c[@"songs"]containsObject:id])[c[@"songs"]addObject:id];
 [db[@"songs"]addObject:song];if(![f moveItemAtPath:folder toPath:target error:error])return NO;
 if(![self commit:db error:error]){[f moveItemAtPath:target toPath:folder error:nil];return NO;}
 [f removeItemAtPath:[target stringByAppendingPathComponent:@"trash-entry.json"] error:nil];return YES;
 }
}
- (BOOL)deleteTrash:(NSString*)token error:(NSError**)error{NSString*path=[self trashPath:token];if(!path){if(error)*error=err(@"Invalid trash path");return NO;}return [NSFileManager.defaultManager removeItemAtPath:path error:error];}
