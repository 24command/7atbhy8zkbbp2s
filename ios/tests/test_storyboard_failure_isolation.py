from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class StoryboardRegression(unittest.TestCase):
 def test_enum_keeps_strict_type_identity(self):
  bridge=(ROOT/'PhiMod/Sources/PMIL2CPP.hpp').read_text(encoding='utf-8')
  enum=bridge[bridge.index('int enumValue('):bridge.index('NSString*string(')]
  self.assertIn('typeIs(class_get_type(c),expectedType)',enum)
  self.assertIn('class_value_size(c,&alignment)!=sizeof(int)',enum)
  self.assertIn('expected="System.Int32"',bridge)
  content=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  self.assertIn('r.enumValue(r.call(renderer,"get_drawMode"),"UnityEngine.SpriteDrawMode")',content)
  self.assertNotIn('r.unbox<int>(r.call(renderer,"get_drawMode"))',content)
 def test_line_failure_does_not_exit_frame(self):
  content=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  loop=content[content.index('void visuals('):content.index('// Fake notes are independent')]
  self.assertIn('for(int i=0;i<total;++i){\n  try{',loop)
  self.assertIn('Storyboard line update failed:',loop)
  backend=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  self.assertIn('try{pmcontent::recoverSourceNotes(R(),self);}catch',backend)
  self.assertNotIn('pmcontent::recoverSourceNotes(r,self);pmcontent::visuals',backend)
if __name__=='__main__':unittest.main()
