#import <Foundation/Foundation.h>
@interface PMContentStore : NSObject
+ (instancetype)shared;
@property(nonatomic,readonly) NSString*root;
@property(nonatomic,readonly) NSUInteger revision;
- (NSDictionary*)snapshot;
- (BOOL)saveUnlockRule:(NSDictionary*)rule animationURL:(NSURL*)url identifier:(NSString*)identifier error:(NSError**)error;
- (BOOL)commit:(NSDictionary*)value error:(NSError**)error;
- (NSString*)coverFolder:(NSString*)identifier;
- (BOOL)assignSongs:(NSArray<NSString*>*)ids toChapter:(NSString*)chapter move:(BOOL)move error:(NSError**)error;
- (NSString*)asset:(NSString*)identifier;
- (BOOL)importURL:(NSURL*)url chapter:(NSString*)chapter error:(NSError**)error;
- (NSURL*)exportSong:(NSString*)identifier error:(NSError**)error;
- (NSURL*)exportChapter:(NSString*)identifier error:(NSError**)error;
- (BOOL)removeSong:(NSString*)identifier error:(NSError**)error;
- (BOOL)removeSongs:(NSArray<NSString*>*)identifiers error:(NSError**)error;
- (BOOL)replaceImage:(NSURL*)url identifier:(NSString*)identifier error:(NSError**)error;
- (BOOL)replaceImageData:(NSData*)data identifier:(NSString*)identifier error:(NSError**)error;
- (void)cleanupExports:(NSArray<NSURL*>*)urls;
- (NSArray<NSDictionary*>*)trashItems;
- (BOOL)restoreTrash:(NSString*)token error:(NSError**)error;
- (BOOL)deleteTrash:(NSString*)token error:(NSError**)error;
@end

FOUNDATION_EXPORT BOOL PMConvertAudioResource(NSString*source,NSString*destination,NSError**error);
