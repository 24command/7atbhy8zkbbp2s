from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]/'PhiMod/Sources'
class EditorEntry(unittest.TestCase):
 def test_editor_wired_and_validates(self):
  ui=(R/'PMContentUI.mm').read_text(encoding='utf-8')
  e=(R/'PMUnlockEditor.mm').read_text(encoding='utf-8')
  self.assertIn('PMShowUnlockEditor(self,id)',ui)
  for kind in ('score','acc','fc','phi','rks','chapter'):self.assertIn('@"'+kind+'"',e)
  self.assertIn('PMUnlockValidationError(self.rule)',e)
  self.assertIn('snapshot',e)
  self.assertIn('commit:db',e)
 def test_native_pages_hidden_and_previous_tab_kept(self):
  s=(R/'PMSceneUI.mm').read_text(encoding='utf-8')
  press=s[s.index('bool press('):]
  self.assertNotIn('int tab=2;',press)
  self.assertIn('"tabScrollContents"',press)
  self.assertIn('"itemsHolder"',press)
  self.assertIn('restore(r,hidden,"SetActive")',s)
if __name__=='__main__':unittest.main()
