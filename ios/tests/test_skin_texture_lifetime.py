from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]/'PhiMod/Sources'
class SkinLifetime(unittest.TestCase):
 def test_skin_after_loading_and_native_retention(self):
  s=(R/'PMRuntimeFeatures.mm').read_text(encoding='utf-8')
  awake=s.split('void levelBegin(',1)[1].split('void levelEnd(',1)[0]
  self.assertNotIn('loadSkin(r)',awake)
  self.assertIn('void afterChart(Runtime&r,void*level){try{loadSkin(r);}',s)
  self.assertEqual(s.count('int flags=32;'),2)
  self.assertIn('if(!r.alive(texture))',s)
 def test_available_material_entry(self):
  s=(R/'PMContentRuntime.mm').read_text(encoding='utf-8')
  self.assertNotIn('"set_sharedMaterial"',s)
  self.assertEqual(s.count('r.resolve(r.type("UnityEngine","Renderer"),"SetMaterial",{"UnityEngine.Material"})'),2)
if __name__=='__main__':unittest.main()
