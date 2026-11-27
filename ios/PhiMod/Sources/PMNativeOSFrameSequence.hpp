#pragma once
// Foundation and ImageIO must be imported before this header. C linkage permits
// inclusion by MapMedia.inc inside its private C++ namespace, without Map.mm edits.
extern "C" {
// Paths must be inside NSHomeDirectory(), with no symlinks below that trusted container.
// Call only on a decoder queue. This validates metadata/files, never preloads frames.
NSObject *PMOSFrameSequenceOpen(NSString *path, NSError **error);
NSUInteger PMOSFrameSequenceCount(NSObject *sequence);
double PMOSFrameSequenceDelay(NSObject *sequence);
CGImageRef PMOSFrameSequenceCopyFrame(NSObject *sequence, NSUInteger index,
                                     NSUInteger maxPixels, NSError **error) CF_RETURNS_RETAINED;
// Queue-confined, one-frame cache keyed by filename and decode limit. RGBA32 is
// straight alpha, bottom row first for Unity. revision changes only on a decode.
NSData *PMOSFrameSequenceRGBAFrame(NSObject *sequence, NSUInteger index,
    NSUInteger maxPixels, NSUInteger *width, NSUInteger *height,
    uint64_t *revision, NSError **error);
}
