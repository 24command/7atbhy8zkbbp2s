#import "PMArchive.h"
#include "../Vendor/miniz/miniz.h"
#include <set>
#include <algorithm>
#include <string>
#include <cerrno>
#include <cstdio>
static NSError*PMArchiveError(NSString*text){return [NSError errorWithDomain:@"PhiMod.Archive" code:1 userInfo:@{NSLocalizedDescriptionKey:text}];}
static constexpr unsigned long long GiB = 1ull << 30;
static constexpr unsigned long long chartTotalLimit = 16 * GiB, chartFileLimit = 8 * GiB;

struct ExtractionWriter {
 FILE *file = nullptr;
 __unsafe_unretained NSURL *source = nil;
 mz_uint64 before = 0, offset = 0, expected = 0, total = 0, nextReport = 0;
 double lastReport = 0;
};
static void reportBytes(ExtractionWriter &writer, mz_uint64 done) {
 if (writer.source) [[NSNotificationCenter defaultCenter] postNotificationName:@"PMChartImportBytes" object:writer.source
  userInfo:@{@"done":@(done), @"total":@(writer.total)}];
}
static size_t writeExtracted(void *context, mz_uint64 offset, const void *bytes, size_t length) {
 auto &w = *static_cast<ExtractionWriter *>(context);
 if (offset != w.offset || length > w.expected - w.offset) return 0;
 const size_t written = fwrite(bytes,1,length,w.file);
 w.offset += written;
 const auto done = w.before + w.offset;
 if (w.source && done >= w.nextReport && done < w.total) {
  w.nextReport = done + (256ull << 10);
  const double now = NSDate.timeIntervalSinceReferenceDate;
  if (now - w.lastReport >= .12) { reportBytes(w,done); w.lastReport = now; }
 }
 return written;
}
static NSArray<NSString*>*PMExtractArchiveImpl(NSString*archive,NSString*destination,NSUInteger maxEntries,unsigned long long maxUncompressed,unsigned long long maxFile,NSError**error,NSURL *source=nil){
 mz_zip_archive zip{};if(!mz_zip_reader_init_file(&zip,archive.fileSystemRepresentation,0)){if(error)*error=PMArchiveError(@"Unable to open ZIP / PEZ archive.");return nil;}
 NSError*failure=nil;
 NSMutableArray*files=[NSMutableArray new];NSFileManager*fm=NSFileManager.defaultManager;NSString*base=destination.stringByStandardizingPath;if(![fm createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:error]){mz_zip_reader_end(&zip);return nil;}
 std::set<std::string>seen;BOOL ok=YES;unsigned long long spaceBudget=0,bytesSinceSpaceCheck=0;NSUInteger filesSinceSpaceCheck=256;
 NSUInteger count=mz_zip_reader_get_num_files(&zip);
 ExtractionWriter writer; writer.source=source;
 if(count>maxEntries){failure=PMArchiveError(@"压缩包中的文件数量超过上限。");ok=NO;}
 for(mz_uint i=0;ok && i<count;++i){
  mz_zip_archive_file_stat st{};
  if(!mz_zip_reader_file_stat(&zip,i,&st)){ok=NO;break;}
  if(st.m_is_directory)continue;
  if(st.m_uncomp_size>maxFile || st.m_uncomp_size>maxUncompressed-writer.total){
   failure=PMArchiveError([NSString stringWithFormat:@"解压数据超过安全上限（单文件 %@，整包 %@）。",[NSByteCountFormatter stringFromByteCount:maxFile countStyle:NSByteCountFormatterCountStyleBinary],[NSByteCountFormatter stringFromByteCount:maxUncompressed countStyle:NSByteCountFormatterCountStyleBinary]]);ok=NO;break;
  }
  writer.total+=st.m_uncomp_size;
 }
 if(ok){
  NSDictionary*space=[fm attributesOfFileSystemForPath:base error:&failure];
  unsigned long long free=[space[NSFileSystemFreeSize] unsignedLongLongValue];
  if(!space)ok=NO;
  else if(writer.total>free-MIN(64ull*1024*1024,free)){failure=PMArchiveError(@"设备剩余空间不足，无法解压整个文件包。");ok=NO;}
  else if(writer.total)reportBytes(writer,0);
 }
 for(mz_uint i=0,n=(mz_uint)std::min<NSUInteger>(count,maxEntries);i<n&&ok;++i){@autoreleasepool{mz_zip_archive_file_stat st{};if(!mz_zip_reader_file_stat(&zip,i,&st)){ok=NO;break;}
  NSString*name=[[NSString alloc]initWithUTF8String:st.m_filename];name=[name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
  if(!name.length||[name hasPrefix:@"/"]||[name containsString:@":"]){ok=NO;break;}
  for(NSString*part in name.pathComponents)if([part isEqualToString:@".."]){ok=NO;break;}
  if(!ok)break;
  NSString*path=[[base stringByAppendingPathComponent:name]stringByStandardizingPath];if(![path hasPrefix:[base stringByAppendingString:@"/"]]||!seen.insert(path.lowercaseString.UTF8String).second){ok=NO;break;}
  if(mz_zip_reader_is_file_a_directory(&zip,i)){ok=[fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&failure];continue;}
  if(mz_zip_reader_is_file_encrypted(&zip,i)||!mz_zip_reader_is_file_supported(&zip,i)){ok=NO;break;}
  if(filesSinceSpaceCheck>=256||bytesSinceSpaceCheck>=64ull*1024*1024||st.m_uncomp_size>spaceBudget){
   NSDictionary*space=[fm attributesOfFileSystemForPath:base error:&failure];if(!space){ok=NO;break;}
   unsigned long long free=[space[NSFileSystemFreeSize] unsignedLongLongValue];spaceBudget=free-MIN(64ull*1024*1024,free);filesSinceSpaceCheck=0;bytesSinceSpaceCheck=0;
  }
  if(st.m_uncomp_size>spaceBudget){failure=PMArchiveError(@"Insufficient free storage to extract archive.");ok=NO;break;}
  spaceBudget-=st.m_uncomp_size;bytesSinceSpaceCheck+=st.m_uncomp_size;++filesSinceSpaceCheck;
  if(![fm createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&failure]){ok=NO;break;}
  writer.file=fopen(path.fileSystemRepresentation,"wb");
  if(!writer.file){failure=[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSFilePathErrorKey:path}];ok=NO;break;}
  writer.offset=0; writer.expected=st.m_uncomp_size;
  ok=mz_zip_reader_extract_to_callback(&zip,i,writeExtracted,&writer,0) && writer.offset==writer.expected;
  if(fclose(writer.file)!=0)ok=NO;
  if(ok){writer.before+=writer.offset;[files addObject:path];}
 }}
 mz_zip_reader_end(&zip);
 if(!ok){if(error)*error=failure?:PMArchiveError(@"Archive extraction failed: corrupt file, invalid path, or unsupported format.");[fm removeItemAtPath:base error:nil];return nil;}
 if(writer.total)reportBytes(writer,writer.total);
 return files;
}
NSArray<NSString*>*PMExtractArchiveURL(NSURL*url,NSString*destination,NSError**error){
 NSFileCoordinator*coordinator=[[NSFileCoordinator alloc]initWithFilePresenter:nil];
 __block NSArray<NSString*>*files=nil;__block NSError*readError=nil;NSError*coordinationError=nil;
 [coordinator coordinateReadingItemAtURL:url options:0 error:&coordinationError byAccessor:^(NSURL*readURL){files=PMExtractArchiveImpl(readURL.path,destination,100000,chartTotalLimit,chartFileLimit,&readError,url);}];
 if(!files||coordinationError){if(error)*error=readError?:coordinationError?:PMArchiveError(@"Unable to read selected archive");return nil;}
 return files;
}
NSArray<NSString*>*PMExtractArchive(NSString*archive,NSString*destination,NSError**error){return PMExtractArchiveImpl(archive,destination,100000,chartTotalLimit,chartFileLimit,error);}
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
