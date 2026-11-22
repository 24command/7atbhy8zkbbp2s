"""Exclusive stock OS copies, arrival ownership, and ordinary selector return."""
import hashlib
import json
import os
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile

IOS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(IOS / 'tools'))
import native_os_donors as donors


def settings(sf):
    return next(data for t, data in sf.objects.values() if sf.types[t] == 141)


def roots(sf):
    result = {}
    for oid, (t, data) in sf.objects.items():
        if sf.types[t] in (4, 224):
            go, = struct.unpack_from('<q', data, 4)
            count, = struct.unpack_from('<I', data, 52)
            parent, = struct.unpack_from('<q', data, 60 + 12*count)
            if not parent:
                result[oid] = go
    return result


class SceneHostContracts(unittest.TestCase):
    def test_runtime_routes_match_packager(self):
        source = (IOS / 'PhiMod/Sources/PMNativeOSScene.mm').read_text('utf-8-sig')
        for index, (_, name, _) in enumerate(donors.DONORS, 38):
            self.assertIn(f'{index}, "{donors.PREFIX}PM{name.split("/")[-1]}"', source)
        self.assertIn('Assets/Phigros2/SongSelector/SongSelector', source)
        self.assertIn('"/PhiModStockOSHost"', source)
        self.assertIn('int single = 0;', source)
        self.assertIn('requestSingle(r, d->index)', source)
        self.assertIn('requestSingle(r, 7)', source)
        self.assertIn('LoadSceneAsyncNameIndexInternal', source)
        self.assertNotIn('CanStreamedLevelBeLoaded', source)
        self.assertIn('sceneHandle(r, r.call(found, "get_scene")) == handle', source)
        self.assertIn('current.handle != handle', source)

    def test_controller_gates_cover_start_and_teardown(self):
        manifest = json.loads((IOS / 'tools/gameplay_hook_manifest.json').read_text())
        names = {e['name'] for e in manifest}
        for cls, methods in {
            'SaturnOSControl': ['Start'],
            'Chapter8SelectMusicControl': ['Start', 'Update', 'OnDisable'],
            'Phigros2.Chapter9.Chapter9Phase1Control': ['Awake', 'OnEnable', 'Start', 'Update', 'OnDisable', 'OnDestroy'],
            'Phigros2.Chapter9.Scripts.Chapter9Phase2Control': ['Awake', 'Start', 'OnDestroy'],
            'UnityEngine.SceneManagement.SceneManager': ['Internal_SceneLoaded', 'Internal_SceneUnloaded'],
        }.items():
            for method in methods:
                self.assertIn(f'{cls}.{method}', names)
        source = (IOS / 'PhiMod/Sources/PMHookBackend.mm').read_text()
        start = source.split('void onMainlinePhase1Start', 1)[1].split('void onMainlinePhase1ToPhase2', 1)[0]
        self.assertLess(start.index('ownsController'), start.index('orig<VoidFn>'))

    @unittest.skipUnless(os.getenv('PHIGROS_404_IPA'), 'requires stock 4.0.4 IPA')
    def test_packaged_hierarchies(self):
        with ZipFile(os.environ['PHIGROS_404_IPA']) as ipa, tempfile.TemporaryDirectory() as tmp:
            data = Path(tmp)
            def read(name):
                return ipa.read('Payload/Phigros.app/Data/' + name)
            for name in ['globalgamemanagers'] + [f'level{n}' for n, _, _ in donors.DONORS]:
                (data / name).write_bytes(read(name))
            donors.install(data)
            before = donors.SerializedFile(read('globalgamemanagers'))
            after = donors.SerializedFile((data / 'globalgamemanagers').read_bytes())
            old, old_tail = donors.scene_paths(settings(before))
            new, new_tail = donors.scene_paths(settings(after))
            self.assertEqual((new[:38], new_tail), (old, old_tail))
            self.assertEqual(len(new), 42)
            self.assertEqual(old[7], 'Assets/Phigros2/SongSelector/SongSelector.unity')
            self.assertIn('level7', [n.split('/')[-1] for n in ipa.namelist()])
            scripts = donors.SerializedFile(read('globalgamemanagers.assets'))
            for i, (n, name, digest) in enumerate(donors.DONORS, 38):
                with self.subTest(scene=name):
                    self.assertEqual(old[n], f'Assets/Phigros2/{name}.unity')
                    self.assertEqual(new[i], f'{donors.PREFIX}PM{name.split("/")[-1]}.unity')
                    source = (data / f'level{n}').read_bytes()
                    self.assertEqual(hashlib.sha256(source).hexdigest(), digest)
                    stock = donors.SerializedFile(source)
                    host = donors.SerializedFile((data / f'level{i}').read_bytes())
                    self.assertEqual(host.tail, stock.tail)  # shared assets, script refs and externals
                    self.assertEqual(len(host.objects), len(stock.objects) + 2)
                    ((transform, anchor),) = roots(host).items()
                    self.assertNotIn(anchor, stock.objects)
                    self.assertIn(donors.string(donors.ROOT_NAME), host.objects[anchor][1])
                    self.assertEqual(host.objects[anchor][1][-1], 1)
                    original = roots(stock)
                    members = host.objects[transform][1]
                    children, = struct.unpack_from('<I', members, 52)
                    self.assertEqual(set(original), {struct.unpack_from('<q', members, 60+12*j)[0] for j in range(children)})
                    for child, go in original.items():
                        self.assertEqual(host.objects[go][1][-1], 0)
                        self.assertEqual(host.objects[go][1][:-1], stock.objects[go][1][:-1])
                    changed = []
                    for oid in stock.objects.keys() - original.keys() - set(original.values()):
                        if stock.objects[oid] == host.objects[oid]:
                            continue
                        t, obj = host.objects[oid]
                        self.assertEqual(host.types[t], 114)
                        self.assertEqual(obj, stock.objects[oid][1][:12] + b'\0' + stock.objects[oid][1][13:])
                        file_id, script = struct.unpack_from('<iq', obj, 16)
                        self.assertEqual(file_id, 1)
                        mono_script = scripts.objects[script][1]
                        size, = struct.unpack_from('<I', mono_script)
                        changed.append(mono_script[4:4+size].decode())
                    self.assertEqual(changed, [{22: 'SaturnOSControl', 23: 'Chapter8SelectMusicControl',
                        28: 'Chapter9Phase1Control', 30: 'Chapter9Phase2Control'}[n]])
            with self.assertRaises(ValueError):
                donors.install(data)


if __name__ == '__main__':
    unittest.main()
