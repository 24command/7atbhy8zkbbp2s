#pragma once
#import <Foundation/Foundation.h>

// The archive layout is a wire format. These paths are only for the installed library.
static inline NSString *PMAssetPath(NSString *root, NSString *bucket, NSString *identifier) {
 NSString *base=[root stringByAppendingPathComponent:@"assets"];
 if(bucket.length)base=[base stringByAppendingPathComponent:bucket];
 return [base stringByAppendingPathComponent:identifier];
}
static inline NSSet *PMEntityIDs(NSArray *rows) {
 NSMutableSet *ids=[NSMutableSet set];
 for(id row in rows)if([row isKindOfClass:NSDictionary.class]&&[row[@"id"] isKindOfClass:NSString.class])[ids addObject:row[@"id"]];
 return ids;
}
// Called only for entries seen in the legacy directory listing, never per frame.
static inline NSString *PMRelocateAsset(NSString *root, NSString *bucket, NSString *identifier) {
 NSFileManager *fm=NSFileManager.defaultManager;
 NSString *old=PMAssetPath(root,nil,identifier), *dest=PMAssetPath(root,bucket,identifier);
 if([fm fileExistsAtPath:dest]){
  if([[fm attributesOfItemAtPath:dest error:nil][NSFileType] isEqual:NSFileTypeDirectory])return dest;
  return old; // A file occupying the new location must not hide a usable old folder.
 }
 if(![[fm attributesOfItemAtPath:old error:nil][NSFileType] isEqual:NSFileTypeDirectory])return dest;
 return [fm moveItemAtPath:old toPath:dest error:nil]?dest:old;
}
