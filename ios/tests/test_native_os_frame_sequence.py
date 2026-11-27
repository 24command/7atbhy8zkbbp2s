"""PMA integration checks and actual Foundation/ImageIO tests on macOS."""
from pathlib import Path
import os
import platform
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'PhiMod' / 'Sources'
class SequenceAdapter(unittest.TestCase):
    def test_pma_uses_frame_decoder_not_player(self):
        media = (SRC / 'PMNativeOSMapMedia.inc').read_text(encoding='utf-8')
        self.assertIn('[ext isEqualToString:@"pma"]', media)
        build = media.split('std::shared_ptr<Media> buildMedia', 1)[1].split('void stopMedia', 1)[0]
        self.assertIn('isEqualToString:@"mp4"', build)
        self.assertNotIn('isEqualToString:@"pma"', build)
        request = media.split('void requestGif', 1)[1].split('std::shared_ptr<Media> buildMedia', 1)[0]
        self.assertLess(request.index('dispatch_async(queue'), request.index('PMOSFrameSequenceOpen'))
        self.assertIn('PMOSFrameSequenceRGBAFrame(decoder->sequence,frame,pixels,&width,&height,&revision,&error)', request)
        self.assertIn('owner->frame != frame || owner->decoder != decoder', request)
        self.assertIn('std::weak_ptr<GifVisit>', request)
    def test_build_automatically_links_helper(self):
        self.assertIn('"$ROOT"/PhiMod/Sources/*.mm', (ROOT/'build_unsigned.sh').read_text())
    def test_loader_is_rooted_at_trusted_container(self):
        source = (SRC/'PMNativeOSFrameSequence.mm').read_text(encoding='utf-8')
        loader = source.split('int openMediaDirectory(', 1)[1].split('int openFile(', 1)[0]
        self.assertIn('containerSpelling(NSHomeDirectory())', loader)
        self.assertIn('[home stringByAppendingString:@"/"]', loader)
        self.assertIn('open(home.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)', loader)
        self.assertNotIn('open("/"', loader)
        self.assertIn('openat(fd, part.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)', loader)
        self.assertNotIn('stringByResolvingSymlinksInPath', source)
        self.assertIn('NSUnderlyingErrorKey:underlying', source)
        self.assertLess(loader.index('int code = errno'), loader.index('close(fd)'))

    def run_native(self, name, separate_loader):
        with tempfile.TemporaryDirectory(prefix='pma-test-') as tmp:
            binary = str(Path(tmp)/'pma-test')
            sources = [str(ROOT/'tests'/name)]
            if separate_loader:
                sources.append(str(SRC/'PMNativeOSFrameSequence.mm'))
            subprocess.run(['xcrun','clang++','-std=c++17','-fobjc-arc','-Wall','-Wextra','-Werror',
                            '-framework','Foundation','-framework','CoreGraphics','-framework','ImageIO',
                            *sources,'-o',binary],check=True)
            subprocess.run([binary],check=True,timeout=30)

    @unittest.skipUnless(platform.system() == 'Darwin', 'Foundation/ImageIO execution requires macOS')
    def test_native_manifest_and_png_decoder(self):
        self.run_native('PMNativeOSFrameSequenceTest.mm', True)

    @unittest.skipUnless(platform.system() == 'Darwin', 'Foundation/ImageIO execution requires macOS')
    def test_native_container_permissions(self):
        self.run_native('PMNativeOSFrameSequenceContainerTest.mm', False)
if __name__ == '__main__': unittest.main()
