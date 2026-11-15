#import "PMContentIO.h"
#include <cerrno>

@interface PMBufferedFileOutputStream : NSOutputStream {
 NSString*_path;
 FILE*_file;
 NSError*_failure;
 NSStreamStatus _status;
 unsigned char _buffer[64*1024];
}
- (instancetype)initWithPath:(NSString*)path;
@end
@implementation PMBufferedFileOutputStream
- (instancetype)initWithPath:(NSString*)path{if((self=[super init])){_path=[path copy];_status=NSStreamStatusNotOpen;}return self;}
- (void)recordFailure{int code=errno?:EIO;_failure=[NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:@{NSFilePathErrorKey:_path}];_status=NSStreamStatusError;}
- (void)open{
 if(_status!=NSStreamStatusNotOpen)return;
 _file=fopen(_path.fileSystemRepresentation,"wb");
 if(!_file){[self recordFailure];return;}
 if(setvbuf(_file,(char*)_buffer,_IOFBF,sizeof(_buffer))!=0){[self recordFailure];fclose(_file);_file=nullptr;return;}
 _status=NSStreamStatusOpen;
}
- (NSInteger)write:(const uint8_t*)bytes maxLength:(NSUInteger)length{
 if(_status!=NSStreamStatusOpen||!_file)return -1;
 if(!length)return 0;
 size_t count=fwrite(bytes,1,length,_file);
 if(count!=length){[self recordFailure];return -1;}
 return (NSInteger)count;
}
- (void)close{
 if(_file){FILE*file=_file;_file=nullptr;if(fclose(file)!=0)[self recordFailure];}
 if(!_failure)_status=NSStreamStatusClosed;
}
- (void)dealloc{if(_file)fclose(_file);}
- (BOOL)hasSpaceAvailable{return _status==NSStreamStatusOpen;}
- (BOOL)getBuffer:(uint8_t**)buffer length:(NSUInteger*)length{return NO;}
- (NSStreamStatus)streamStatus{return _status;}
- (NSError*)streamError{return _failure;}
// The writer is synchronous and is never scheduled on a run loop.
- (void)scheduleInRunLoop:(NSRunLoop*)loop forMode:(NSRunLoopMode)mode{}
- (void)removeFromRunLoop:(NSRunLoop*)loop forMode:(NSRunLoopMode)mode{}
@end
NSOutputStream*PMBufferedJSONOutput(NSString*path){return [[PMBufferedFileOutputStream alloc]initWithPath:path];}

@implementation PMScopedFileAccess {
 NSMutableArray<NSURL*>*_opened;
}
- (instancetype)initWithURLs:(NSArray<NSURL*>*)urls{
 if((self=[super init])){_opened=[NSMutableArray new];for(NSURL*url in urls)if([url startAccessingSecurityScopedResource])[_opened addObject:url];}return self;
}
- (void)close{for(NSURL*url in _opened)[url stopAccessingSecurityScopedResource];[_opened removeAllObjects];}
- (void)dealloc{[self close];}
@end
