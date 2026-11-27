from pathlib import Path
import platform,subprocess,tempfile,unittest
R=Path(__file__).resolve().parents[1];S=R/'PhiMod/Sources'
class LoadFailure(unittest.TestCase):
 def test_host_isolates_preparation_failure(self):
  p=(S/'PMNativeOSProgram.mm').read_text('utf8');block=p.split('for (int i=0; i<plan->songInterruptionCount;',1)[1].split('NSMutableArray *cards',1)[0]
  self.assertIn('PMOSBindInterruption',block);self.assertNotIn('return fail(',block)
  c=(S/'PMNativeOSCoordinator.mm').read_text('utf8');block=c.split('bool playSelection(Runtime &r,NSDictionary *card,NSDictionary *choice){',1)[1].split('bool wantsOSHome',1)[0]
  self.assertLess(block.index('interruptionError.length'),block.index('scene::play('))
  self.assertIn('PMOSShowLoadError(interruptionError);return false;',block)
 def test_failed_program_keeps_retry_switch(self):
  c=(S/'PMNativeOSCoordinator.mm').read_text('utf8');block=c.split('  if(!p){',1)[1].split('  program=p;',1)[0]
  self.assertIn('program=nil;requestedEntry=0',block)
  self.assertIn('toggle::bind(*game,owner,key.UTF8String)',block)
  self.assertIn('toggle::Face::List,true',block)
  self.assertIn('PMOSShowLoadError',block)
  self.assertIn('if(retryOS || (!returning && wantsOSHome(p,key)))requestedEntry=epoch;',c)
  self.assertIn('if(!program){P owner=selector;NSString *key=[chapter copy];ready(r,owner,key);return;}',c)
 @unittest.skipUnless(platform.system()=='Darwin','Foundation runtime needs macOS')
 def test_actual_optional_binding(self):
  with tempfile.TemporaryDirectory(prefix='os-load-') as t:
   exe=str(Path(t)/'test');subprocess.run(['xcrun','clang++','-std=c++17','-fobjc-arc','-Wall','-Wextra','-Werror','-framework','Foundation',str(R/'tests/PMNativeOSInterruptionPlanTest.mm'),'-o',exe],check=True);subprocess.run([exe],check=True)
if __name__=='__main__':unittest.main()