import importlib.util
import pathlib
import plistlib
import tempfile
import unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('package',ROOT/'tools/package_unsigned_ipa.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class HighRefreshTests(unittest.TestCase):
 def test_only_opt_in_changes_and_format_survives(self):
  for fmt in (plistlib.FMT_BINARY,plistlib.FMT_XML):
   with tempfile.TemporaryDirectory() as temp:
    app=pathlib.Path(temp);path=app/'Info.plist'
    original={'CFBundleIdentifier':'test.game','CADisableMinimumFrameDurationOnPhone':False,'CADisableMinimumFrameDuration':False,'Other':[1,'unchanged']}
    path.write_bytes(plistlib.dumps(original,fmt=fmt));module.enable_high_refresh(app)
    result=plistlib.loads(path.read_bytes());self.assertIs(result.pop('CADisableMinimumFrameDurationOnPhone'),True)
    original.pop('CADisableMinimumFrameDurationOnPhone');self.assertEqual(result,original)
    once=path.read_bytes();module.enable_high_refresh(app);self.assertEqual(path.read_bytes(),once)
    self.assertEqual(once.startswith(b'bplist'),fmt==plistlib.FMT_BINARY)
 def test_sampler_is_per_track_and_no_visibility_or_timing_changes(self):
  source=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text('utf8')
  self.assertIn('using VisualTrack=phimod::CachedRPETrack;',source)
  self.assertIn('std::make_pair(a,channel)',source)
  self.assertIn('visualTracks.clear()',source)
  self.assertIn('return it->second.value(now,fallback);',source)
if __name__=='__main__':unittest.main()
