#pragma once
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <cstdio>
// Fixed-size reads: autoreleased NSData chunks used to retain the entire file until export ended.
static NSString*PMFileSHA256(NSString*p){
 FILE*file=fopen(p.fileSystemRepresentation,"rb");if(!file)return nil;
 CC_SHA256_CTX c;CC_SHA256_Init(&c);unsigned char buffer[65536];size_t n;
 while((n=fread(buffer,1,sizeof(buffer),file))!=0)CC_SHA256_Update(&c,buffer,(CC_LONG)n);
 bool failed=ferror(file)!=0;if(fclose(file)!=0)failed=true;if(failed)return nil;
 unsigned char out[CC_SHA256_DIGEST_LENGTH];CC_SHA256_Final(out,&c);
 NSMutableString*s=[NSMutableString new];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;++i)[s appendFormat:@"%02x",out[i]];return s;
}
