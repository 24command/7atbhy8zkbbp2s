// Test the decoded, orientation-correct thumbnail only on touch-down. Match the
// image view's contain/cover mapping, including transparent letterbox borders.
static BOOL PMCanvasOpaquePixel(UIImageView *view, CGPoint point) {
    CGImageRef image = view.image.CGImage;
    if (!image || CGRectIsEmpty(view.bounds)) return NO;
    CGFloat w = CGImageGetWidth(image), h = CGImageGetHeight(image);
    CGFloat sx = view.bounds.size.width / w, sy = view.bounds.size.height / h;
    CGFloat scale = view.contentMode == UIViewContentModeScaleAspectFill ? MAX(sx,sy) : MIN(sx,sy);
    CGFloat x = floor((point.x - CGRectGetMidX(view.bounds)) / scale + w / 2);
    CGFloat y = floor((point.y - CGRectGetMidY(view.bounds)) / scale + h / 2);
    if (x < 0 || y < 0 || x >= w || y >= h) return NO;
    uint8_t alpha = 0;
    CGContextRef ctx = CGBitmapContextCreate(&alpha, 1, 1, 8, 1, NULL, kCGImageAlphaOnly);
    if (!ctx) return NO;
    CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
    CGContextDrawImage(ctx, CGRectMake(-x, y + 1 - h, w, h), image);
    CGContextRelease(ctx);
    return alpha > 51;
}
