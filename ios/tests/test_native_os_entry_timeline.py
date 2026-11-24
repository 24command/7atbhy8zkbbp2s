"""UIKit adapter contracts complement PMNativeOSEntryTimelineTest.cpp.

The C++ test exercises the implementation's actual portable sampling/geometry.
These checks keep UIKit/threading/resource boundaries auditable on non-Apple CI;
they are not a substitute for an iOS build or on-device rotation/decode tests.
"""
from pathlib import Path
import unittest

SOURCES = Path(__file__).resolve().parents[1] / "PhiMod" / "Sources"
HEADER = (SOURCES / "PMNativeOSEntryTimeline.h").read_text(encoding="utf-8-sig")
SOURCE = (SOURCES / "PMNativeOSEntryTimeline.mm").read_text(encoding="utf-8-sig")


def between(start, end):
    return SOURCE.split(start, 1)[1].split(end, 1)[0]


class EntryTimelineAdapter(unittest.TestCase):
    def test_public_api_and_async_main_completion(self):
        self.assertIn("prepareWithProgram:(PMNativeOSProgram *)program", HEADER)
        self.assertIn("PMNativeOSEntryTimeline * _Nullable timeline", HEADER)
        self.assertIn("NSError * _Nullable error", HEADER)
        self.assertIn("@property(nonatomic, readonly) UIView *view;", HEADER)
        self.assertIn("- (void)sample:(double)seconds;", HEADER)
        prepare = SOURCE.split("+ (void)prepareWithProgram:", 1)[1]
        self.assertLess(prepare.index("dispatch_async(dispatch_get_main_queue()"), prepare.index("completion(nil"))
        self.assertIn("dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, error); })", prepare)
        self.assertLess(prepare.rindex("dispatch_async(dispatch_get_main_queue()"), prepare.index("initWithPlan:*plan"))
        self.assertIn("program.transitionError", prepare)

    def test_global_indices_and_snapshot_not_map_or_vm(self):
        self.assertIn("program.nodes[i]", SOURCE)
        self.assertIn("plan->nodes.assign(page->elements, page->elements + page->nodes)", SOURCE)
        self.assertIn("node.screen != plan->screen", SOURCE)
        self.assertIn("_nodeViews[@(node.parent)]", SOURCE)
        for forbidden in ("transitionNodes", "pmnativeosmap::open", "PMOSClick(", "lua_", "PMNativeOSTransition", "CADisplayLink", "NSTimer"):
            self.assertNotIn(forbidden, SOURCE)
        for helper in ("layout::opacity", "layout::sample", "layout::motion"):
            self.assertIn(helper, SOURCE)

    def test_decode_is_serial_bounded_and_shared(self):
        decoder = between("PMEntryTimelineBitmap *decodeStill(", "@interface PMEntryTimelineNodeView")
        self.assertIn("!NSThread.isMainThread", decoder)
        self.assertIn("DISPATCH_QUEUE_SERIAL", SOURCE)
        for guard in ("sourceFileBudget", "sourcePixelBudget", "CGImageSourceGetCount(source) != 1", "imageBytes(w, h, remaining"):
            self.assertIn(guard, decoder)
        self.assertIn("kCGImageSourceThumbnailMaxPixelSize", decoder)
        self.assertIn("kCGImageSourceShouldCacheImmediately", decoder)
        self.assertIn("CGContextDrawImage(bitmap", decoder)
        self.assertIn("CGBitmapContextCreateImage(bitmap)", decoder)
        self.assertIn("remaining -= bytes", decoder)
        self.assertNotIn("UIImage", decoder)
        prepare = SOURCE.split("+ (void)prepareWithProgram:", 1)[1]
        self.assertLess(prepare.index("dispatch_async(decodeQueue()"), prepare.index("decodeStill("))
        self.assertIn("[NSSet setWithArray:paths.allValues]", prepare)
        self.assertIn("bitmaps[path] = bitmap", prepare)
        self.assertIn("UIImage *image = [UIImage imageWithCGImage:", prepare)
        self.assertIn("images[path] = image", prepare)
        self.assertNotIn("imageWithContentsOfFile", SOURCE)
        self.assertNotIn("imageWithData", SOURCE)

    def test_rotation_layout_never_writes_transformed_frame(self):
        root = between("@implementation PMEntryTimelineRootView", "@interface PMNativeOSEntryTimeline ()")
        layout = root.split("- (void)layoutSubviews", 1)[1].split("- (void)sample:", 1)[0]
        self.assertIn("pmentrytimeline::fit(self.bounds.size.width, self.bounds.size.height", layout)
        self.assertIn("CGRect parent = view.superview.bounds", layout)
        self.assertIn("pmentrytimeline::rect(node, parent.size.width, parent.size.height)", layout)
        self.assertIn("view.bounds =", layout)
        self.assertIn("view.center =", layout)
        self.assertIn("[self applyPose:i]", layout)
        self.assertNotIn(".frame =", root)
        self.assertIn("CGAffineTransformMake(pose.scale, 0, 0, pose.scale, 0, -pose.lift * view.bounds.size.height)", root)
        self.assertIn("view.alpha = state.local", root)
        self.assertIn("UIViewContentModeScaleAspectFit", SOURCE)
        self.assertIn("UIViewContentModeScaleAspectFill", SOURCE)

    def test_black_backdrop_is_input_and_accessibility_transparent(self):
        root = between("@implementation PMEntryTimelineRootView", "@interface PMNativeOSEntryTimeline ()")
        self.assertIn("self.backgroundColor = UIColor.blackColor", root)
        self.assertIn("self.opaque = YES", root)
        self.assertIn("self.userInteractionEnabled = NO", root)
        self.assertIn("self.accessibilityElementsHidden = YES", root)
        self.assertIn("- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return nil; }", root)
        self.assertIn("_canvas.clipsToBounds = YES", root)
        self.assertIn("[self sample:0]", root)

    def test_rgba_label_and_end_hold(self):
        for channel in ("node.rgba >> 24", "node.rgba >> 16", "node.rgba >> 8", "node.rgba & 255"):
            self.assertIn(channel, SOURCE)
        self.assertIn("[NSString stringWithUTF8String:node.label]", SOURCE)
        self.assertIn("std::nextafter(duration, 0.)", SOURCE)
        self.assertIn("pmentrytimeline::clock(seconds, _duration)", SOURCE)
        self.assertIn("_label.minimumScaleFactor = 14. / 24.", SOURCE)


if __name__ == "__main__":
    unittest.main()
