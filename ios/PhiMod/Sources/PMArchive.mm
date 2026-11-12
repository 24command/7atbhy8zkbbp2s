#import "PMArchive.h"
#include "../Vendor/miniz/miniz.h"
#include <set>
#include <algorithm>
#include <string>
static NSError*PMArchiveError(NSString*text){return [NSError errorWithDomain:@"PhiMod.Archive" code:1 userInfo:@{NSLocalizedDescriptionKey:text}];}
static NSArray<NSString*>*PMExtractArchiveImpl(NSString*archive,NSString*destination,NSUInteger maxEntries,unsigned long long maxUncompressed,unsigned long long maxFile,NSError**error){
 mz_zip_archive zip{};if(!mz_zip_reader_init_file(&zip,archive.fileSystemRepresentation,0)){if(error)*error=PMArchiveError(@"Unable to open ZIP / PEZ archive.");return nil;}
 NSMutableArray*files=[NSMutableArray new];NSFileManager*fm=NSFileManager.defaultManager;NSString*base=destination.stringByStandardizingPath;if(![fm createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:error]){mz_zip_reader_end(&zip);return nil;}std::set<std::string>seen;BOOL ok=YES;unsigned long long total=0;NSUInteger count=mz_zip_reader_get_num_files(&zip);if(count>maxEntries){if(error)*error=PMArchiveError(@"Archive entry count or expanded size exceeds safety limits.");ok=NO;}
 for(mz_uint i=0,n=(mz_uint)std::min<NSUInteger>(count,maxEntries);i<n&&ok;++i){mz_zip_archive_file_stat st{};if(!mz_zip_reader_file_stat(&zip,i,&st)){ok=NO;break;}
  NSString*name=[[NSString alloc]initWithUTF8String:st.m_filename];name=[name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
  if(!name.length||[name hasPrefix:@"/"]||[name containsString:@":"]){ok=NO;break;}
  for(NSString*part in name.pathComponents)if([part isEqualToString:@".."]){ok=NO;break;}
  if(!ok)break;
  NSString*path=[[base stringByAppendingPathComponent:name]stringByStandardizingPath];if(![path hasPrefix:[base stringByAppendingString:@"/"]]||!seen.insert(path.lowercaseString.UTF8String).second){ok=NO;break;}
  if(mz_zip_reader_is_file_a_directory(&zip,i)){ok=[fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:error];continue;}
  if(mz_zip_reader_is_file_encrypted(&zip,i)||!mz_zip_reader_is_file_supported(&zip,i)){ok=NO;break;}
  if(st.m_uncomp_size>maxFile||st.m_uncomp_size>maxUncompressed-total){if(error)*error=PMArchiveError(@"Archive entry exceeds the configured extraction limit.");ok=NO;break;}total+=st.m_uncomp_size;
  NSDictionary*space=[fm attributesOfFileSystemForPath:base error:nil];unsigned long long free=[space[NSFileSystemFreeSize] unsignedLongLongValue];if(st.m_uncomp_size>free-MIN(64ull*1024*1024,free)){if(error)*error=PMArchiveError(@"Insufficient free storage to extract archive.");ok=NO;break;}
  ok=[fm createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]&&mz_zip_reader_extract_to_file(&zip,i,path.fileSystemRepresentation,0);if(ok)[files addObject:path];
 }
 if(!ok&&error&&!*error)*error=PMArchiveError(@"Archive extraction failed: corrupt file, invalid path, or unsupported format.");mz_zip_reader_end(&zip);if(!ok)[fm removeItemAtPath:base error:nil];return ok?files:nil;
}
NSArray<NSString*>*PMExtractArchive(NSString*archive,NSString*destination,NSError**error){return PMExtractArchiveImpl(archive,destination,100000,1024ull*1024*1024,512ull*1024*1024,error);}
NSArray<NSString*>*PMExtractArchiveLimited(NSString*archive,NSString*destination,NSUInteger maxEntries,unsigned long long maxUncompressed,unsigned long long maxFile,NSError**error){return PMExtractArchiveImpl(archive,destination,maxEntries,maxUncompressed,maxFile,error);}
BOOL PMCreateArchive(NSString*folder,NSString*output,NSError**error){
 // NSURL enumeration may canonicalize /var to /private/var on Apple systems.
 // Derive archive-relative names from the same canonical root as enumerated URLs.
 folder=folder.stringByStandardizingPath.stringByResolvingSymlinksInPath;
 NSString*prefix=[folder stringByAppendingString:@"/"];
 mz_zip_archive zip{};if(!mz_zip_writer_init_file(&zip,output.fileSystemRepresentation,0)){if(error)*error=PMArchiveError(@"无法创建导出文件");return NO;}BOOL ok=YES;
 NSDirectoryEnumerator*entries=[NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:folder] includingPropertiesForKeys:@[NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
 NSMutableArray<NSURL*>*ordered=[NSMutableArray new];for(NSURL*url in entries)[ordered addObject:url];
 [ordered sortUsingComparator:^NSComparisonResult(NSURL*a,NSURL*b){BOOL am=[a.path isEqualToString:[folder stringByAppendingPathComponent:@"chapter.json"]],bm=[b.path isEqualToString:[folder stringByAppendingPathComponent:@"chapter.json"]];if(am!=bm)return am?NSOrderedAscending:NSOrderedDescending;return [a.path compare:b.path];}];
 for(NSURL*url in ordered){NSNumber*file=nil,*symlink=nil;[url getResourceValue:&file forKey:NSURLIsRegularFileKey error:nil];[url getResourceValue:&symlink forKey:NSURLIsSymbolicLinkKey error:nil];if(symlink.boolValue){ok=NO;break;}if(!file.boolValue)continue;NSString*path=url.path.stringByStandardizingPath.stringByResolvingSymlinksInPath;
 if(![path hasPrefix:prefix]){ok=NO;break;}
 NSString*name=[path substringFromIndex:prefix.length];if(!mz_zip_writer_add_file(&zip,name.UTF8String,url.fileSystemRepresentation,nullptr,0,MZ_BEST_SPEED)){ok=NO;break;}}
 if(ok)ok=mz_zip_writer_finalize_archive(&zip);mz_zip_writer_end(&zip);if(!ok&&error)*error=PMArchiveError(@"导出压缩包失败");return ok;
}
