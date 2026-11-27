"""Compile production PMA adapters on Apple; portable budgets/dump checks locally."""
from pathlib import Path
import os
import platform
import re
import subprocess
import tempfile
import unittest
from test_native_os_transition_support import compile_cpp, run_cpp
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'PhiMod/Sources'
MAP = (SRC / 'PMNativeOSMap.mm').read_text(encoding='utf-8')
MEDIA = (SRC / 'PMNativeOSMapMedia.inc').read_text(encoding='utf-8')


def section(start, end):
    return start + MAP.split(start, 1)[1].split(end, 1)[0]


class PMAPerformance(unittest.TestCase):
    def test_portable_budget(self):
        header = (SRC / 'PMNativeOSFrameSequenceBudget.hpp').as_posix()
        source = '#include "' + header + '"\n' + r'''
#include <cassert>
int main() {
    using namespace pmnativeosmap::residency;
    assert(dimensionLimit(5)>=720);
    assert(dimensionLimit(253)<130);
    assert(dimensionLimit(1)==2048);
    for(size_t count=1;count<=512;++count) {
        size_t side=dimensionLimit(count);
        assert(side*side*count<=pageTexels);
    }
}
'''
        with tempfile.TemporaryDirectory(prefix='pma-budget-') as tmp:
            run_cpp(self, compile_cpp(source, tmp, 'budget'))

    def test_lazy_page_wiring(self):
        build = section('void build(', '// UI objects remain stable')
        self.assertNotIn('loadArt(', build)
        self.assertIn('pixels[n.screen]', build)
        media_build = MEDIA.split('std::shared_ptr<Media> buildMedia', 1)[1].split('void stopMedia', 1)[0]
        self.assertNotIn('newTexture(', media_build)
        refresh = section('void refresh(', 'bool matches(')
        self.assertLess(refresh.index('if (!active)'), refresh.index('acquireArt(m,item)'))
        switch = section('bool displayPage(', 'bool setElement(')
        self.assertLess(switch.index('stopMedia(m,'), switch.index('releasePageArt(m)'))
        self.assertLess(switch.index('releasePageArt(m)'), switch.index('m.page = screen'))
        pma = MEDIA.split('if ([path.pathExtension.lowercaseString isEqualToString:@"pma"])', 1)[1].split('if (!decoder->source)', 1)[0]
        self.assertNotIn('encodeImage', pma)
        raw = MEDIA.split('P uploadSequence(', 1)[1].split('void warmMedia(', 1)[0]
        self.assertIn('uploadedRevision==g.revision', raw)
        self.assertIn('"LoadRawTextureData",{"System.IntPtr","System.Int32"}', raw)
        self.assertNotIn('LoadImage', raw)
        self.assertNotIn('array_new', raw)
        self.assertIn('std::weak_ptr<GifSource> queuedDecoder', MEDIA)
        self.assertIn('std::weak_ptr<GifDelivery> delivery', MEDIA)
        callback = MEDIA.split('dispatch_async(dispatch_get_main_queue()', 1)[1].split('std::shared_ptr<Media> buildMedia', 1)[0]
        self.assertNotIn('= png', callback)
        self.assertIn('owner->delivery.reset()', callback)


    @unittest.skipUnless(os.environ.get('PHIGROS_404_ANALYSIS'), 'requires local retail dump.cs')
    def test_retail_texture_signatures(self):
        dump = (Path(os.environ['PHIGROS_404_ANALYSIS']) / 'dump.cs').read_text('utf-8-sig')
        cls = re.search(r'^public sealed class Texture2D\b.*?^}', dump, re.M | re.S)
        self.assertIsNotNone(cls)
        for signature in (
            'public void LoadRawTextureData(IntPtr data, int size)',
            'public void Apply(bool updateMipmaps, bool makeNoLongerReadable)',
            'public bool Reinitialize(int width, int height, TextureFormat format, bool hasMipMap)',
            'public void .ctor(int width, int height, TextureFormat textureFormat, bool mipChain)',
        ):
            self.assertIn(signature, cls[0])
        self.assertIn('public const TextureFormat RGBA32 = 4;', dump)

    @unittest.skipUnless(platform.system() == 'Darwin', 'Foundation/ImageIO adapter runs on Apple CI')
    def test_native_actual_adapter(self):
        with tempfile.TemporaryDirectory(prefix='pma-performance-') as tmp:
            out = Path(tmp)
            # Extract exact production functions, not replicas. Full Map.mm is
            # additionally syntax-checked against the iOS SDK by the CI runner.
            (out / 'PMNativeOSMapPortableUnderTest.inc').write_text(MAP.split('#ifdef __OBJC__', 1)[0])
            (out / 'PMNativeOSMapOwnershipUnderTest.inc').write_text(
                section('void destroy(', 'template<class Work> bool checked(') +
                section('Handle newTexture(', 'void upload('))
            (out / 'PMNativeOSMapResidencyUnderTest.inc').write_text(
                section('NSString *pageArtKey(', 'void validateParent(') +
                section('void acquireArt(', 'void refresh('))
            binary = out / 'adapter'
            subprocess.run(['xcrun', 'clang++', '-std=c++17', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
                            '-I' + str(out), '-I' + str(SRC),
                            '-framework', 'Foundation', '-framework', 'CoreGraphics', '-framework', 'ImageIO',
                            str(ROOT / 'tests/PMNativeOSFrameSequencePerformanceTest.mm'),
                            str(SRC / 'PMNativeOSFrameSequence.mm'), '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True, timeout=60)


if __name__ == '__main__':
    unittest.main()
