// Compact only the new import's owned folder. Keep one source chart for future
// conversion, plus runtime charts. Never sweep arbitrary JSON/media resources.
NSDictionary*compactImportedSong(NSString*folder,NSString*chartSource,NSString*musicSource,NSDictionary*chart,NSDictionary*entityInfo,NSError**error){
 NSFileManager*f=NSFileManager.defaultManager;NSString*base=folder.stringByStandardizingPath.stringByResolvingSymlinksInPath;
 NSString*prefix=[base stringByAppendingString:@"/"];NSMutableArray*candidates=[NSMutableArray new];
 auto contained=[&](NSString*path){NSString*resolved=path.stringByStandardizingPath.stringByResolvingSymlinksInPath;return [resolved hasPrefix:prefix];};
 NSString*format=chart[@"pmFormat"],*canonicalChart=@"chart.json";
 if([format isEqualToString:@"RPE"])canonicalChart=@"source.rpe.json";else if([format isEqualToString:@"PEC"])canonicalChart=@"source.pec";
 NSString*keptChart=[base stringByAppendingPathComponent:canonicalChart];
 if(![canonicalChart isEqualToString:@"chart.json"]){
  if(![f fileExistsAtPath:keptChart]){if(error)*error=err(@"Canonical source chart missing; import cleanup cancelled");return nil;}
  if([canonicalChart hasSuffix:@"json"]){NSData*bytes=[NSData dataWithContentsOfFile:keptChart];id object=bytes?[NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil]:nil;if(!object||!writeJSONCompact(object,keptChart,error))return nil;}
 }
 NSString*sourceCandidate=contained(chartSource)?chartSource:[base stringByAppendingPathComponent:chartSource.lastPathComponent];
 if(contained(sourceCandidate)&&![sourceCandidate.lastPathComponent isEqualToString:canonicalChart]&&![sourceCandidate.lastPathComponent isEqualToString:@"chart.json"]&&![sourceCandidate.lastPathComponent isEqualToString:@"chart-native.json"]&&[f fileExistsAtPath:sourceCandidate]){
  NSData*a=[NSData dataWithContentsOfFile:sourceCandidate options:NSDataReadingMappedIfSafe error:nil],*b=[NSData dataWithContentsOfFile:keptChart options:NSDataReadingMappedIfSafe error:nil];
  BOOL same=[a isEqualToData:b];if(!same&&[sourceCandidate.pathExtension.lowercaseString isEqualToString:@"json"]){id x=a?[NSJSONSerialization JSONObjectWithData:a options:0 error:nil]:nil,y=b?[NSJSONSerialization JSONObjectWithData:b options:0 error:nil]:nil;same=x&&y&&[x isEqual:y];}
  if(same)[candidates addObject:sourceCandidate];
 }
 NSString*audioMetaPath=[base stringByAppendingPathComponent:@"source-audio.json"];NSData*audioData=[NSData dataWithContentsOfFile:audioMetaPath];id meta=audioData?[NSJSONSerialization JSONObjectWithData:audioData options:0 error:nil]:nil;
 NSString*canonicalMusic=[meta isKindOfClass:NSDictionary.class]&&[meta[@"file"]isKindOfClass:NSString.class]?meta[@"file"]:nil;
 if(!canonicalMusic.length||![canonicalMusic isEqualToString:canonicalMusic.lastPathComponent]||![f fileExistsAtPath:[base stringByAppendingPathComponent:canonicalMusic]])canonicalMusic=nil;
 NSString*musicCandidate=contained(musicSource)?musicSource:[base stringByAppendingPathComponent:musicSource.lastPathComponent];
 BOOL pcm=[musicSource.pathExtension.lowercaseString isEqualToString:@"pcm"];
 if(pcm){
  AVAudioFile*check=[[AVAudioFile alloc]initForReading:[NSURL fileURLWithPath:[base stringByAppendingPathComponent:@"music.m4a"]] error:error];if(!check||check.length<=0)return nil;
  if(canonicalMusic&&[canonicalMusic.pathExtension.lowercaseString isEqualToString:@"pcm"]){[candidates addObject:[base stringByAppendingPathComponent:canonicalMusic]];canonicalMusic=nil;}
  if(contained(musicCandidate)&&[f fileExistsAtPath:musicCandidate])[candidates addObject:musicCandidate];
  if(!canonicalMusic&&[f fileExistsAtPath:audioMetaPath]&&![f removeItemAtPath:audioMetaPath error:error])return nil;
 }
 if(!canonicalMusic)canonicalMusic=@"music.m4a";
 if(!pcm&&![musicCandidate.lastPathComponent isEqualToString:canonicalMusic]&&![musicCandidate.lastPathComponent isEqualToString:@"music.m4a"]&&contained(musicCandidate)&&[f fileExistsAtPath:musicCandidate]){
  NSData*a=[NSData dataWithContentsOfFile:musicCandidate options:NSDataReadingMappedIfSafe error:nil],*b=[NSData dataWithContentsOfFile:[base stringByAppendingPathComponent:canonicalMusic] options:NSDataReadingMappedIfSafe error:nil];if(a&&[a isEqualToData:b])[candidates addObject:musicCandidate];
 }
 // References from chart data, unlock metadata or extension text make a file
 // ineligible for deletion even when it is also a redundant import source.
 NSMutableString*references=[NSMutableString new];for(id object in @[chart,entityInfo?:@{}]){NSData*d=[NSJSONSerialization dataWithJSONObject:object options:0 error:nil];if(d)[references appendString:[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding]?:@""];}
 for(NSString*rel in [f subpathsOfDirectoryAtPath:[base stringByAppendingPathComponent:@"extensions"] error:nil])if([@[@"json",@"tsv",@"txt",@"yml",@"yaml",@"glsl"]containsObject:rel.pathExtension.lowercaseString]){NSString*text=[NSString stringWithContentsOfFile:[[base stringByAppendingPathComponent:@"extensions"]stringByAppendingPathComponent:rel] encoding:NSUTF8StringEncoding error:nil];if(text)[references appendString:text];}
 unsigned long long removed=0;for(NSString*path in [NSSet setWithArray:candidates]){
  if(!contained(path)||[references containsString:path.lastPathComponent])continue;
  NSNumber*size=[f attributesOfItemAtPath:path error:nil][NSFileSize];if([f fileExistsAtPath:path]&&![f removeItemAtPath:path error:error])return nil;removed+=size.unsignedLongLongValue;
 }
 PMDiagnosticsWrite([NSString stringWithFormat:@"Content compacted import: removed=%llu bytes sourceChart=%@ sourceMusic=%@",removed,canonicalChart,canonicalMusic].UTF8String);
 return @{@"sourceChart":canonicalChart,@"sourceMusic":canonicalMusic};
}
