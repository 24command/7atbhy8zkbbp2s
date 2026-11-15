#import "PMArchive.h"
#include "../Vendor/miniz/miniz.h"
#include <set>
#include <algorithm>
#include <string>
static NSError*PMArchiveError(NSString*text){return [NSError errorWithDomain:@"PhiMod.Archive" code:1 userInfo:@{NSLocalizedDescriptionKey:text}];}
static NSArray<NSString*>*PMExtractArchiveImpl(NSString*archive,NSString*destination,NSUInteger maxEntries,unsigned long long maxUncompressed,unsigned long long maxFile,NSError**error){
 mz_zip_archive zip{};if(!mz_zip_reader_init_file(&zip,archive.fileSystemRepresentation,0)){if(error)*error=PMArchiveError(@"Unable to open ZIP / PEZ archive.");return nil;}
 NSError*failure=nil;
 NSMutableArray*files=[NSMutableArray new];NSFileManager*fm=NSFileManager.defaultManager;NSString*base=destination.stringByStandardizingPath;if(![fm createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:error]){mz_zip_reader_end(&zip);return nil;}std::set<std::string>seen;BOOL ok=YES;unsigned long long total=0;NSUInteger count=mz_zip_reader_get_num_files(&zip);if(count>maxEntries){if(error)*error=PMArchiveError(@"Archive entry count or expanded size exceeds safety limits.");ok=NO;}
 for(mz_uint i=0,n=(mz_uint)std::min<NSUInteger>(count,maxEntries);i<n&&ok;++i){@autoreleasepool{mz_zip_archive_file_stat st{};if(!mz_zip_reader_file_stat(&zip,i,&st)){ok=NO;break;}
  NSString*name=[[NSString alloc]initWithUTF8String:st.m_filename];name=[name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
  if(!name.length||[name hasPrefix:@"/"]||[name containsString:@":"]){ok=NO;break;}
  for(NSString*part in name.pathComponents)if([part isEqualToString:@".."]){ok=NO;break;}
  if(!ok)break;
  NSString*path=[[base stringByAppendingPathComponent:name]stringByStandardizingPath];if(![path hasPrefix:[base stringByAppendingString:@"/"]]||!seen.insert(path.lowercaseString.UTF8String).second){ok=NO;break;}
  if(mz_zip_reader_is_file_a_directory(&zip,i)){ok=[fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&failure];continue;}
  if(mz_zip_reader_is_file_encrypted(&zip,i)||!mz_zip_reader_is_file_supported(&zip,i)){ok=NO;break;}
  if(st.m_uncomp_size>maxFile||st.m_uncomp_size>maxUncompressed-total){failure=PMArchiveError(@"Archive entry exceeds the configured extraction limit.");ok=NO;break;}total+=st.m_uncomp_size;
  NSDictionary*space=[fm attributesOfFileSystemForPath:base error:nil];unsigned long long free=[space[NSFileSystemFreeSize] unsignedLongLongValue];if(st.m_uncomp_size>free-MIN(64ull*1024*1024,free)){failure=PMArchiveError(@"Insufficient free storage to extract archive.");ok=NO;break;}
  ok=[fm createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&failure]&&mz_zip_reader_extract_to_file(&zip,i,path.fileSystemRepresentation,0);if(ok)[files addObject:path];
 }}
 if(!ok&&error&&failure)*error=failure;
 if(!ok&&error&&!*error)*error=PMArchiveError(@"Archive extraction failed: corrupt file, invalid path, or unsupported format.");mz_zip_reader_end(&zip);if(!ok)[fm removeItemAtPath:base error:nil];return ok?files:nil;
}
NSArray<NSString*>*PMExtractArchive(NSString*archive,NSString*destination,NSError**error){return PMExtractArchiveImpl(archive,destination,100000,1024ull*1024*1024,512ull*1024*1024,error);}
NSArray<NSString*>*PMExtractArchiveLimited(NSString*archive,NSString*destination,NSUInteger maxEntries,unsigned long long maxUncompressed,unsigned long long maxFile,NSError**error){return PMExtractArchiveImpl(archive,destination,maxEntries,maxUncompressed,maxFile,error);}
BOOL PMCreateArchive(NSString*folder,NSString*output,NSError**error){
 folder=folder.stringByStandardizingPath.stringByResolvingSymlinksInPath;
 NSString*prefix=[folder stringByAppendingString:@"/"];
 // Publish only a finalized archive; failed exports never leave a corrupt shareable ZIP.
 NSString*temporary=[output stringByAppendingFormat:@".%@.partial",NSUUID.UUID.UUIDString];
 mz_zip_archive zip{};if(!mz_zip_writer_init_file(&zip,temporary.fileSystemRepresentation,0)){if(error)*error=PMArchiveError(@"Unable to create export archive");return NO;}
 BOOL ok=YES;NSFileManager*fm=NSFileManager.defaultManager;
 @try{
  __block NSError*scanError=nil;
  NSDirectoryEnumerator*entries=[fm enumeratorAtURL:[NSURL fileURLWithPath:folder] includingPropertiesForKeys:@[NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:^BOOL(NSURL*url,NSError*failure){scanError=failure;return NO;}];
  NSMutableArray<NSURL*>*ordered=[NSMutableArray new];for(NSURL*url in entries)[ordered addObject:url];
  if(!entries||scanError){ok=NO;if(error)*error=scanError?:PMArchiveError(@"Unable to enumerate export assets");}
  NSString*manifest=[folder stringByAppendingPathComponent:@"chapter.json"];
  [ordered sortUsingComparator:^NSComparisonResult(NSURL*a,NSURL*b){BOOL am=[a.path isEqualToString:manifest],bm=[b.path isEqualToString:manifest];if(am!=bm)return am?NSOrderedAscending:NSOrderedDescending;return [a.path compare:b.path];}];
  NSSet*encoded=[NSSet setWithArray:@[@"zip",@"pez",@"png",@"jpg",@"jpeg",@"webp",@"gif",@"mp3",@"ogg",@"m4a",@"mp4",@"mov",@"flac"]];
  for(NSURL*url in ordered){if(!ok)break;@autoreleasepool{
   NSNumber*file=nil,*symlink=nil;
   if(![url getResourceValue:&file forKey:NSURLIsRegularFileKey error:nil]||![url getResourceValue:&symlink forKey:NSURLIsSymbolicLinkKey error:nil]||symlink.boolValue){ok=NO;continue;}
   if(!file.boolValue)continue;NSString*path=url.path.stringByStandardizingPath.stringByResolvingSymlinksInPath;
   if(![path hasPrefix:prefix]){ok=NO;continue;}
   NSString*name=[path substringFromIndex:prefix.length];
   // Encoded media is already compressed; retain fast deflate for JSON/TSV/PCM.
   mz_uint level=[encoded containsObject:path.pathExtension.lowercaseString]?MZ_NO_COMPRESSION:MZ_BEST_SPEED;
   ok=mz_zip_writer_add_file(&zip,name.UTF8String,url.fileSystemRepresentation,nullptr,0,level);
  }}
  if(ok)ok=mz_zip_writer_finalize_archive(&zip);
 }@catch(NSException*exception){ok=NO;if(error)*error=PMArchiveError(exception.reason);}
 @finally{mz_zip_writer_end(&zip);}
 if(ok){
  if([fm fileExistsAtPath:output])ok=[fm replaceItemAtURL:[NSURL fileURLWithPath:output] withItemAtURL:[NSURL fileURLWithPath:temporary] backupItemName:nil options:0 resultingItemURL:nil error:error];
  else ok=[fm moveItemAtPath:temporary toPath:output error:error];
 }
 if(!ok){[fm removeItemAtPath:temporary error:nil];if(error&&!*error)*error=PMArchiveError(@"Export failed; check free storage and asset files");}
 return ok;
}
