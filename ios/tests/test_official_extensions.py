"""Guard official-song absence through both extension consumers (source check)."""
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class OfficialExtensions(unittest.TestCase):
 def test_no_null_string_conversion_and_consumers_skip_absent_folder(self):
  source=(ROOT/'PhiMod/Sources/PMRuntimeFeatures.mm').read_text(encoding='utf-8')
  folder=source.split('NSString*resourceFolder(',1)[1].split('std::string hexDecodePath',1)[0]
  self.assertIn('if(!folder.length)return nil;',folder)
  self.assertIn('if(!song)return nil;',folder)
  self.assertNotIn('UTF8String',folder.split('if(!identifier.length)',1)[1])
  self.assertNotIn('resourceFolder(identifier).c_str()',source)
  video=source.split('void prepareVideos(Runtime',1)[1].split('double trackAt',1)[0]
  self.assertLess(video.index('if(!folder.length)return;'),video.index('prepareVideosFromEffects'))
  self.assertIn('PMMetalShadersLoad(folder);',source)
  metal=(ROOT/'PhiMod/Sources/PMMetalShaders.mm').read_text(encoding='utf-8')
  self.assertIn('if(!folder.length)return;',metal)
if __name__=='__main__':unittest.main()
