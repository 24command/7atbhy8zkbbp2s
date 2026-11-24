"""Pin the Play iterator yields and the cold presentation donors used by the adapter."""
import json
import os
from pathlib import Path
import re
import struct
import unittest
from zipfile import ZipFile

from test_native_os_chrome import Graph, ref, u32
from native_os_donors import SerializedFile, dormant_scene

IOS = Path(__file__).resolve().parents[1]


class RetailPlay(unittest.TestCase):
    def test_arm_and_frame_capture_boundary(self):
        impl = (IOS / 'PhiMod/Sources/PMNativeOSPlayTransition.inc').read_text('utf-8-sig')
        commit = impl.split('void commit(Play &p)', 1)[1].split('void tick(', 1)[0]
        self.assertLess(commit.index('p.arm(r,p.info)'), commit.index('r.put(g,"levelStartInfo",p.info)'))
        self.assertLess(commit.index('r.put(g,"background",p.bgGO)'), commit.index('"StartCoroutine"'))
        for call in ('"Play"', '"NormalStart"', '"Flash"', '"SaveManagement"', 'leaveToSongSelector', 'requestSingle('):
            self.assertNotIn(call, impl)

    def test_private_runner_load_deadline_and_cancellation(self):
        impl = (IOS / 'PhiMod/Sources/PMNativeOSPlayTransition.inc').read_text('utf-8-sig')
        prepare = impl.split('void prepare(', 1)[1].split('float clock(', 1)[0]
        self.assertIn('component(r,p.panel,"UnityEngine.UI","CanvasScaler")', prepare)
        self.assertLess(prepare.index('flag(r,p.parking,"SetActive",true)'), prepare.index('"get_isActiveAndEnabled"'))
        self.assertIn('for(P loader:{p.bg,p.cover})', prepare)
        self.assertIn('r.call(loader,"LoadImage",{"System.String"},{key})', prepare)
        self.assertNotIn('"set_Code"', prepare)
        self.assertRegex(prepare, r'job \|\| .*"get_ImageLoaded"')
        for loader in ('bg', 'cover'):
            self.assertIn(f'r.call(p->{loader},"get_ImageLoaded")', impl)
            self.assertIn(f'r.call(p->{loader},"get__settedFile")', impl)
        self.assertNotIn('"loadImageOver"', impl)
        self.assertEqual(impl.count('"StartCoroutine"'), impl.count('runner,"StartCoroutine"'))
        tick = impl.split('void tick(', 1)[1].split('void loaded(', 1)[0]
        precommit = tick.split('"Play: source visit interrupted"', 1)[1]
        self.assertLess(precommit.index('systemUptime<p->deadline'), precommit.index('if(!p->shown)'))
        finish = impl.split('void finish(', 1)[1].split('void commit(', 1)[0]
        self.assertLess(finish.index('p->runner,"StopAllCoroutines"'), finish.index('p->parking,"SetActive",false'))
        self.assertLess(finish.index('p->runner,"StopAllCoroutines"'), finish.index('p->finished(routed)'))

    @unittest.skipUnless(os.getenv('PHIGROS_404_ANALYSIS'), 'requires retail 4.0.4 analysis')
    def test_native_play_edges_and_resume_states(self):
        base = Path(os.environ['PHIGROS_404_ANALYSIS'])
        methods = {e['Address']: e['Name'] for e in json.loads((base / 'script.json').read_bytes())['ScriptMethod']}
        literals = {int(e['address'], 16): e['value'] for e in json.loads((base / 'stringliteral.json').read_bytes())}
        with (base / 'UnityFramework').open('rb') as f:
            def word(pc):
                f.seek(pc)
                return struct.unpack('<I', f.read(4))[0]

            def call(pc, method):
                ins = word(pc)
                self.assertIn(ins >> 26, (5, 37))
                imm = ins & 0x3ffffff
                self.assertTrue(methods[pc + 4*(imm - (1 << 26) if imm & 1 << 25 else imm)].endswith(method), method)

            # Direct LoadImage uses the populated AssetRef.obj immediately for PM imports,
            # or yields WaitForPrepare. Both paths install the sprite and set ImageLoaded.
            call(0x15ca83c, 'AssetStore$$ReleaseAndGetNew<object>')
            self.assertEqual(word(0x15ca848), 0xf9401d00)  # ldr x0, [x8,#0x38] (obj)
            self.assertEqual(word(0x15ca87c), 0x34fff360)  # cbz w0, 0x15ca6e8 (install)
            call(0x15ca894, 'AssetStore.AssetRef<object>$$get_WaitForPrepare')
            call(0x15ca714, 'Image$$set_sprite')
            call(0x15ca728, 'SpriteRenderer$$set_sprite')
            for store in (0x15ca758, 0x15ca780):
                self.assertEqual(word(store-4), 0x52800028)  # mov w8,#1
                self.assertEqual(word(store), 0x39014668)   # strb w8,[x19,#0x51]
            self.assertEqual(word(0x15c9f70), 0x39414400)   # get_ImageLoaded reads +0x51
            self.assertEqual(word(0x15cabd4), 0x3901e688)   # crossfade's loadImageOver at +0x79
            for pc in (0x14f521c, 0x15166d4):
                call(pc, 'Chapter9SongLevelStartControl$$GameStart')
            call(0x15389c0, 'SaveManagement$$LoadBool')
            call(0x14fb3c8, 'Camera$$Render')
            for start, seconds, state, end_frame, capture, mask, literal, load in (
                (0x153b334,0x153b9f0,4,0x153bca8,0x153b608,0x153b660,0x153b6d0,0x153b6e0),
                (0x14fb658,0x14fb940,3,0x14fba0c,0x14fb77c,0x14fb7d4,0x14fb844,0x14fb854),
            ):
                self.assertRegex(methods[start], r'<StartAnimation>d__\d+\$\$MoveNext$')
                call(seconds, 'WaitForSeconds$$.ctor')
                # MOV W8, #state after yielding the one-second fade-out.
                self.assertEqual(word(seconds+12), 0x52800008 | state << 5)
                call(end_frame, 'WaitForEndOfFrame$$.ctor')
                call(capture, 'Texture2D$$ReadPixels')
                call(mask, 'RawImage$$set_texture')
                page, add = word(literal), word(literal+4)
                displacement = ((page >> 5 & 0x7ffff) << 2) | (page >> 29 & 3)
                slot = (literal & ~4095) + (displacement << 12) + (add >> 10 & 4095)
                self.assertEqual(literals[slot], 'Level')
                call(load, 'SceneManager$$LoadScene')

    @unittest.skipUnless(os.getenv('PHIGROS_404_IPA'), 'requires retail 4.0.4 IPA')
    def test_entrance_graph_and_background_prefab(self):
        with ZipFile(os.environ['PHIGROS_404_IPA']) as ipa:
            def asset(file): return ipa.read('Payload/Phigros.app/Data/'+file)
            managers = SerializedFile(asset('globalgamemanagers'))
            settings, = [d for t,d in managers.objects.values() if managers.types[t] == 141]
            self.assertEqual(re.findall(rb'Assets/[^\x00-\x1f]+?\.unity',settings)[12], b'Assets/Phigros2/Level/Level.unity')
            scripts = SerializedFile(asset('globalgamemanagers.assets'))
            for oid, name in ((96,b'CanvasScaler'), (146,b'AddressableImageLoaderWithLowResPreview'),
                              (1086,b'AddressableImageLoader')):
                script = scripts.objects[oid][1]
                self.assertEqual(script[4:4+u32(script,0)], name)
            for level in (23,28,30):
                with self.subTest(level=level):
                    g = Graph(dormant_scene(asset('level'+str(level))))
                    panel = 'SongDetailCanvas' if level == 23 else 'UI/StartInfoCanvas'
                    self.assertEqual(g.script(panel,96)[12], 1)  # enabled on the private canvas root
                    preview = g.script(panel+'/StartInfos/SongsCover/Cover',146)
                    self.assertEqual(preview[12], 1)
                    # Unity aligns each serialized bool here. loadedImage, loadImageOver
                    # and loadedLowResImage all start false on the entrance clone.
                    self.assertEqual(preview[36:48:4], bytes(3))
                    panel = 'PhiModStockOSHost/'+panel
                    face = panel+'/StartInfos'
                    def kind(i): return g.file.types[g.file.objects[i][0]]
                    self.assertIn(95, map(kind,g.by_path[face]))
                    self.assertIn(95, map(kind,g.by_path[face+'/StartAnimation']))
                    self.assertIn(95, map(kind,g.by_path[face+'/StartAnimation/moreInfos/content/loading']))
                    path = 'PhiModStockOSHost/SceneControl' if level == 23 else face
                    ctl, = [g.file.objects[i][1] for i in g.by_path[path] if kind(i)==114]
                    offset = 944 if level == 23 else 176
                    fid, oid = ref(ctl,offset)
                    ext = re.findall(rb'(?:[\w.]+\.assets|Library/unity default resources)\0', g.file.tail)
                    shared = SerializedFile(asset(ext[fid-1][:-1].decode()))
                    k, loader = shared.objects[oid]
                    self.assertEqual(shared.types[k],114)
                    self.assertEqual(ref(loader,16), (1,1086))
                    obj = shared.objects[ref(loader,0)[1]][1]
                    self.assertEqual(obj[-1], 1)  # independently active background prefab
                    components = [shared.objects[ref(obj,4+12*i)[1]][0] for i in range(u32(obj,0))]
                    self.assertIn(212, [shared.types[k] for k in components])  # SpriteRenderer
                    offset = 8 + 12*u32(obj,0)
                    self.assertEqual(obj[offset+4:offset+4+u32(obj,offset)], b'background')
                    branches = ['SelectedSong', 'SongsCover/Cover', 'StartAnimation/moreInfos']
                    if level != 23:
                        branches.extend(['StartAnimation/BlurLayers/MapBlur', 'StartAnimation/BlurLayers/BackgroundBlur'])
                    for sub in branches:
                        self.assertIn(face+'/'+sub, g.by_path)
