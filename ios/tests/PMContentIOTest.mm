#import "../PhiMod/Sources/PMContentIO.h"
#include <cassert>
#include <cstdio>
@interface PMScopeProbe : NSObject
@property(nonatomic) BOOL grantsAccess;
@property(nonatomic) NSUInteger starts;
@property(nonatomic) NSUInteger stops;
@end
@implementation PMScopeProbe
- (BOOL)startAccessingSecurityScopedResource{++self.starts;return self.grantsAccess;}
- (void)stopAccessingSecurityScopedResource{++self.stops;}
@end
int main(){@autoreleasepool{
 PMScopeProbe*a=[PMScopeProbe new],*b=[PMScopeProbe new],*local=[PMScopeProbe new];a.grantsAccess=YES;b.grantsAccess=YES;
 PMScopedFileAccess*batch=[[PMScopedFileAccess alloc]initWithURLs:(id)@[a,b,local]];
 assert(a.starts==1&&b.starts==1&&local.starts==1&&a.stops==0&&b.stops==0);
 [batch close];[batch close];assert(a.stops==1&&b.stops==1&&local.stops==0);
 @autoreleasepool{__unused PMScopedFileAccess*automatic=[[PMScopedFileAccess alloc]initWithURLs:(id)@[a]];}
 assert(a.starts==2&&a.stops==2);
 NSFileManager*fm=NSFileManager.defaultManager;NSError*error=nil;NSString*root=[NSTemporaryDirectory()stringByAppendingPathComponent:NSUUID.UUID.UUIDString];assert([fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:&error]);
 NSString*json=[root stringByAppendingPathComponent:@"chart.json"];NSMutableArray*notes=[NSMutableArray new];for(int i=0;i<40000;++i)[notes addObject:@{@"time":@(i),@"hold":@(i%4==0),@"text":@"谱面\n难度 Ω 😺",@"value":@(.123456789012345)}];NSDictionary*original=@{@"judgeLineList":notes,@"empty":NSNull.null};
 for(NSNumber*pretty in @[@NO,@YES]){assert(PMWriteJSONFile(original,json,pretty.boolValue?NSJSONWritingPrettyPrinted:0,&error));assert(error==nil);id read=PMReadJSONFile(json,NSJSONReadingMutableContainers,&error);assert([read isEqual:original]);[read setObject:@YES forKey:@"mutable"];assert([read[@"mutable"]boolValue]);}
 // More than one buffer of one-byte writes exercises fragment coalescing and close flushing.
 NSString*fragments=[root stringByAppendingPathComponent:@"fragments.bin"];NSOutputStream*stream=PMBufferedJSONOutput(fragments);[stream open];
 for(NSUInteger i=0;i<200003;++i){uint8_t byte=(uint8_t)i;assert([stream write:&byte maxLength:1]==1);}
 [stream close];assert(!stream.streamError);NSData*fragmentData=[NSData dataWithContentsOfFile:fragments];assert(fragmentData.length==200003);const uint8_t*fragmentBytes=(const uint8_t*)fragmentData.bytes;for(NSUInteger i=0;i<fragmentData.length;++i)assert(fragmentBytes[i]==(uint8_t)i);
 NSData*before=[NSData dataWithContentsOfFile:json];error=nil;assert(!PMWriteJSONFile(@{@"bad":[NSSet setWithObject:@1]},json,0,&error));assert(error);assert([[NSData dataWithContentsOfFile:json]isEqual:before]);
 error=nil;assert(!PMWriteJSONFile(original,[root stringByAppendingPathComponent:@"missing/file.json"],0,&error));assert(error);
 NSString*file=[root stringByAppendingPathComponent:@"song.mp3"],*copy=[root stringByAppendingPathComponent:@"audio.source.mp3"];FILE*out=fopen(file.fileSystemRepresentation,"wb");assert(out);unsigned char chunk[65536];for(size_t i=0;i<sizeof(chunk);++i)chunk[i]=(unsigned char)i;for(int i=0;i<512;++i)assert(fwrite(chunk,1,sizeof(chunk),out)==sizeof(chunk));assert(fclose(out)==0);
 error=nil;assert(PMCopySourceFile(file,copy,&error));assert(PMFilesEqual(file,copy));assert(PMCopySourceFile(file,file,&error));assert(PMCopySourceFile(file,copy,&error));assert(PMFilesEqual(file,copy));
 out=fopen(copy.fileSystemRepresentation,"r+b");assert(out);assert(fseek(out,-1,SEEK_END)==0);assert(fputc(7,out)!=EOF);fclose(out);assert(!PMFilesEqual(file,copy));
 error=nil;NSString*missing=[root stringByAppendingPathComponent:@"missing"];assert(!PMCopySourceFile(missing,copy,&error));assert(error);assert([fm fileExistsAtPath:copy]);assert(!PMFilesEqual(missing,missing));error=nil;assert(!PMCopySourceFile(missing,missing,&error));assert(error);
 for(NSString*name in [fm contentsOfDirectoryAtPath:root error:nil])assert(![name hasSuffix:@".partial"]);
 assert([fm removeItemAtPath:root error:&error]);puts("PASS streamed JSON Unicode/number round-trip, failed-write preservation, bounded 32MiB compare/copy, missing files and temporary cleanup");
}return 0;}
