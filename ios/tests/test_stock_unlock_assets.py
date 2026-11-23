"""Set PM_STOCK_IPA and PM_STOCK_DUMP to audit the retail inputs with UnityPy."""
import hashlib
import os
from pathlib import Path
import plistlib
import re
import struct
import unittest
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1] / 'PhiMod'


@unittest.skipUnless(os.getenv('PM_STOCK_IPA') and os.getenv('PM_STOCK_DUMP'), 'requires retail IPA and dump.cs')
class StockUnlockAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import UnityPy
        cls.open_unity = staticmethod(UnityPy.load)
        cls.ipa = zipfile.ZipFile(os.environ['PM_STOCK_IPA'])
        cls.addClassCleanup(cls.ipa.close)
        cls.dump = Path(os.environ['PM_STOCK_DUMP']).read_text(encoding='utf-8-sig')
        scripts = cls.open_unity(cls.ipa.read('Payload/Phigros.app/Data/globalgamemanagers.assets'))
        cls.scripts = {o.path_id:o.read().m_ClassName for o in scripts.objects if o.type.name=='MonoScript'}
        cls.layout = (ROOT / 'Sources/PMStockUnlockLayout.hpp').read_text()
        cls.movies = (ROOT / 'Core/PMStockIntroResolver.h').read_text()

    def data(self, name):
        return self.ipa.read('Payload/Phigros.app/Data/' + name)

    def test_ipa_and_font(self):
        info = plistlib.loads(self.ipa.read('Payload/Phigros.app/Info.plist'))
        self.assertEqual((info['CFBundleShortVersionString'], info['CFBundleVersion']), ('4.0.4', '3'))
        asset = (ROOT / 'Sources/PMStockUnlockAssets.hpp').read_text()
        data = self.data('sharedassets0.assets')
        obj = next(o for o in self.open_unity(data).objects if o.path_id == 50)
        self.assertEqual(obj.type.name, 'Font')
        font = bytes(obj.read().m_FontData)
        self.assertIn(f'],{data.index(font)},{len(font)},', asset)
        self.assertIn(hashlib.sha256(font).hexdigest(), asset)

    def test_scenes_and_clips(self):
        names = ('SongInfoBar','Line','SongNameBar','Level')
        clips = (('Spas_Unlock','spas-unlock'), ('Iga_Main','iga-main'), ('Iga_Loop','iga-loop'),
                 ('Rrharil_Unlock','rrharil-unlock'))
        for scene, chapter, owner in ((8,0,'ChallengeModeControl'), (14,5,'FakeAboutUsControl'),
                                      (15,6,'IgalltaUnlock'), (20,7,'RrharilUnlockControl')):
            with self.subTest(chapter=chapter):
                body = self.dump.split(f'public class {owner} :',1)[1].split('\n}',1)[0]
                self.assertIn('GameObject '+('songInfoCanvas' if chapter else 'overlay')+';',body)
                data = self.data(f'level{scene}')
                sf = next(iter(self.open_unity(data).files.values()))
                objects = sf.objects
                shared_data = self.data(f'sharedassets{scene}.assets')
                shared = next(iter(self.open_unity(shared_data).files.values())).objects
                root = next(o.read() for o in objects.values() if o.type.name=='GameObject' and o.read().m_Name=='SongInfoCanvas')
                control = next(o.get_raw_data() for o in objects.values() if o.type.name=='MonoBehaviour'
                               and self.scripts.get(struct.unpack_from('<q',o.get_raw_data(),20)[0])==owner)
                def reference(offset):
                    file, path = struct.unpack_from('<iq',control,offset)
                    self.assertEqual(file,0)
                    return objects[path].read()
                self.assertEqual(reference({8:192,14:184,15:160,20:108}[scene]).m_Name,'SongInfoCanvas')
                players = {8:[],14:[(160,'Spas_Unlock')],15:[(112,'Iga_Loop'),(124,'Iga_Main')],20:[(56,'Rrharil_Unlock')]}
                for offset, name in players[scene]:
                    ref = reference(offset).m_VideoClip
                    self.assertEqual(sf.externals[ref.file_id-1].path,f'sharedassets{scene}.assets')
                    self.assertEqual(shared[ref.path_id].read().m_Name,name)
                self.assertFalse(root.m_IsActive)
                art = {}
                font_refs = []
                def walk(go):
                    for comp in go.m_Component:
                        obj = objects[comp.component.path_id]
                        if obj.type.name == 'RectTransform':
                            for child in obj.read().m_Children:
                                walk(objects[objects[child.path_id].read().m_GameObject.path_id].read())
                        if obj.type.name == 'MonoBehaviour':
                            raw = obj.get_raw_data()
                            script = struct.unpack_from('<q',raw,20)[0]
                            if script == 362:
                                self.assertEqual(struct.unpack_from('<I',raw,96)[0],4)
                                art[go.m_Name] = obj.byte_start
                            if script == 658:
                                # File/path PPtr for the actual shared text face.
                                font_file = next(i for i,x in enumerate(sf.externals,1) if x.path=='sharedassets0.assets')
                                font_refs.append(struct.pack('<iq',font_file,50) in raw)
                walk(root)
                self.assertEqual(font_refs,[True]*8)
                offsets = '{'+','.join(str(art[k]) for k in names)+'}'
                animator = next(objects[c.component.path_id].read() for c in root.m_Component if objects[c.component.path_id].type.name=='Animator')
                controller = shared[animator.m_Controller.path_id].read()
                if chapter:
                    self.assertEqual(controller.m_Name,'ShowInfoControl')
                else:
                    # ChallengeModeControl carries both EM and ETC controller references.
                    file, path = struct.unpack_from('<iq',control,300)
                    self.assertEqual(sf.externals[file-1].path,'sharedassets8.assets')
                    controller = shared[path].read()
                    self.assertEqual(controller.m_Name,'ShowInfoControlETC')
                clip = shared[controller.m_AnimationClips[0].path_id].read()
                self.assertEqual(clip.m_Name,'ShowInfo' if chapter else 'ShowInfoETC')
                binds = clip.m_ClipBindingConstant.genericBindings
                crc = lambda s: zlib.crc32(s.encode())
                expected = [('SongNameBar','m_AnchoredPosition.x'), ('SongInfoBar','m_AnchoredPosition.x'), ('','m_Alpha')]
                if chapter==7:
                    expected += [('SongInfoBar','m_Color.'+c) for c in 'rgba'] + [('SongNameBar','m_Color.'+c) for c in 'rgb']
                self.assertEqual([(b.path,b.attribute) for b in binds],[(crc(p),crc(a)) for p,a in expected])
                words = clip.m_MuscleClip.m_Clip.data.m_StreamedClip.data
                stream = struct.pack(f'<{len(words)}I',*words)
                manifest = re.sub(r'\s+','',self.layout)
                self.assertIn(f'"{hashlib.sha256(data).hexdigest()}",{offsets},{shared_data.index(stream)},{len(stream)},{len(binds)},"{hashlib.sha256(stream).hexdigest()}"',manifest)
                for obj in shared.values():
                    if obj.type.name!='VideoClip':
                        continue
                    v = obj.read()
                    name = dict(clips)[v.m_Name]
                    res = v.m_ExternalResources
                    resource = self.data(res.m_Source)
                    movie = resource[res.m_Offset:res.m_Offset+res.m_Size]
                    self.assertEqual(movie[4:8],b'ftyp')
                    expected = f'{{"@stock/c{chapter}/{name}","{res.m_Source}","{hashlib.sha256(movie).hexdigest()}",{len(movie)},{res.m_Offset},{len(resource)}}}'
                    self.assertIn(expected,re.sub(r'\s+','',self.movies))


if __name__=='__main__':
    unittest.main()
