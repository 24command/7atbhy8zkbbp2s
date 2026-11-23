#pragma once
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <cstdio>
#import "PMStockUnlockLayout.hpp"
#import <CoreGraphics/CoreGraphics.h>

namespace pmstock {
inline NSData *verifiedSpan(NSString *file, NSUInteger offset, NSUInteger length, const char *sha) {
    NSData *mapped=[NSData dataWithContentsOfFile:file options:NSDataReadingMappedIfSafe error:nil];
    if (!mapped || offset>mapped.length) return nil;
    if (!length) length=mapped.length-offset;
    if (!length || length>mapped.length-offset || length>UINT32_MAX) return nil;
    NSData *span=[mapped subdataWithRange:NSMakeRange(offset,length)];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(span.bytes,(CC_LONG)length,digest);
    char hex[65];
    for (unsigned i=0;i<sizeof(digest);++i) snprintf(hex+2*i,3,"%02x",digest[i]);
    return strcmp(hex,sha)==0 ? span : nil;
}
struct Polygon { float rgba[4], points[4][4]; };
struct Assets {
    Curves curves;
    Polygon shapes[4];
    CGFontRef font=nullptr;
    ~Assets() { if (font) CGFontRelease(font); }
    Assets()=default;
    Assets(const Assets &)=delete;
    bool load(const Layout &s, NSString *dir) {
        NSString *scene=[NSString stringWithFormat:@"level%d",s.scene];
        NSString *shared=[NSString stringWithFormat:@"sharedassets%d.assets",s.scene];
        NSData *art=verifiedSpan([dir stringByAppendingPathComponent:scene],0,0,s.sceneHash);
        NSData *stream=verifiedSpan([dir stringByAppendingPathComponent:shared],s.streamOffset,s.streamSize,s.streamHash);
        if (!art || !stream || !curves.load((const uint8_t *)stream.bytes,stream.length,s.lanes)) return false;
        for (size_t i=0;i<s.polygons.size();++i) {
            if (s.polygons[i]+164>art.length) return false;
            auto p=(const uint8_t *)art.bytes+s.polygons[i];
            if (read<uint32_t>(p+96)!=4) return false;
            memcpy(shapes[i].rgba,p+44,16);
            memcpy(shapes[i].points,p+100,64);
        }
        // Serialized Unity Font pathID 50, also referenced by all eight Text components.
        NSData *fontData=verifiedSpan([dir stringByAppendingPathComponent:@"sharedassets0.assets"],77016,8693128,
            "1355a75352b0adcafd385238f1c481a31ed41c96b7761beb5c0b7c9d602b31b3");
        if (!fontData) return false;
        CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)fontData);
        if (!provider) return false;
        font=CGFontCreateWithDataProvider(provider);
        CGDataProviderRelease(provider);
        return font!=nullptr;
    }
};
}
