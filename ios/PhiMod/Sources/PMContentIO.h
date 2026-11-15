#pragma once
#import <Foundation/Foundation.h>
#include <cstdio>
#include <cstring>
#include <sys/stat.h>
static inline NSError*PMContentIOError(NSString*message){return [NSError errorWithDomain:@"PhiMod.ContentIO" code:1 userInfo:@{NSLocalizedDescriptionKey:message?:@"File operation failed"}];}
// Streaming serialization avoids a second full-size JSON NSData beside the object graph.
// Never replace the last good file until writing and closing the temporary file succeeds.
static inline BOOL PMWriteJSONFile(id object,NSString*path,NSJSONWritingOptions options,NSError**error){
 NSString*temporary=[path stringByAppendingFormat:@".%@.partial",NSUUID.UUID.UUIDString];NSOutputStream*stream=[NSOutputStream outputStreamToFileAtPath:temporary append:NO];NSError*failure=nil;BOOL ok=NO;
 @try{[stream open];if(!stream){failure=PMContentIOError(@"Cannot open JSON output");}else{NSInteger bytes=[NSJSONSerialization writeJSONObject:object toStream:stream options:options error:&failure];ok=bytes>0&&!failure;if(stream.streamError){failure=stream.streamError;ok=NO;}}}
 @catch(NSException*e){failure=PMContentIOError(e.reason);ok=NO;}
 @finally{[stream close];if(stream.streamError){failure=stream.streamError;ok=NO;}}
 NSFileManager*fm=NSFileManager.defaultManager;
 if(ok){if([fm fileExistsAtPath:path])ok=[fm replaceItemAtURL:[NSURL fileURLWithPath:path] withItemAtURL:[NSURL fileURLWithPath:temporary] backupItemName:nil options:0 resultingItemURL:nil error:&failure];else ok=[fm moveItemAtPath:temporary toPath:path error:&failure];}
 if(!ok){[fm removeItemAtPath:temporary error:nil];if(error)*error=failure?:PMContentIOError(@"JSON output could not be completed; check available storage");}return ok;
}
static inline id PMReadJSONFile(NSString*path,NSJSONReadingOptions options,NSError**error){
 NSInputStream*stream=[NSInputStream inputStreamWithFileAtPath:path];if(!stream){if(error)*error=PMContentIOError(@"Cannot open JSON input");return nil;}id object=nil;
 @try{[stream open];object=[NSJSONSerialization JSONObjectWithStream:stream options:options error:error];}@catch(NSException*e){if(error)*error=PMContentIOError(e.reason);}@finally{[stream close];}return object;
}
static inline BOOL PMCopySourceFile(NSString*source,NSString*destination,NSError**error){
 if([source.stringByStandardizingPath.stringByResolvingSymlinksInPath isEqualToString:destination.stringByStandardizingPath.stringByResolvingSymlinksInPath]){BOOL exists=[NSFileManager.defaultManager fileExistsAtPath:source];if(!exists&&error)*error=PMContentIOError(@"Source file is missing");return exists;}
 NSString*temporary=[destination stringByAppendingFormat:@".%@.partial",NSUUID.UUID.UUIDString];NSFileManager*fm=NSFileManager.defaultManager;BOOL ok=[fm copyItemAtPath:source toPath:temporary error:error];
 if(ok){if([fm fileExistsAtPath:destination])ok=[fm replaceItemAtURL:[NSURL fileURLWithPath:destination] withItemAtURL:[NSURL fileURLWithPath:temporary] backupItemName:nil options:0 resultingItemURL:nil error:error];else ok=[fm moveItemAtPath:temporary toPath:destination error:error];}
 if(!ok)[fm removeItemAtPath:temporary error:nil];return ok;
}
// Fixed memory even for long songs/videos. Any read/size failure means "not equal",
// so a failed duplicate check can never authorize deleting the source file.
static inline bool PMFilesEqual(NSString*first,NSString*second){
 FILE*a=fopen(first.fileSystemRepresentation,"rb");if(!a)return false;FILE*b=fopen(second.fileSystemRepresentation,"rb");if(!b){fclose(a);return false;}
 struct stat sa{},sb{};bool equal=fstat(fileno(a),&sa)==0&&fstat(fileno(b),&sb)==0&&sa.st_size==sb.st_size;
 unsigned char x[65536],y[65536];while(equal){size_t na=fread(x,1,sizeof(x),a),nb=fread(y,1,sizeof(y),b);if(na!=nb||memcmp(x,y,na)||ferror(a)||ferror(b)){equal=false;break;}if(na==0)break;}
 fclose(a);fclose(b);return equal;
}
