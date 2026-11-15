#import <Foundation/Foundation.h>
NSArray<NSString*>*PMExtractArchiveURL(NSURL*url,NSString*destination,NSError**error);
NSArray<NSString*>*PMExtractArchive(NSString*archive,NSString*destination,NSError**error);
NSArray<NSString*>*PMExtractArchiveLimited(NSString*archive,NSString*destination,NSUInteger maxEntries,unsigned long long maxUncompressed,unsigned long long maxFile,NSError**error);
BOOL PMCreateArchive(NSString*folder,NSString*output,NSError**error);
