#import <Foundation/Foundation.h>
@interface PMContentStore : NSObject
+ (instancetype)shared;
@property(nonatomic,readonly) NSString*root;
@property(nonatomic,readonly) NSUInteger revision;
- (NSDictionary*)snapshot;
- (BOOL)commit:(NSDictionary*)value error:(NSError**)error;
- (NSString*)asset:(NSString*)identifier;
- (BOOL)importURL:(NSURL*)url chapter:(NSString*)chapter error:(NSError**)error;
- (NSURL*)exportSong:(NSString*)identifier error:(NSError**)error;
- (NSURL*)exportChapter:(NSString*)identifier error:(NSError**)error;
- (BOOL)removeSong:(NSString*)identifier error:(NSError**)error;
- (BOOL)removeSongs:(NSArray<NSString*>*)identifiers error:(NSError**)error;
- (BOOL)replaceImage:(NSURL*)url identifier:(NSString*)identifier error:(NSError**)error;
- (BOOL)replaceImageData:(NSData*)data identifier:(NSString*)identifier error:(NSError**)error;
@end
