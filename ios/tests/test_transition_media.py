"""Portable decision tests + source contracts; NOT an Apple SDK/device playback test.

Run: CXX=/path/to/c++ python ios/tests/test_transition_media.py
Device plan: MP4/MOV natural/cutoff and zero/mid/end/beyond-end holds; confirm the
last decoded frame stays visible and touches stay blocked until resume. Repeat
with nil-path textures, missing/truncated/audio-only files, never-resuming loads,
background during decode/play/load, async/double/stale resumes, and cancellation
from sample/load/completion. Verify no Skip/text, no scene routing, observer/input
cleanup, mutual exclusion with legacy unlock, and legacy GIF/MP4/Skip behavior.
"""
from pathlib import Path
import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest

IOS = Path(__file__).resolve().parents[1]
SOURCE = (IOS / 'PhiMod/Sources/PMUnlockMedia.mm').read_text(encoding='utf-8')
HEADER = (IOS / 'PhiMod/Sources/PMUnlockMedia.h').read_text(encoding='utf-8')
TRANSITION = SOURCE.split('// BEGIN PM_HELD_TRANSITION_CORE', 1)[1]
VIEW = TRANSITION.split('@implementation PMTransitionMediaView', 1)[1]


class HeldTransitionTests(unittest.TestCase):
    def test_actual_private_timeline(self):
        compiler = os.getenv('CXX') or shutil.which('clang++') or shutil.which('g++')
        if not compiler:
            self.skipTest('set CXX to a C++ compiler to execute the actual timeline core')
        core = TRANSITION.split('// END PM_HELD_TRANSITION_CORE', 1)[0]
        with tempfile.TemporaryDirectory(prefix='pm-held-transition-') as folder:
            folder = Path(folder)
            (folder / 'PMTransitionTimelineUnderTest.hpp').write_text(core, encoding='utf-8')
            binary = folder / ('timeline.exe' if os.name == 'nt' else 'timeline')
            built = subprocess.run([compiler, '-std=c++11', '-Wall', '-Wextra', '-Werror',
                                    '-I', str(folder), str(IOS / 'tests/PMTransitionTimelineTest.cpp'),
                                    '-o', str(binary)], capture_output=True, text=True, timeout=60)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            env = dict(os.environ)
            env['PATH'] = str(Path(compiler).parent) + os.pathsep + env.get('PATH', '')
            run = subprocess.run([str(binary)], capture_output=True, text=True, env=env, timeout=15)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn('checks passed', run.stdout)
            print(run.stdout.strip())

    def test_legacy_unlock_logic_is_unchanged(self):
        legacy = SOURCE.split('// BEGIN PM_HELD_TRANSITION_CORE', 1)[0]
        # PMA adds a sibling backend to the shared owner. Exclude only its new
        # implementation/declarations and project the explicitly guarded shared
        # statements back to their non-PMA form. Keep the ORIGINAL baseline hash:
        # GIF/video setup, ticking, fallback/Skip, cleanup, overlay and ownership
        # must remain byte-for-byte unchanged, not merely contain a few tokens.
        def replace_once(old, new):
            nonlocal legacy
            self.assertEqual(legacy.count(old), 1, 'missing/ambiguous PMA integration: ' + old)
            legacy = legacy.replace(old, new, 1)

        replace_once('#include "PMNativeOSFrameSequence.hpp"\n', '')
        replace_once('#include "PMNativeOSFrameSequencePlayback.hpp"\n', '')
        # Explicit delimiters exclude new PMA helpers only, never a legacy method.
        for start, end in (
            ('static dispatch_queue_t PMUnlockSequenceQueue(void) {',
             '@interface PMUnlockMediaView : UIView <PMMediaPresentation>'),
            ('- (BOOL)setSequenceLimit:(double)seconds {', '- (void)layoutSubviews{'),
        ):
            self.assertEqual(legacy.count(start), 1)
            self.assertEqual(legacy.count(end), 1)
            first, last = legacy.index(start), legacy.index(end)
            self.assertLess(first, last)
            legacy = legacy[:first] + legacy[last:]
        replace_once(
            '@interface PMUnlockMediaView : UIView <PMMediaPresentation> {\n'
            ' pmpma::Playback _sequenceState;\n}\n'
            '@property(nonatomic) BOOL frameSequence;\n'
            '@property(nonatomic,strong) NSObject *sequenceSource;\n'
            '@property(nonatomic,copy) NSString *sequencePath;\n'
            '- (void)startSequence:(NSString *)path;\n'
            '- (void)requestSequenceFrame:(NSUInteger)frame;\n'
            '- (void)stepSequence:(double)now;\n'
            '- (BOOL)setSequenceLimit:(double)seconds;\n'
            '- (void)showFallback;\n',
            '@interface PMUnlockMediaView : UIView <PMMediaPresentation>\n')
        replace_once(' if(self.frameSequence){_sequenceState.cancel();self.sequenceSource=nil;'
                     '[(UIButton *)[self viewWithTag:101] setEnabled:YES];}\n', '')
        replace_once('self.frameSequence ? @"Animation unavailable — tap Skip to continue" : '
                     '@"Unlocked — tap Skip to continue"', '@"Unlocked — tap Skip to continue"')
        replace_once('- (void)skip{\n'
                     ' if(self.frameSequence){if(self.fallback){[self finish:NO];return;}'
                     'if(!_sequenceState.canSkip())return;}\n'
                     ' [self finish:!(self.strict && self.fallback)];\n}',
                     '- (void)skip{[self finish:!(self.strict && self.fallback)];}')
        replace_once('[self finish:!self.strict && !self.frameSequence]', '[self finish:!self.strict]')
        replace_once(' if(self.frameSequence){[self stepSequence:CACurrentMediaTime()];return;}\n', '')
        replace_once(' if(self.frameSequence){_sequenceState.cancel();self.sequenceSource=nil;'
                     'self.sequencePath=nil;self.image.image=nil;}\n', '')
        replace_once('(!view.player && !view.frameSequence)', '!view.player')
        replace_once(' if(view.frameSequence && ![view setSequenceLimit:duration])'
                     '{[view showFallback];return;}\n', '')
        replace_once(' if([path.pathExtension.lowercaseString isEqualToString:@"pma"]){\n'
                     '  [v startSequence:path];\n'
                     ' }else if([path.pathExtension.lowercaseString isEqualToString:@"gif"]){',
                     ' if([path.pathExtension.lowercaseString isEqualToString:@"gif"]){')
        legacy = legacy.replace('@protocol PMMediaPresentation <NSObject>\n- (void)finish:(BOOL)completed;\n@end\n\n', '', 1)
        legacy = legacy.replace('@interface PMUnlockMediaView : UIView <PMMediaPresentation>', '@interface PMUnlockMediaView : UIView', 1)
        legacy = legacy.replace('static UIView<PMMediaPresentation> *activeMedia;', 'static PMUnlockMediaView *activeMedia;', 1)
        legacy = legacy.replace(' if(![activeMedia isKindOfClass:PMUnlockMediaView.class])return;\n PMUnlockMediaView *view=(PMUnlockMediaView*)activeMedia;', ' PMUnlockMediaView *view=activeMedia;', 1)
        self.assertEqual(hashlib.sha256((legacy.rstrip()+'\n').encode()).hexdigest(), 'fe5caa97994f93888b75609d68e1e10e9845d7e21c6ff4b9da013b4e0c2a9abe')

    def test_held_transition_implementation_is_unchanged(self):
        # Baseline predates PMA; the separate held-transition presenter must not
        # inherit PMA decoding, Skip UI, or one-shot completion behavior.
        self.assertEqual(hashlib.sha256(TRANSITION.encode()).hexdigest(),
                         'bece331c729f0b3d281ff8ba1a62e3d68b51dd89d05d62ab97c8c40821ecdd3e')

    def test_public_api_and_shared_owner(self):
        self.assertIn('BOOL PMPresentTransitionMedia(NSString * _Nullable path, UIView * _Nullable overlay,', HEADER)
        self.assertIn('void (^ _Nullable load)(void (^resume)(BOOL))', HEADER)
        self.assertEqual(SOURCE.count('static UIView<PMMediaPresentation> *activeMedia;'), 1)
        self.assertIn('void PMCancelUnlockMedia(void){[activeMedia finish:NO];}', SOURCE)
        self.assertIn('if(!NSThread.isMainThread||activeMedia||!PMHeldTransition::Timeline::valid', VIEW)
        self.assertIn('activeMedia=view;[window addSubview:view];[view start];return YES;', VIEW)
        self.assertIn('if(![activeMedia isKindOfClass:PMUnlockMediaView.class])return;', SOURCE)

    def test_video_hard_stop_and_retained_frame(self):
        self.assertIn('AVPlayerActionAtItemEndPause', VIEW)
        self.assertIn('- (void)configurePlayback {\n if(!self.player)return;', VIEW)
        self.assertIn('forwardPlaybackEndTime=_playbackEnd>0?', VIEW)
        self.assertIn('self.video.readyForDisplay', VIEW)
        pump = VIEW.split('- (void)pump:(double)delta {', 1)[1].split('- (void)finish:', 1)[0]
        self.assertIn('if(_timeline.phase==Phase::Holding)[self.player pause];', pump)
        self.assertNotIn('removeFromSuperlayer', pump)
        self.assertNotIn('replaceCurrentItemWithPlayerItem', pump)
        self.assertLess(pump.index('sample(_timeline.time)'), pump.index('[self requestLoad]'))
        self.assertIn('if(view&&view->_playbackEpoch==epoch)[view reachedEnd];', VIEW)

    def test_fallback_is_opaque_and_has_no_unlock_ui_or_scene_calls(self):
        blackout = VIEW.split('- (void)blackout {', 1)[1].split('- (void)requestLoad', 1)[0]
        self.assertIn('self.video.hidden=YES;self.overlay.hidden=YES;', blackout)
        self.assertIn('self.backgroundColor=UIColor.blackColor;self.opaque=YES;', blackout)
        for forbidden in ('UIButton', 'UILabel', '@"Skip', '@"Unlocked', 'showFallback',
                          'LoadScene', 'TurnToNextScene', 'Unity', 'beginIgnoringInteractionEvents'):
            self.assertNotIn(forbidden, VIEW)
        loader = VIEW.split('- (void)requestLoad {', 1)[1].split('- (void)acceptResume:', 1)[0]
        self.assertLess(loader.index('[CATransaction flush]'), loader.index('if(loader)loader(resume)'))

    def test_load_waits_for_a_held_frame_render_turn(self):
        loader = VIEW.split('- (void)requestLoad {', 1)[1].split('- (void)acceptResume:', 1)[0]
        self.assertIn('_loadAfterTick=_displayTick+2;', loader)
        self.assertIn('[self layoutIfNeeded];[CATransaction flush];return;', loader)
        self.assertLess(loader.index('if(_displayTick<_loadAfterTick||_loadScheduled)return;'),
                        loader.index('dispatch_async(dispatch_get_main_queue()'))
        self.assertIn('if(!view->_loadFrameArmed||view->_displayTick<view->_loadAfterTick)return;', loader)
        self.assertIn('- (void)step:(CADisplayLink*)clock {\n ++_displayTick;', VIEW)
        suspend = VIEW.split('- (void)suspend {', 1)[1].split('- (void)activate {', 1)[0]
        self.assertIn('_loadFrameArmed=NO;', suspend)
        self.assertIn('self.backgroundColor=path?UIColor.blackColor:UIColor.clearColor;self.opaque=path!=nil;', VIEW)

    def test_pause_and_resume_do_not_route_or_complete_in_background(self):
        suspend = VIEW.split('- (void)suspend {', 1)[1].split('- (void)activate {', 1)[0]
        self.assertIn('_timeline.suspended=true;_lastTick=0;self.clock.paused=YES;[self.player pause];', suspend)
        self.assertNotIn('finish:', suspend)
        for name in ('UIApplicationWillResignActiveNotification', 'UIApplicationDidEnterBackgroundNotification',
                     'UIApplicationDidBecomeActiveNotification', 'UISceneWillDeactivateNotification',
                     'UISceneDidActivateNotification'):
            self.assertIn(name, VIEW)
        resume = VIEW.split('- (void)acceptResume:(BOOL)ok {', 1)[1].split('- (void)pump:', 1)[0]
        self.assertLess(resume.index('[self suspend]'), resume.index('_timeline.resume(ok)'))
        self.assertLess(resume.index('[self pump:delta]'), resume.index('_timeline.resume(ok)'))
        self.assertIn('if(!_timeline.suspended)', resume)
        self.assertIn('_lastTick=CACurrentMediaTime();[self configurePlayback];[self.player play];', resume)

    def test_reentrancy_and_release_before_completion(self):
        finish = VIEW.split('- (void)finish:(BOOL)completed {', 1)[1].split('@end', 1)[0]
        self.assertLess(finish.index('_finished=YES'), finish.index('[self removeFromSuperview]'))
        for cleanup in ('[self.clock invalidate]', 'removeObserver:token', 'removeObserver:self.endObserver',
                        'self.sample=nil;self.load=nil;', 'self.completion=nil;', '[self removeFromSuperview]', 'activeMedia=nil'):
            self.assertLess(finish.index(cleanup), finish.index('if(done)done(completed)'))
        self.assertIn('self.overlay.userInteractionEnabled=_overlayWasInteractive;', finish)
        self.assertIn('dispatch_async(dispatch_get_main_queue(),^{[weak acceptResume:ok];});', VIEW)
        self.assertIn('if(view->_timeline.suspended||![view foreground]){[view suspend];return;}', VIEW)
        self.assertIn('- (void)start {\n if(![self owned])return;', VIEW)
        self.assertIn('if(![self owned]||!_loadInvoked)return;', VIEW)
        self.assertIn('if(sample)sample(_timeline.time);\n  if(![self owned])return;', VIEW)


if __name__ == '__main__':
    unittest.main(verbosity=2)
