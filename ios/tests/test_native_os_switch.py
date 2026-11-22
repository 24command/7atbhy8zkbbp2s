"""Check the stock selector binding against the serialized 4.0.4 level."""
import os
from pathlib import Path
import struct
import unittest
from zipfile import ZipFile

from test_native_os_chrome import Graph, ref, u32

SOURCE = Path(__file__).resolve().parents[1] / 'PhiMod/Sources/PMNativeOSSwitch.mm'


class SwitchTests(unittest.TestCase):
    def test_scope_and_restoration(self):
        source = SOURCE.read_text(encoding='utf-8')
        bind = source.split('bool bind(', 1)[1].split('void show(', 1)[0]
        self.assertLess(bind.index('"chapterCode"'), bind.index('"toggleSimulateButton"'))
        self.assertLess(bind.index('pin(r, stock)'), bind.index('clickEvent(r, button, empty)'))
        self.assertLess(bind.index('current.modified = true'), bind.index('clickEvent(r, button, empty)'))
        release = source.split('void release(', 1)[1].split('bool bind(', 1)[0]
        for state in ('stockClick', 'stockActive', 'stockInteractable'):
            self.assertLess(release.index('current.' + state), release.index('gchandle_free'))
        for unwanted in ('FindObjectOfType', 'Instantiate', 'RemoveAllListeners', 'ToSimulateMode', 'LoadScene'):
            self.assertNotIn('"' + unwanted + '"', source)

    @unittest.skipUnless(os.getenv('PHIGROS_404_IPA'), 'needs stock 4.0.4 IPA')
    def test_stock_selector_button_and_listener(self):
        with ZipFile(os.environ['PHIGROS_404_IPA']) as ipa:
            graph = Graph(ipa.read('Payload/Phigros.app/Data/level7'))
        path = 'Canvas (1)/TopBar/ToggleSimulate'
        self.assertIn(path + '/Icon', graph.by_path)
        button, = [data for oid in graph.by_path[path]
                   for kind, data in [graph.file.objects[oid]]
                   if graph.file.types[kind] == 114 and ref(data, 16) == (1, 530)]
        go = ref(button, 0)
        self.assertEqual(graph.file.objects[go[1]][1][-1], 0)  # activeSelf at rest
        self.assertEqual(u32(button, 308), 1)  # one serialized persistent call
        target = ref(button, 312)
        self.assertEqual(target[0], 0)
        self.assertEqual(button[332:346], b'ToSimulateMode')
        selector = graph.file.objects[target[1]][1]
        self.assertEqual(ref(selector, 16), (1, 753))  # SongSelector
        self.assertEqual(ref(selector, 1192), go)  # selector.toggleSimulateButton


if __name__ == '__main__':
    unittest.main()
