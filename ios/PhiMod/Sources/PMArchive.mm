#import "PMArchive.h"
#include "../Vendor/miniz/miniz.h"
#include <set>
#include <string>
static NSError*PMArchiveError(NSString*text){return [NSError errorWithDomain:@"PhiMod.Archive" code:1 userInfo:@{NSLocalizedDescriptionKey:text}];}
NSArray<NSString*>*PMExtractArchive(NSString*archive,NSString*destination,NSError**error){
 mz_zip_archive zip{};if(!mz_zip_reader_init_file(&zip,archive.fileSystemRepresentation,0)){if(error)*error=PMArchiveError(@"无法打开 ZIP / PEZ 谱包");return nil;}
 NSMutableArray*files=[NSMutableArray new];NSFileManager*fm=NSFileManager.defaultManager;NSString*base=destination.stringByStandardizingPath;if(![fm createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:error]){mz_zip_reader_end(&zip);return nil;}std::set<std::string>seen;BOOL ok=YES;
 for(mz_uint i=0,n=mz_zip_reader_get_num_files(&zip);i<n&&ok;++i){mz_zip_archive_file_stat st{};if(i>=100000||!mz_zip_reader_file_stat(&zip,i,&st)){ok=NO;break;}
  NSString*name=[[NSString alloc]initWithUTF8String:st.m_filename];name=[name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
  if(!name.length||[name hasPrefix:@"/"]||[name containsString:@":"]){ok=NO;break;}
  for(NSString*part in name.pathComponents)if([part isEqualToString:@".."]){ok=NO;break;}
  if(!ok)break;
  NSString*path=[[base stringByAppendingPathComponent:name]stringByStandardizingPath];if(![path hasPrefix:[base stringByAppendingString:@"/"]]||!seen.insert(path.lowercaseString.UTF8String).second){ok=NO;break;}
  if(mz_zip_reader_is_file_a_directory(&zip,i)){ok=[fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:error];continue;}
  if(mz_zip_reader_is_file_encrypted(&zip,i)||!mz_zip_reader_is_file_supported(&zip,i)){ok=NO;break;}
  NSDictionary*space=[fm attributesOfFileSystemForPath:base error:nil];if(st.m_uncomp_size>[space[NSFileSystemFreeSize] unsignedLongLongValue]-MIN(64ull*1024*1024,[space[NSFileSystemFreeSize] unsignedLongLongValue])){if(error)*error=PMArchiveError(@"剩余空间不足");ok=NO;break;}
  ok=[fm createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]&&mz_zip_reader_extract_to_file(&zip,i,path.fileSystemRepresentation,0);if(ok)[files addObject:path];
 }
 if(!ok&&error&&!*error)*error=PMArchiveError(@"谱包解压失败：文件损坏、路径无效或格式不支持");mz_zip_reader_end(&zip);return ok?files:nil;
}
BOOL PMCreateArchive(NSString*folder,NSString*output,NSError**error){
 mz_zip_archive zip{};if(!mz_zip_writer_init_file(&zip,output.fileSystemRepresentation,0)){if(error)*error=PMArchiveError(@"无法创建导出文件");return NO;}BOOL ok=YES;
 NSDirectoryEnumerator*entries=[NSFileManager.defaultManager enumeratorAtURL:[NSURL fileURLWithPath:folder] includingPropertiesForKeys:@[NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
 for(NSURL*url in entries){NSNumber*file=nil,*symlink=nil;[url getResourceValue:&file forKey:NSURLIsRegularFileKey error:nil];[url getResourceValue:&symlink forKey:NSURLIsSymbolicLinkKey error:nil];if(symlink.boolValue){ok=NO;break;}if(!file.boolValue)continue;NSString*name=[url.path substringFromIndex:folder.length+1];if(!mz_zip_writer_add_file(&zip,name.UTF8String,url.fileSystemRepresentation,nullptr,0,MZ_BEST_SPEED)){ok=NO;break;}}
 if(ok)ok=mz_zip_writer_finalize_archive(&zip);mz_zip_writer_end(&zip);if(!ok&&error)*error=PMArchiveError(@"导出压缩包失败");return ok;
}
