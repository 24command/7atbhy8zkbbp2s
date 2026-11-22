"""Native song details: verify 4.0.4 dump, ARM64 call edges and serialized scene donors.
Set PHIGROS_404_ANALYSIS and PHIGROS_404_IPA to run the optional artifact checks.
"""
from pathlib import Path
import os
import re
import struct
import unittest
from zipfile import ZipFile

SOURCE = Path(__file__).resolve().parents[1] / 'PhiMod/Sources/PMNativeOSDetail.mm'
ANALYSIS = os.environ.get('PHIGROS_404_ANALYSIS')
IPA = os.environ.get('PHIGROS_404_IPA')


class NativeOSDetail(unittest.TestCase):
    def test_adapter_is_presentation_only(self):
        source = SOURCE.read_text('utf-8-sig')
        for method in ('Play', 'Back', 'StartNextScene', 'SaveInt', 'SaveBool', 'SaveFloat',
                       'ShowHint', 'OpenSongDetailNormal', 'OnDisable'):
            self.assertNotIn('"' + method + '"', source)
        for dependency in ('UIKit', 'UIGraphics', 'ReadPixels', 'ScreenCapture'):
            self.assertNotIn(dependency, source)
        self.assertIn('r.call(c,"Open",{"SongSelectorItem","System.Int32","System.Boolean"}', source)
        self.assertIn('r.call(c,"UpdateInfo",{"SongSelectorItem","System.Int32"}', source)
        self.assertIn('r.call(c,"Close")', source)
        self.assertIn('r.call(c,"UpdateInfo",{"System.Boolean"}', source)
        self.assertIn('current->id!=token', source)

    @unittest.skipUnless(ANALYSIS, 'requires 4.0.4 dump and binary')
    def test_metadata_and_native_side_effects(self):
        base = Path(ANALYSIS)
        dump = (base / 'dump.cs').read_text('utf-8-sig')
        def body(cls):
            return re.search(r'^public class ' + cls + r' [^\n]*\n\{.*?^\}', dump, re.M | re.S)[0]
        def addr(cls, signature):
            return int(re.search(r'// RVA: 0x(\w+)[^\n]*\n\s*' + re.escape(signature), body(cls))[1], 16)
        c8, c9 = 'Chapter8SelectMusicControl', 'Chapter9SongDetailsControl'
        self.assertEqual(addr(c9, 'public void Open(SongSelectorItem song, int level, bool useNarrowFont)'), 0x1556e88)
        self.assertEqual(addr(c9, 'public void UpdateInfo(SongSelectorItem song, int level)'), 0x1557cec)
        self.assertEqual(addr(c9, 'public void Close()'), 0x1557b20)
        update = addr(c8, 'private void UpdateInfo(bool jump)')
        show_hint = addr('Chapter8HintControl', 'public void ShowHint(int id, bool isAlt, bool showHint = False)')
        self.assertIn('public int displayedLength;', body('WaveSource'))
        for field in ('Text lengthText;', 'Text contentText;', 'WaveDisplay waveDisplay;'):
            self.assertIn(field, body('Chapter8HintControl'))
        with (base / 'UnityFramework').open('rb') as f:
            def direct_targets(start, end):
                f.seek(start)
                targets = set()
                for i, (word,) in enumerate(struct.iter_unpack('<I', f.read(end-start))):
                    if word >> 26 in (5, 37):
                        offset = word & 0x3ffffff
                        if offset & 0x2000000: offset -= 0x4000000
                        targets.add(start + 4*i + 4*offset)
                return targets
            self.assertTrue({update, show_hint} <= direct_targets(0x1539778, 0x1539d34))
            self.assertIn(0x1492578, direct_targets(show_hint, 0x15349bc))  # GetableItem.Get
            self.assertTrue({0x14b04f8,0x14b0410,0x14b058c} <= direct_targets(0x1537c20,0x1537f28))

    @unittest.skipUnless(IPA, 'requires serialized 4.0.4 IPA')
    def test_scene_donors(self):
        with ZipFile(IPA) as z:
            root = 'Payload/Phigros.app/Data/'
            scenes = re.findall(rb'Assets/[^\x00\r\n]+?\.unity', z.read(root+'globalgamemanagers'))
            for n, scene, fields in ((23, 'Chapter8SelectMusic', (b'SongDetailCanvas', b'SPEECH_TO_TEXT')),
                                     (28, 'Chapter9SelectMusic', (b'SongDetails', b'SongDetailsLocked')),
                                     (30, 'Chapter9Phase2', (b'SongDetails', b'SongDetailsLocked'))):
                self.assertTrue(scenes[n].endswith(('/'+scene+'.unity').encode()))
                data = z.read(root+'level'+str(n))
                for field in fields: self.assertIn(field, data)


if __name__ == '__main__': unittest.main()
