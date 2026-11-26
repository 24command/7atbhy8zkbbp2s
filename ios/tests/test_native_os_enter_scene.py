from pathlib import Path
import tempfile,unittest
from test_native_os_transition_support import compile_cpp,run_cpp
ROOT=Path(__file__).resolve().parents[1]
class EntryScene(unittest.TestCase):
 def test_real_clock(self):
  code=(ROOT/'tests/PMNativeOSEnterSceneTest.cpp').read_text().replace('../PhiMod/Sources/PMNativeOSEnterScene.hpp',(ROOT/'PhiMod/Sources/PMNativeOSEnterScene.hpp').as_posix())
  with tempfile.TemporaryDirectory(prefix='scene-clock-') as out:run_cpp(self,compile_cpp(code,out,'scene'))
 def test_native_map_and_stale_completion(self):
  s=(ROOT/'PhiMod/Sources/PMNativeOSCoordinator.mm').read_text('utf8')
  self.assertIn('map::displayPage(*game,mapID,spec.toScreen)',s)
  self.assertIn('generation!=epoch || mapID!=owner || mode!=Mode::map',s)
  self.assertIn('chrome::Face::Map,!entry',s)
  self.assertIn('mapID,true,!enterSceneClock.committing,!entry',s)
  self.assertIn('enterSceneClock.reset();mapRevealed=nil',s)
  self.assertIn('program.entrySceneSeen',s)
 def test_progress_only_on_completion_and_first_clear_event(self):
  s=(ROOT/'PhiMod/Sources/PMNativeOSProgram.mm').read_text('utf8')
  block=s.split('- (void)markEntrySceneSeen:',1)[1].split('- (void)markEntryMovieSeen:',1)[0]
  self.assertIn('self->_progress commitValues:@{key:@1}',block)
  self.assertIn('if(ok)self->_entrySceneFinished=YES',block)
  door=(ROOT/'PhiMod/Sources/PMDoorRun.mm').read_text('utf8')
  self.assertIn('if(clear && value<=0)updates',door)
  self.assertIn('door.%@.new',door)
 def test_exact_terminal_chart_binding(self):
  p=(ROOT/'PhiMod/Sources/PMNativeOSCoordinator.mm').read_text('utf8')
  self.assertIn('PMArmSongInterruption(program.visibleBySong[exact.chartID][@"interruption"],exact.chartID,exact.slot)',p)
  self.assertIn('PMCancelSongInterruptionLaunch();armed=false;',p)
if __name__=='__main__':unittest.main()
