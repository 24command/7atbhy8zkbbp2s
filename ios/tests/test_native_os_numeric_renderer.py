"""Compile and run the owned renderer parity fixture in the configured toolchain."""
from pathlib import Path
import tempfile
import unittest
from test_native_os_transition_support import compile_cpp, run_cpp


class NumericRenderer(unittest.TestCase):
    def test_portable_renderer_parity(self):
        fixture = Path(__file__).with_name('PMNativeOSNumericRendererTest.cpp')
        with tempfile.TemporaryDirectory(prefix='pm-os-numeric-renderer-') as directory:
            executable = compile_cpp('#include "' + fixture.as_posix() + '"\n',
                                     directory, 'numeric-renderer')
            run_cpp(self, executable)

    def test_affine_drag_implementation(self):
        fixture = Path(__file__).with_name('PMNativeOSAffineDragTest.cpp')
        with tempfile.TemporaryDirectory(prefix='pm-os-affine-drag-') as directory:
            executable = compile_cpp('#include "' + fixture.as_posix() + '"\n',
                                     directory, 'affine-drag')
            run_cpp(self, executable)

    def test_image_color_and_drag_integration_contracts(self):
        sources = Path(__file__).resolve().parents[1] / 'PhiMod' / 'Sources'
        native = (sources / 'PMNativeOSMap.mm').read_text(encoding='utf-8-sig')
        timeline = (sources / 'PMNativeOSEntryTimeline.mm').read_text(encoding='utf-8-sig')
        drag = (sources / 'PMNativeOSMapDrag.inc').read_text(encoding='utf-8-sig')
        self.assertIn('bool spriteTint = n.kind == PMOSImage && rendering::rgbTracks(n);', native)
        self.assertIn('if (spriteTint) color[3] = 0;', native)
        self.assertIn('if (spriteTint) item.tint = item.media->raw;', native)
        self.assertIn('if (spriteTint) item.tint = m.keep(image);', native)
        self.assertIn('_colorAnimated = pmentrytimeline::rgbTracks(node);', timeline)
        self.assertIn('if (!_colorAnimated ||', timeline)
        self.assertIn('if (_tintArtwork) self.backgroundColor = UIColor.clearColor;', timeline)
        self.assertIn('set_alphaHitTestMinimumThreshold', native)
        self.assertIn('if (item.affineDrag) buildDragLayer(m,item);', native)
        self.assertIn('if (m.affinePlacements) refreshAffinePlacements(m);', native)
        self.assertIn('if (m.affineMirrors) syncDragLayers(m);', native)
        self.assertIn('rendering::unsupportedNestedDrag(page,i)', native)
        start = drag.split('int puzzleInput(Map &m)', 1)[1]
        self.assertIn('showDragLayer(m,item);', start)
        self.assertIn('accepted=finishDrag(m,accepted);', start)
        for forbidden in ('trackKeys.assign', 'trackKeys.resize', 'make_unique', 'push_back'):
            self.assertNotIn(forbidden, start)


if __name__ == '__main__':
    unittest.main()
