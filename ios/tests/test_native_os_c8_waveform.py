"""C8 private graphic binding and the serialized iOS 4.0.4 waveform contract."""
import os
from pathlib import Path
import struct
import unittest
from zipfile import ZipFile

from test_native_os_chrome import Graph, dormant_scene, ref

SOURCES = Path(__file__).resolve().parents[1] / 'PhiMod/Sources'


class C8Waveform(unittest.TestCase):
    def test_card_reaches_private_graphic(self):
        program = (SOURCES / 'PMNativeOSProgram.mm').read_text()
        self.assertIn('row[@"waveform"] = [NSData dataWithBytes:c->waveform', program)
        self.assertIn('detail[@"waveform"] = card[@"waveform"]', program)
        coordinator = (SOURCES / 'PMNativeOSCoordinator.mm').read_text()
        self.assertRegex(coordinator, r'panel::Speech speech\{[^}]*card\[@"waveform"\]')
        self.assertIn('row.row,row.slot,speech,false,row.cover', coordinator)
        detail = (SOURCES / 'PMNativeOSDetail.mm').read_text()
        self.assertIn('c8Waveform(r,root,hint,s.waveform)', detail)
        self.assertIn('c8Speech(r,root,member(r,c,"chapter8HintControl"),speech)', detail)
        wave = detail.split('void c8Waveform(', 1)[1].split('void c8Speech(', 1)[0]
        steps = ['within(r,root,wave)', 'active(r,object,false)', 'array_new', 'copy_from_unmanaged',
                 'r.put(wave,"data",data.get())', '"set_raycastTarget",false', 'active(r,object,true)',
                 '"set_enabled",true', '"SetVerticesDirty"']
        offsets = [wave.index(step) for step in steps]
        self.assertEqual(offsets, sorted(offsets))

    @unittest.skipUnless(os.getenv('PHIGROS_404_IPA'), 'requires local stock IPA')
    def test_private_copy_contains_stock_100_bar_graphic(self):
        with ZipFile(os.environ['PHIGROS_404_IPA']) as ipa:
            graph = Graph(dormant_scene(ipa.read('Payload/Phigros.app/Data/level23')))
        controller = graph.script('SceneControl', 913)
        hint = graph.file.objects[ref(controller, 920)[1]][1]
        wave_id = ref(hint, 32)[1]
        self.assertTrue(graph.owners[wave_id].endswith('/SongInfo/Hint/Content/Wave'))
        graphic = graph.file.objects[wave_id][1]
        self.assertEqual(ref(graphic, 16), (1, 1105))
        width, gap, count = struct.unpack_from('<ffI', graphic, 88)
        self.assertEqual((width, gap, count), (3, 3, 100))
        bars = struct.unpack_from('<100f', graphic, 100)
        self.assertTrue(all(0 <= v <= 1 for v in bars))


if __name__ == '__main__':
    unittest.main()
