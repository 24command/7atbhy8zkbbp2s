from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class BackendFailure(unittest.TestCase):
 def test_current_ipa_requires_72_slots(self):
  entry_bytes=16;gate_bytes=48
  self.assertEqual((4384-32)//(entry_bytes+gate_bytes),68)
  self.assertEqual(32+72*(entry_bytes+gate_bytes),4640)
 def test_failed_install_reports_actual_error(self):
  s=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf8')
  command=s.split('+ (NSDictionary*)contentCommand:',1)[1].split('+ (',1)[0]
  self.assertIn('lastError.c_str()',command)
  self.assertIn('if(!ready||broken||!rt)',command)
  self.assertIn('return pmcontent::command',command)
  self.assertIn('IPA has ',s)
  self.assertIn('std::to_string(installed)',s)
  runtime=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf8')
  self.assertIn('PhiMod backend is not initialized',runtime)
if __name__=='__main__':unittest.main()
