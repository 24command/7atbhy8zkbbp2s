"""Verify chapter-specific movie and credit assets in an installed 4.0.4 build 3 IPA."""
import hashlib
import os
from pathlib import Path
import plistlib
import re
import struct
import unittest
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1] / 'PhiMod'
IPA = os.getenv('PHIGROS_404_IPA') or os.getenv('PM_STOCK_IPA')


class LockedPreviewContract(unittest.TestCase):
    def test_exact_song_reaches_display_only_presenter(self):
        bridge = (ROOT / 'Sources/PMChapterC8C9UnlockInfo.hpp').read_text()
        self.assertRegex(bridge, r'prepareChapter:0\s+songID:songID\s+fields:fields')
        # Guard against routing upcoming-song metadata through the playable-row API.
        for gateway in ('PMNativeOSDetail', 'SongSelectorItem', 'PMDoorArm', 'PMUnlockProgress',
                        'get_Unlocked', 'get_PlayableLevelCount', 'PMStorySequenceArm'):
            self.assertNotIn(gateway, bridge)
        shared = (ROOT / 'Sources/PMStockUnlockPresenter.mm').read_text()
        self.assertRegex(shared, r'userInteractionEnabled\s*=\s*NO')
        self.assertRegex(shared, r'selected\s*=\s*\[songID copy\]')
        self.assertRegex(shared, r'_songID\s*=\s*selected')


@unittest.skipUnless(IPA, 'set PHIGROS_404_IPA to audit the installed assets')
class C8C9UnlockAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import UnityPy
        cls.unity = staticmethod(UnityPy.load)
        cls.archive = ZipFile(IPA)
        cls.addClassCleanup(cls.archive.close)

    def data(self, name):
        return self.archive.read('Payload/Phigros.app/Data/' + name)

    def test_default_and_df_movies(self):
        info = plistlib.loads(self.archive.read('Payload/Phigros.app/Info.plist'))
        self.assertEqual((info['CFBundleShortVersionString'], info['CFBundleVersion']), ('4.0.4', '3'))
        resolver = (ROOT / 'Core/PMStockIntroResolver.h').read_text()
        for scene, asset, ref, frames in [(24, '321_Unlock_Final_Plus', 'c8/321-unlock', 807),
                                          (27, 'DF_Unlock', 'c8/df-unlock', 1396),
                                          (33, 'ds unlockIntro_Sound', 'c9/ds-intro', 540)]:
            with self.subTest(scene=scene):
                objects = self.unity(self.data(f'sharedassets{scene}.assets')).objects
                clip, = [o.read() for o in objects if o.type.name == 'VideoClip' and o.peek_name() == asset]
                self.assertEqual((clip.m_FrameCount, clip.m_FrameRate), (frames, 30))
                span = clip.m_ExternalResources
                resource = self.data(span.m_Source)
                digest = hashlib.sha256(resource[span.m_Offset:span.m_Offset+span.m_Size]).hexdigest()
                self.assertRegex(resolver, re.escape(f'"@stock/{ref}", "{span.m_Source}",') +
                                 r'\s*' + re.escape(f'"{digest}", {span.m_Size}, {span.m_Offset}, {len(resource)}'))

    def test_credit_polygons_and_showinfo(self):
        # Compare actual RGBA, vertex count and relative + absolute polygon coordinates.
        def polygons(scene, offsets):
            data = self.data(f'level{scene}')
            return [data[p+44:p+60] + data[p+96:p+164] for p in offsets]

        shared = polygons(8, [22440, 23424, 22720, 21224])
        self.assertEqual(polygons(24, [6912, 9144, 8848, 7616]), shared)
        self.assertEqual(polygons(27, [9552, 12808, 12512, 11168]), shared)
        streams = []
        for n, name, stop in [(8, 'ShowInfoETC', 7), (24, 'ShowInfo', 11), (27, 'ShowInfo', 7)]:
            objects = self.unity(self.data(f'sharedassets{n}.assets')).objects
            animation, = [o.read() for o in objects if o.type.name == 'AnimationClip' and o.peek_name() == name]
            self.assertEqual((animation.m_SampleRate, animation.m_MuscleClip.m_StopTime), (60, stop))
            words = animation.m_MuscleClip.m_Clip.data.m_StreamedClip.data
            stream = struct.pack(f'<{len(words)}I', *words)
            streams.append(stream)
            # Third binding is CanvasGroup.alpha. Read each timestamp and keyed lane.
            self.assertEqual(animation.m_ClipBindingConstant.genericBindings[2].typeID, 225)
            alpha = []
            pos = 0
            while pos < len(stream):
                time, count = struct.unpack_from('<fI', stream, pos)
                pos += 8
                for key in range(count):
                    lane, _, _, _, value = struct.unpack_from('<I4f', stream, pos)
                    pos += 20
                    if lane == 2 and time >= 0:
                        alpha.append((time, value))
            self.assertAlmostEqual(alpha[0][0], 62/60, places=6)
            self.assertEqual(alpha[0][1], 0)
            self.assertGreater(alpha[1][1], 0)
            self.assertEqual(alpha[-1], (stop, 0))
        self.assertEqual(streams[0], streams[2])


if __name__ == '__main__':
    unittest.main()
