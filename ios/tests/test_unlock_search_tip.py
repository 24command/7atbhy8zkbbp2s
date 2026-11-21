from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]/'PhiMod/Sources'
class UnlockSearchTip(unittest.TestCase):
 def test_search_and_selected_identity(self):
  s=(R/'PMUnlockEditor.mm').read_text(encoding='utf-8')
  self.assertIn('UISearchResultsUpdating',s)
  self.assertIn('NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch',s)
  self.assertIn('@[@"title",@"id"]',s)
  self.assertIn('NSDictionary*entry=self.filtered[index.row]',s)
  self.assertIn('c[@"ref"]=entry[@"id"]',s)
 def test_native_tip_and_rule_display(self):
  s=(R/'PMUnlockRuntime.mm').read_text(encoding='utf-8')
  self.assertIn('r.get<P>(card,"unlockTip")',s)
  self.assertIn('open?@"":chapterRequirements(r,ruleFor(id))',s)
  for kind in ('score','acc','fc','phi','rks','chapter'):self.assertIn('@"'+kind+'"',s)
  self.assertIn('r.managedString(requirements)',s)
if __name__=='__main__':unittest.main()
