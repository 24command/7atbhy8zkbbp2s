#pragma once
#import <Foundation/Foundation.h>
#include <string.h>

static NSString * const PMChapterScriptName=@"os.lua";
static inline NSData *PMChapterScriptData(NSURL *url,NSError **error) {
 NSFileManager *fm=NSFileManager.defaultManager;
 NSDictionary *a=[fm attributesOfItemAtPath:url.path error:error];if(!a)return nil;
 if([a[NSFileType] isEqual:NSFileTypeRegular] && [a[NSFileSize] unsignedLongLongValue]>0 && [a[NSFileSize] unsignedLongLongValue]<=2*1024*1024){
  NSData *data=[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];if(!data)return nil;
  if(data.length && data.length<=2*1024*1024 && !memchr(data.bytes,0,data.length) && ((const uint8_t*)data.bytes)[0]!=0x1b && [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding])return data;
 }
 if(error)*error=[NSError errorWithDomain:@"PhiMod.ChapterOS" code:1 userInfo:@{NSLocalizedDescriptionKey:@"请选择非空的 UTF-8 Lua 源码文件（最大 2 MiB），不支持二进制字节码。"}];return nil;
}
