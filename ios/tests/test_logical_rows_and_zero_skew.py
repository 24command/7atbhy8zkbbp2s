from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class LogicalRowsAndZeroSkew(unittest.TestCase):
 def test_extra_name_is_not_official_at_slot(self):
  row=(ROOT/'PhiMod/Sources/PMSelectorRowPresentation.inc').read_text('utf8')
  self.assertIn('PMStockDifficulty(chosen[@"level"])<0',row)
  self.assertIn('PMMatchingExtraDifficulty(entries->second,extra)',row)
  self.assertIn('if(!present){maskRow(r,binding);continue;}',row)
  self.assertIn('binding.ratings',row)
  self.assertIn('listRowRecords',row)
  self.assertIn('"GetSongRecord"',row)
  self.assertNotIn('"SetSongRecord"',row)
  self.assertIn('if(logicalChanged)r.call(item,"SetText"',row)
 def test_mask_restoration_precedes_native_list_update(self):
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text('utf8').split('void onSelector(',1)[1].split('void onSelectorOff(',1)[0]
  self.assertLess(hook.index('restoreSelectorRowVisibility'),hook.index('orig<VoidFn>'))
  source=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text('utf8')
  self.assertIn('clearSelectorRowPresentation(r)',source.split('void selectorLoadingEnd(',1)[1])
 def test_zero_skew_keeps_nonzero_and_cleanup_paths(self):
  source=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text('utf8')
  self.assertIn('if(point.value!=0){zero=false;break;}',source)
  self.assertIn('zeroSkewTracks.clear()',source)
  geom=source.split('void finishNoteGeometry(',1)[1].split('void ranking(',1)[0]
  self.assertLess(geom.index('if(isZeroSkewTrack(d))'),geom.index('"nowTime"'))
  self.assertIn('if(skewMeshes.count(renderer))applySkew(r,renderer,0)',geom)
  self.assertIn('applySkew(r,renderer,rpeSkew',geom)
 def test_renderer_iteration_does_not_allocate_per_note(self):
  source=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text('utf8')
  moved=source.split('void noteMoved(',1)[1].split('bool isZeroSkewTrack(',1)[0]
  self.assertNotIn('std::vector<const char*>',moved)
  self.assertIn('fields=hold?holdFields:tapFields',moved)
  self.assertIn('fieldCount=hold?3:1',moved)
  self.assertEqual(moved.count('fieldIndex<fieldCount'),2)
if __name__=='__main__':unittest.main()
