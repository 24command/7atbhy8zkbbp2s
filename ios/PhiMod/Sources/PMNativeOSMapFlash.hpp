#pragma once
#include <CoreGraphics/CoreGraphics.h>

namespace pmnativeosmap {
// Input is the displayed, orientation-correct thumbnail. Source-in paints
// white with the destination alpha, including all fractional edge pixels.
inline CGImageRef createFlashSilhouette(CGImageRef thumbnail) {
    size_t w = CGImageGetWidth(thumbnail), h = CGImageGetHeight(thumbnail);
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    if (!rgb) return nullptr;
    CGContextRef ctx = CGBitmapContextCreate(nullptr, w, h, 8, w * 4, rgb,
                             kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(rgb);
    if (!ctx) return nullptr;
    CGRect bounds = CGRectMake(0, 0, w, h);
    CGContextSetBlendMode(ctx, kCGBlendModeCopy);
    CGContextDrawImage(ctx, bounds, thumbnail);
    CGContextSetBlendMode(ctx, kCGBlendModeSourceIn);
    CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
    CGContextFillRect(ctx, bounds);
    CGImageRef result = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    return result;
}
}
