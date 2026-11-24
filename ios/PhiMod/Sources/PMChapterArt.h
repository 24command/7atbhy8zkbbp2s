#pragma once
#import <Foundation/Foundation.h>
// Used by both the document picker and the script loader. Never resolve a script-supplied absolute path.
static inline NSString *PMOSLocalMediaPath(NSString *chapter,NSString *name,NSArray<NSString *> *extensions){
 if(!chapter.length||!name.length||[name hasPrefix:@"."]||![name isEqual:name.lastPathComponent]||[name rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/:\\"]].location!=NSNotFound||[name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound||[name lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>=256)return nil;
 if(![extensions containsObject:name.pathExtension.lowercaseString])return nil;
 NSString *dir=[chapter stringByAppendingPathComponent:@"os-media"],*path=[dir stringByAppendingPathComponent:name];NSFileManager *fm=NSFileManager.defaultManager;
 for(NSString *part in @[chapter,dir,path])if([[fm attributesOfItemAtPath:part error:nil][NSFileType] isEqual:NSFileTypeSymbolicLink])return nil;
 return path;
}
// Preserve ordinary map/import validation. MOV is transition-video-only.
static inline NSString *PMOSArtPath(NSString *chapter,NSString *name){
 return PMOSLocalMediaPath(chapter,name,@[@"png",@"jpg",@"jpeg",@"webp",@"gif",@"mp4"]);
}
static inline NSString *PMOSEntryVideoPath(NSString *chapter,NSString *name){
 return PMOSLocalMediaPath(chapter,name,@[@"mp4",@"mov"]);
}
