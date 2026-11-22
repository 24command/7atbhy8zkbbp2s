"""Check the transition against the supplied 4.0.4 player and scene assets."""
import os
from pathlib import Path
import re
import struct
import sys
import unittest
from zipfile import ZipFile

IOS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IOS / 'tools'))
from native_os_donors import SerializedFile


class ManualSwitch404(unittest.TestCase):
    @unittest.skipUnless(os.getenv('PHIGROS_404_ANALYSIS'), 'requires local 4.0.4 player')
    def test_iterators_and_visual_instantiation(self):
        base = Path(os.environ['PHIGROS_404_ANALYSIS'])
        dump = (base / 'dump.cs').read_text('utf-8-sig')
        with (base / 'UnityFramework').open('rb') as binary:
            def word(pc):
                binary.seek(pc)
                return struct.unpack('<I', binary.read(4))[0]

            def call(pc, target):
                self.assertEqual(word(pc), 0x94000000 | (((target-pc)//4) & 0x3ffffff))

            for cls, action, method, instantiate, wait, delta, load in (
                ('SongSelector', 'ToSimulateMode', 0x15b2490, 0x15b25f8, 0x15c0854, 0x15c08ec, 0x15c08b4),
                ('Chapter8SelectMusicControl', 'ToSongList', 0x153864c, 0x15387d8, 0x153bda8, 0x153be44, 0x153be08),
                ('Chapter9Phase1Control', 'ToSongList', 0x14f443c, 0x14f45d0, 0x14f99ac, 0x14f9a48, 0x14f9a0c),
                ('Chapter9Phase2Control', 'ToSongList', 0x15171c4, 0x1517358, 0x1519d0c, 0x1519da8, 0x1519d6c),
            ):
                with self.subTest(cls=cls):
                    body = re.search(r'^public class '+cls+r' : .*?^}', dump, re.M | re.S)[0]
                    self.assertRegex(body, rf'RVA: 0x{method:X}[^\n]*\n\s*public void {action}\(\)')
                    self.assertIn('GameObject cutOut;', body)
                    call(instantiate, 0x180d62c)  # Object.Instantiate<object>
                    # MOV/MOVK into W8, FMOV S1,W8, FCMP S0,S1, B.LE.
                    bits, = struct.unpack('<I', struct.pack('<f', .67))
                    self.assertEqual(word(wait), 0x52800008 | ((bits & 0xffff) << 5))
                    self.assertEqual(word(wait+4), 0x72a00008 | ((bits >> 16) << 5))
                    self.assertEqual(word(wait+8), 0x1e270101)
                    self.assertEqual(word(wait+12), 0x1e212000)
                    self.assertEqual(word(wait+16) & 0xff00001f, 0x5400000d)
                    call(delta, 0x3983e18)  # UnityEngine.Time.get_deltaTime
                    call(load, 0x39957c8)  # SceneManager.LoadScene

    @unittest.skipUnless(os.getenv('PHIGROS_404_IPA'), 'requires local 4.0.4 IPA')
    def test_all_switches_share_animated_cutout(self):
        with ZipFile(os.environ['PHIGROS_404_IPA']) as ipa:
            def asset(name):
                return SerializedFile(ipa.read('Payload/Phigros.app/Data/'+name))

            for level, script, field in ((7,753,1144), (23,913,32), (28,218,32), (30,199,32)):
                with self.subTest(level=level):
                    scene = asset('level'+str(level))
                    controller, = (d for t,d in scene.objects.values() if scene.types[t] == 114
                                   and struct.unpack_from('<iq',d,16) == (1,script))
                    file_id, obj = struct.unpack_from('<iq', controller, field)
                    externals = re.findall(rb'(?:[\w.]+\.assets|Library/unity default resources)\0', scene.tail)
                    self.assertEqual((externals[file_id-1],obj), (b'sharedassets1.assets\0',9))
            shared = asset('sharedassets1.assets')
            def obj(i, kind):
                t,d = shared.objects[i]
                self.assertEqual(shared.types[t],kind)
                return d
            self.assertIn(b'CutOut',obj(9,1))
            self.assertEqual(struct.unpack_from('<iq',obj(11,95),28),(0,7))  # Animator controller
            self.assertIn(struct.pack('<iq',0,4),obj(7,91))
            self.assertIn(b'CutOut',obj(4,74))  # authored animation clip
