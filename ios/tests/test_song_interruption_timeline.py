"""Compile and run the production portable owner. No UIKit/string-only substitute."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SongInterruptionTimeline(unittest.TestCase):
    def test_ui_and_media_wiring(self):
        text = (ROOT / 'PhiMod/Sources/PMSongInterruption.mm').read_text(encoding='utf8')
        self.assertTrue('presentViewController:alert animated:YES' in text, 'presentViewController:alert animated:YES')
        self.assertTrue('presentViewController:alert animated:NO' not in text, 'presentViewController:alert animated:NO')
        self.assertTrue('PMCompleteCover(payload->prepared.image, aspect, &error)' in text, 'PMCompleteCover(payload->prepared.image, aspect, &error)')
        self.assertTrue('state.advanceStage(ticket, now, true)' in text, 'state.advanceStage(ticket, now, true)')
        self.assertTrue('state.suspend(ticket,continuousSeconds())' in text, 'state.suspend(ticket,continuousSeconds())')
        self.assertTrue('resumeAudio = self.audio.playing' in text, 'resumeAudio = self.audio.playing')
        self.assertTrue('return !play || [self.audio play]' in text, 'return !play || [self.audio play]')
        self.assertTrue('media.audio.numberOfLoops=0' in text, 'media.audio.numberOfLoops=0')
        self.assertTrue('AVAudioSession' not in text, 'AVAudioSession')
        self.assertTrue('payload->prepared.audioData[phase]' in text, 'payload->prepared.audioData[phase]')
        for key in ('effectAudioSrc', 'blackAudioSrc', 'blueAudioSrc'):
            self.assertTrue(key in text, key)
        self.assertTrue('config[@"audioPhase"]' not in text, 'config[@"audioPhase"]')
        self.assertTrue('config[@"audioSrc"]' not in text, 'config[@"audioSrc"]')
        self.assertTrue('playing->effect = [configuredEffect copy]' in text, 'playing->effect = [configuredEffect copy]')
        self.assertTrue('state.claimAudio(ticket,continuousSeconds(),delay)' in text, 'state.claimAudio(ticket,continuousSeconds(),delay)')
        self.assertTrue('if (sceneNote && note.object != owner.gameScene) return;' in text, 'if (sceneNote && note.object != owner.gameScene) return;')
        prepare = text[text.index('PMPreparedSongInterruption *PMPrepareSongInterruption('):text.index('struct PMInterruptionPayload')]
        arm = text[text.index('BOOL PMArmSongInterruption('):text.index('BOOL PMSongInterruptionPending(')]
        self.assertTrue('prepareToPlay' not in prepare, 'prepareToPlay')
        self.assertTrue('prepareToPlay' not in arm, 'prepareToPlay')
        self.assertTrue('std::isfinite(probe.duration)' in prepare, 'std::isfinite(probe.duration)')
        self.assertTrue('probe.numberOfChannels == 0' in prepare, 'probe.numberOfChannels == 0')
        self.assertTrue('off_t remainingAudioBytes = 32 * 1024 * 1024' in prepare, 'off_t remainingAudioBytes = 32 * 1024 * 1024')
        self.assertTrue('error, remainingAudioBytes)' in prepare, 'error, remainingAudioBytes)')
        self.assertTrue('if (hasAudio && !staged)' in prepare, 'if (hasAudio && !staged)')
        self.assertTrue('[self muteFailedAudio:phase]' in text, '[self muteFailedAudio:phase]')
        self.assertTrue('if(!state.payload()->prepared.audioTail)[self stopAudio]' in text, 'if(!state.payload()->prepared.audioTail)[self stopAudio]')
        self.assertTrue('self.audioSessions[phase]=media' in text, 'self.audioSessions[phase]=media')
        self.assertTrue('self.mediaSuspended)return' in text, 'self.mediaSuspended)return')
        self.assertTrue('O_NOFOLLOW' in text, 'O_NOFOLLOW')
        self.assertTrue('S_ISREG(before.st_mode)' in text, 'S_ISREG(before.st_mode)')

    def test_native_visual_and_only_authoritative_clock(self):
        bridge=(ROOT/'PhiMod/Sources/PMSongInterruptionGameplay.inc').read_text('utf8')
        self.assertTrue('PMSetSongInterruptionEffectHandler' in bridge)
        self.assertTrue('PMSongInterruptionEffectFrame:ok=scope->visual.validate(1)' in bridge)
        self.assertTrue('scope->visual.frame(' not in bridge)
        self.assertTrue('retainFailedGlitch(scope)' in bridge)
        self.assertTrue('drainGlitches();return gameplay.tick' in bridge)

    def test_production_owner(self):
        compiler = os.environ.get('CXX') or shutil.which('clang++') or shutil.which('g++') or shutil.which('cl')
        vcvars = Path('D:/Program Files (x86)/Microsoft Visual Studio/2019/Community/VC/Auxiliary/Build/vcvars64.bat')
        if not compiler and not (os.name == 'nt' and vcvars.is_file()):
            self.skipTest('C++17 compiler unavailable')
        # Never put build products/cache in the source checkout or on C:/F:.
        base = Path(os.environ.get('PM_INTERRUPTION_TEST_TMP', 'G:/phimod项目/本地测试归档/OS-av-hp-20261128/interruption' if os.name == 'nt' else '/tmp/interruption-tests'))
        if os.name == 'nt' and base.resolve().drive.upper() not in ('D:', 'G:'):
            self.fail('Interruption test scratch must be on D: or G:')
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='cpu-', dir=base) as folder:
            folder = Path(folder)
            output = folder / ('owner.exe' if os.name == 'nt' else 'owner')
            source = ROOT / 'tests/PMSongInterruptionTimelineTest.cpp'
            is_msvc = not compiler or Path(compiler).name.lower() in ('cl', 'cl.exe')
            if is_msvc:
                command = [compiler or 'cl', '/nologo', '/std:c++17', '/EHsc', '/W4', '/WX', '/utf-8',
                           str(source), '/Fe:' + str(output), '/Fo:' + str(folder / 'owner.obj')]
            else:
                command = [compiler, '-std=c++17', '-Wall', '-Wextra', '-Werror', str(source), '-o', str(output)]
            if not compiler:
                script = folder / 'build.cmd'
                script.write_text('@echo off\ncall "' + str(vcvars) + '" >nul\nif errorlevel 1 exit /b %errorlevel%\n' +
                                  subprocess.list2cmdline(command) + '\n', encoding='utf-8')
                command = ['cmd.exe', '/d', '/c', str(script)]
            env = dict(os.environ, TEMP=str(folder), TMP=str(folder), PYTHONDONTWRITEBYTECODE='1')
            result = subprocess.run(command, cwd=folder, env=env, capture_output=True, text=True, errors='replace', timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(output)], cwd=folder, env=env, capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('14 timeline/media groups passed', result.stdout)
            print(result.stdout.strip())


if __name__ == '__main__':
    unittest.main()
