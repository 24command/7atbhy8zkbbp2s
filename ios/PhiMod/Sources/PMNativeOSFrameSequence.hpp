#pragma once
// Foundation and ImageIO must be imported before this header. C linkage permits
// inclusion by MapMedia.inc inside its private C++ namespace, without Map.mm edits.
extern "C" {
// Call only on a decoder queue. This validates metadata/files, never preloads frames.
NSObject *PMOSFrameSequenceOpen(NSString *path, NSError **error);
NSUInteger PMOSFrameSequenceCount(NSObject *sequence);
double PMOSFrameSequenceDelay(NSObject *sequence);
CGImageRef PMOSFrameSequenceCopyFrame(NSObject *sequence, NSUInteger index,
                                     NSUInteger maxPixels, NSError **error) CF_RETURNS_RETAINED;
}
