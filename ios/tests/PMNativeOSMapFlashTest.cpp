#include "../PhiMod/Sources/PMNativeOSMapFlash.hpp"
#include <array>
#include <cassert>
#include <cstdint>

int main() {
    // Asymmetric rows catch vertical flips. Test every alpha value twice,
    // with different source colors to catch tinting or luminance-based masks.
    constexpr size_t w = 32, h = 16;
    std::array<uint8_t, w*h*4> original{}, actual{};
    for (size_t i = 0; i < w*h; ++i) {
        auto alpha = uint8_t(i);
        original[4*i + (i < 256 ? 0 : 2)] = alpha;
        original[4*i + 3] = alpha;
    }
    auto rgb = CGColorSpaceCreateDeviceRGB();
    auto format = kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast;
    auto src = CGBitmapContextCreate(original.data(), w, h, 8, w*4, rgb, format);
    auto dst = CGBitmapContextCreate(actual.data(), w, h, 8, w*4, rgb, format);
    CGColorSpaceRelease(rgb);
    assert(src && dst);
    auto image = CGBitmapContextCreateImage(src);
    auto flash = pmnativeosmap::createFlashSilhouette(image);
    assert(flash && CGImageGetWidth(flash) == w && CGImageGetHeight(flash) == h);
    CGContextDrawImage(dst, CGRectMake(0, 0, w, h), flash);
    CGContextFlush(dst);
    for (size_t i = 0; i < w*h; ++i) {
        for (size_t c = 0; c < 4; ++c) assert(actual[4*i+c] == original[4*i+3]);
    }
    CGImageRelease(flash);
    CGImageRelease(image);
    CGContextRelease(dst);
    CGContextRelease(src);
}
