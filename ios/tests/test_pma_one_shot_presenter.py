"""PMA one-shot contracts + compiled actual timing core. Not device/UI playback."""
from pathlib import Path
import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/'PhiMod/Sources'
MEDIA=(SRC/'PMUnlockMedia.mm').read_text(encoding='utf-8')
SECTIONS={'gif_tick': (' if(self.gif){', ' }else if(self.player){'), 'video_tick': (' }else if(self.player){', '\n- (void)finish:(BOOL)completed{'), 'gif_open': ('if([path.pathExtension.lowercaseString isEqualToString:@"gif"]){', ' }else if([path.pathExtension.lowercaseString isEqualToString:@"mp4"]'), 'video_open': (' }else if([path.pathExtension.lowercaseString isEqualToString:@"mp4"]', '\n}\n\n\n// BEGIN PM_HELD_TRANSITION_CORE'), 'held_transition': ('// BEGIN PM_HELD_TRANSITION_CORE', '\x00')}
HASHES={'gif_tick': 'f8848919472ce9b07f28153f22dc5f37f962697976401e606fa99718a4fa37d0', 'video_tick': '3e644e03e93fbf27b6f16a9680dc0d55a7674c14132133e98b149895d4f4f62f', 'gif_open': '61980d139a5b1552abbf94abb8a6e260d06bc8c2f48841c41e443c0eaf5d6209', 'video_open': 'acbec78dcbd15df9a56b3a0e7e8b39c2de92be5df73eb932d2f650dd5a43508f', 'held_transition': 'bece331c729f0b3d281ff8ba1a62e3d68b51dd89d05d62ab97c8c40821ecdd3e'}
def between(s,a,b):return s.split(a,1)[1].split(b,1)[0]
class PMAOneShot(unittest.TestCase):
    def test_actual_portable_playback(self):
        compiler=os.environ.get('CXX') or shutil.which('clang++') or shutil.which('g++') or shutil.which('cl')
        if not compiler:self.skipTest('C++ compiler unavailable; macOS runner requires this test')
        with tempfile.TemporaryDirectory(prefix='pma-oneshot-') as tmp:
            binary=Path(tmp)/('playback.exe' if os.name=='nt' else 'playback')
            source=ROOT/'tests/PMNativeOSFrameSequencePlaybackTest.cpp'
            if Path(compiler).name.lower() in ('cl','cl.exe'):
                args=[compiler,'/nologo','/EHsc','/std:c++17','/W4','/WX',f'/Fe:{binary}',f'/Fo:{Path(tmp)/"playback.obj"}',str(source)]
            else:args=[compiler,'-std=c++17','-Wall','-Wextra','-Werror',str(source),'-o',str(binary)]
            result=subprocess.run(args,cwd=tmp,capture_output=True,text=True,errors='replace',timeout=60)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            result=subprocess.run([str(binary)],capture_output=True,text=True,timeout=15)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn('6 behavioral groups passed',result.stdout)
    def test_legacy_gif_video_and_held_transition_unchanged(self):
        for name,(start,end) in SECTIONS.items():
            with self.subTest(region=name):
                self.assertEqual(hashlib.sha256(between(MEDIA,start,end).encode()).hexdigest(),HASHES[name])
    def test_queue_and_stale_completions(self):
        block=between(MEDIA,'- (void)requestSequenceFrame:(NSUInteger)frame {','- (void)stepSequence:')
        self.assertLess(block.index('dispatch_async(PMUnlockSequenceQueue()'),block.index('PMOSFrameSequenceOpen'))
        self.assertLess(block.index('dispatch_get_main_queue()'),block.index('owner.image.image=image'))
        self.assertIn('__weak PMUnlockMediaView *weak=self',block)
        self.assertIn('activeMedia!=owner || !owner->_sequenceState.owns(token,frame)',block)
        self.assertIn('PMOSFrameSequenceCopyFrame(source,frame,2048,nullptr)',block)
        self.assertNotIn('animatedImage',block)
        self.assertNotIn('for(',block)
    def test_completion_skip_and_cleanup(self):
        skip=between(MEDIA,'- (void)skip{','- (void)step:')
        self.assertIn('if(self.fallback){[self finish:NO];return;}',skip)
        self.assertIn('if(!_sequenceState.canSkip())return;',skip)
        self.assertIn('[self finish:!(self.strict && self.fallback)]',skip)
        finish=between(MEDIA,'- (void)finish:(BOOL)completed{','\n@end')
        self.assertLess(finish.index('_sequenceState.cancel()'),finish.index('activeMedia=nil'))
        self.assertLess(finish.index('self.completion=nil'),finish.index('if(done)done(completed)'))
        self.assertIn('if(activeMedia!=self)return;',finish)
        self.assertIn('activeMedia=nil;if(done)done(completed)',finish)
        self.assertIn('self.sequenceSource=nil;self.sequencePath=nil;self.image.image=nil',finish)
        self.assertIn('if(action==pmpma::Playback::Action::Complete){[self finish:YES];return;}',MEDIA)
    def test_metadata_not_sent_to_avfoundation(self):
        inc=(SRC/'PMNativeOSUnlockPlayback.inc').read_text(encoding='utf-8')
        sequence=between(inc,'if([path.pathExtension.lowercaseString isEqualToString:@"pma"]){','}else{')
        self.assertIn('PMUnlockFrameSequenceMetadata(path,&seconds)',sequence)
        self.assertNotIn('AVURLAsset',sequence)
        self.assertIn('[program markUnlockSeen:index',inc)
        actions=(SRC/'PMNativeOSActions.mm').read_text(encoding='utf-8')
        entry=between(actions,'- (BOOL)playEntryMovie:','- (BOOL)playIntro:')
        self.assertIn('if (!played)',entry)
        self.assertIn('markEntryMovieSeen:',entry)
    def test_shared_owner_and_overlay(self):
        self.assertEqual(MEDIA.count('static UIView<PMMediaPresentation> *activeMedia;'),1)
        self.assertIn('void PMCancelUnlockMedia(void){[activeMedia finish:NO];}',MEDIA)
        configure=between(MEDIA,'void PMConfigureUnlockTimeline(','void PMCancelUnlockMedia')
        self.assertIn('(!view.player && !view.frameSequence)',configure)
        self.assertIn('setSequenceLimit:duration',configure)
        self.assertIn('self.sample(_sequenceState.elapsed(now))',MEDIA)
        self.assertIn('if(activeMedia!=self)return; // sample may cancel',MEDIA)
    def test_macos_ci_runner_is_available(self):
        runner=(ROOT/'tests/run_pma_presenter_tests.sh').read_text(encoding='utf-8')
        for name in ('test_native_os_frame_sequence.py','test_pma_one_shot_presenter.py','PMUnlockMedia.mm','PMNativeOSActions.mm','PMNativeOSFrameSequence.mm'):
            self.assertIn(name,runner)
        self.assertIn('--sdk iphoneos',runner)
        self.assertIn('-fsyntax-only',runner)
        workflow=(ROOT.parent/'.github/workflows/test-pma-presenter.yml').read_text(encoding='utf-8')
        self.assertIn('runs-on: macos-15-intel',workflow)
        self.assertIn('bash ios/tests/run_pma_presenter_tests.sh',workflow)
if __name__=='__main__':unittest.main()
