"""Verify the stock assets shared by the phase-two authored map."""
import os
import re
import unittest
from zipfile import ZipFile

from test_native_os_chrome import Graph, IOS, dormant_scene, ref, u32
from native_os_donors import SerializedFile


class C9PhaseTwo(unittest.TestCase):
    def test_selected_route_reaches_entry_chrome_and_return(self):
        src = IOS / 'PhiMod/Sources'
        coord = (src / 'PMNativeOSCoordinator.mm').read_text('utf-8-sig')
        chrome = (src / 'PMNativeOSChrome.mm').read_text('utf-8-sig')
        cut = (src / 'PMNativeOSManualTransition.inc').read_text('utf-8-sig')
        self.assertIn('program.page->nativePhase == 2 ? scene::Route::C9Phase2 : scene::Route::C9', coord)
        self.assertIn('scene::enter(r,chapterRoute(),arrived)', coord)
        self.assertIn('chrome::open(r,visit,route,root,chromeView)', coord)
        self.assertIn('case scene::Route::C9Phase2: type = r.type("Phigros2.Chapter9.Scripts","Chapter9Phase2Control")', cut)
        self.assertIn('if (c.route==Route::C9Phase2) c.backdrop=mountPhaseTwoBackdrop(c)', chrome)
        self.assertIn('active(r,c.backdrop,face==Face::Map)', chrome)

    @unittest.skipUnless(os.getenv('PHIGROS_404_IPA'), 'requires stock 4.0.4 IPA')
    def test_dormant_map_art(self):
        impl = (IOS / 'PhiMod/Sources/PMNativeOSC9Backdrop.inc').read_text()
        path, = re.findall(r'find\(r,c.host,"([^"]+)"\)', impl)
        with ZipFile(os.environ['PHIGROS_404_IPA']) as ipa:
            root = 'Payload/Phigros.app/Data/'
            graph = Graph(dormant_scene(ipa.read(root + 'level30')))
            image = graph.script(path, 1609)
            shared = SerializedFile(ipa.read(root + 'sharedassets30.assets'))
            externals = re.findall(rb'(?:[\w.]+\.assets|Library/unity default resources)\0', graph.file.tail)
            for offset, kind, name in ((32, 21, b'MapRedToAllChannel'), (88, 213, b'NoiseBg')):
                file_id, object_id = ref(image, offset)
                self.assertEqual(externals[file_id - 1], b'sharedassets30.assets\0')
                type_id, data = shared.objects[object_id]
                self.assertEqual((shared.types[type_id], data[4:4 + u32(data, 0)]), (kind, name))


if __name__ == '__main__':
    unittest.main()
