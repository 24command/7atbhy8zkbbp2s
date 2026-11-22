"""Stock donor contracts for the UI exposed by PMNativeOSChrome.
Set PHIGROS_404_IPA to test the actual serialized GameObjects (no Unity install).
"""
import os
import re
from pathlib import Path
import struct
import sys
import unittest
from zipfile import ZipFile

IOS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IOS / 'tools'))
from native_os_donors import SerializedFile, dormant_scene


def u32(data, pos):
    return struct.unpack_from('<I', data, pos)[0]


def ref(data, pos):
    return struct.unpack_from('<iq', data, pos)


class Graph:
    def __init__(self, data):
        self.file = SerializedFile(data)
        parents, names, components, objects = {}, {}, {}, {}
        for tr, (kind, data) in self.file.objects.items():
            if self.file.types[kind] not in (4, 224):
                continue
            parents[tr] = ref(data, 56 + 12 * u32(data, 52))[1]
            obj = self.file.objects[ref(data, 0)[1]][1]
            n = u32(obj, 0)
            off = 8 + n * 12
            names[tr] = obj[off+4:off+4+u32(obj, off)].decode()
            objects[tr] = ref(data, 0)[1]
            components[tr] = [ref(obj, 4 + i*12)[1] for i in range(n)]
        def path(tr):
            return (path(parents[tr]) + '/' if parents[tr] else '') + names[tr]
        self.owners = {oid: path(tr) for tr, entries in components.items() for oid in [objects[tr], *entries]}
        self.by_path = {path(tr): entries for tr, entries in components.items()}

    def components(self, path):
        for oid in self.by_path['PhiModStockOSHost/' + path]:
            kind, data = self.file.objects[oid]
            yield self.file.types[kind], data

    def script(self, path, script):
        result, = [d for kind, d in self.components(path) if kind == 114 and ref(d,16) == (1,script)]
        return result


class ChromeTests(unittest.TestCase):
    def test_activation_and_listener_boundaries(self):
        source = (IOS/'PhiMod/Sources/PMNativeOSChrome.mm').read_text()
        for a, b in [('bootstrap(*c)', 'active(r,c->stage,true)'),
                     ('sanitize(r,c.copy)', 'active(r,c.copy,true)'),
                     ('c.input=false;', 'c.face=face; c.slots=mask; c.input=input;')]:
            self.assertLess(source.index(a), source.index(b))
        for checked in ('set_onClick','set_fireEvents','useOnComplete','set_firstSelectedGameObject',
                        'pmnativeosscene::activeRoot(r)==root', 'Chrome: unreviewed component'):
            self.assertIn(checked, source)
        for forbidden in ('"ToSongList"','"SetLevel"','"OnDisable"','PlayerPrefs','RemoveAllListeners','FindObjectOfType'):
            self.assertNotIn(forbidden, source)

    def test_gate_survives_presentation_and_owned_presses(self):
        source = (IOS/'PhiMod/Sources/PMNativeOSChrome.mm').read_text()
        self.assertIn('policy::visible(face,b.action.intent,c.allowList)',source)
        self.assertIn('policy::enabled(face,input,mask,b.action,c.allowList)',source)
        self.assertIn('policy::enabled(current->face,current->input,current->slots,b.action,current->allowList)',source)
        self.assertEqual(source.count('current->allowList='),1)
        self.assertIn('Press result{Intent::Consumed,-1}',source)

    @unittest.skipUnless(os.getenv('PHIGROS_404_IPA'), 'needs stock 4.0.4 IPA')
    def test_open_dependencies_and_render_modes(self):
        # Offsets into serialized 4.0.4 MonoBehaviour payloads, not C++ fields.
        c8 = dict(songDetailCanvas=68, songNameText=608, songArtistText=620,
                  illustratorText=776, charterText=764, songCoverImage=656, levelBarController=668,
                  levelSliderController=680, ratingDisplayController=908, recordInfoBar=824,
                  unlockInfoBar=836, difficulty=848, level=860, score=872, acc=884,
                  chapter8HintControl=920, songDetailTweenControl=932)
        c9 = dict(zip(('titleText','composerText','scoreText','accText','songCoverImage','levelBarController',
                       'levelSliderController','ratingDisplayController','animator','canvasGroup','illustrationSizeControl'),
                      range(56,177,12)))
        detail = (IOS/'PhiMod/Sources/PMNativeOSDetail.mm').read_text()
        checked = re.findall(r'for\(const char \*key:\{([^}]+)\}\)within\(r,root,member\(r,c,key\)\)',detail)
        self.assertCountEqual([set(re.findall(r'"(\w+)"',keys)) for keys in checked], [set(c8),set(c9)])
        with ZipFile(os.environ['PHIGROS_404_IPA']) as ipa:
            for scene in (23,28,30):
                with self.subTest(scene=scene):
                    g=Graph(dormant_scene(ipa.read(f'Payload/Phigros.app/Data/level{scene}')))
                    canvas='UICanvas' if scene==23 else 'UI/UICanvas'
                    data, = [d for k,d in g.components(canvas) if k==223]
                    self.assertEqual(u32(data,16),int(scene==23))  # screen-space camera or overlay
                    if scene==23:
                        self.assertEqual(g.owners[ref(data,20)[1]],'PhiModStockOSHost/Main Camera')
                    panel='SongDetailCanvas' if scene==23 else canvas+'/SongDetails'
                    controller=g.script('SceneControl',913) if scene==23 else g.script(panel,1569)
                    def contained(data,offset):
                        file,oid=ref(data,offset)
                        self.assertEqual(file,0)
                        path=g.owners[oid]
                        prefix='PhiModStockOSHost/'+panel
                        self.assertTrue(path==prefix or path.startswith(prefix+'/'),path)
                        return g.file.objects[oid][1]
                    fields=c8 if scene==23 else c9
                    for name,offset in fields.items():
                        with self.subTest(field=name): contained(controller,offset)
                    nested=contained(controller,fields['chapter8HintControl' if scene==23 else 'illustrationSizeControl'])
                    for offset in range(32,104 if scene==23 else 68,12): contained(nested,offset)
                    if scene==23:
                        self.assertEqual(g.owners[ref(controller,692)[1]],'PhiModStockOSHost/UICanvas/Play')

    @unittest.skipUnless(os.getenv('PHIGROS_404_IPA'), 'needs stock 4.0.4 IPA')
    def test_exact_donor_controls(self):
        with ZipFile(os.environ['PHIGROS_404_IPA']) as ipa:
            for scene in (22,23,28,30):
                with self.subTest(scene=scene):
                    g=Graph(dormant_scene(ipa.read(f'Payload/Phigros.app/Data/level{scene}')))
                    self.assertIn(20, [kind for kind,_ in g.components('Main Camera')])
                    for script in (793,541): g.script('EventSystem',script)
                    canvas={22:'Panels/FolderPanel/Canvas',23:'UICanvas'}.get(scene,'UI/UICanvas')
                    self.assertIn(223,[k for k,_ in g.components(canvas)])
                    g.script(canvas,1421)  # stock GraphicRaycaster
                    def button(path, method):
                        self.assertIn(method.encode(),g.script(path,530))
                    if scene==22:
                        button(canvas+'/Overlay/Back','BackToChapter')
                        self.assertFalse(any(p.endswith('/MenuFull/ToggleMode') for p in g.by_path))
                        continue
                    button(canvas+'/Back','Back')
                    menu={23:'UILowCanvas',28:canvas+'/BottomMenu',30:canvas+'/Menu'}[scene]
                    button(menu+'/MenuFull/ToggleMode','ToSongList')
                    if scene==23:
                        bar='SongDetailCanvas/SongCoverPanel/LevelBar/'
                        button(canvas+'/Play','Play')
                        self.assertEqual(g.script('SceneControl',913)[12],0)
                        # Every tween dependency is in the cloned detail panel or
                        # Play. A new reference escaping the clone needs review.
                        for path in g.by_path:
                            if not path.startswith('PhiModStockOSHost/SongDetailCanvas/'): continue
                            for kind,data in g.components(path.split('/',1)[1]):
                                if kind!=114 or ref(data,16)!=(1,682): continue
                                file,target=ref(data,36)
                                self.assertEqual(file,0)
                                owner,=[p for p,items in g.by_path.items() if target in items]
                                self.assertTrue(owner.startswith('PhiModStockOSHost/SongDetailCanvas') or owner.endswith('/UICanvas/Play'),owner)
                    else:
                        g.script(canvas+'/SongDetails',1569)
                        button(canvas+'/SongDetails/Play','Play')
                        bar=canvas+'/SongDetails/DifficultyBar/Contents/Bar/'
                    for level in ('EZ','HD','IN','AT'): button(bar+level,'SetLevel')


if __name__=='__main__': unittest.main()
