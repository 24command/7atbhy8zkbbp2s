"""CPU lifecycle scenarios plus UIKit/NativeHost wiring contracts (no UIKit runtime)."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(os.environ.get('PM_LIFECYCLE_REPO', str(Path(__file__).resolve().parents[1])))
if (ROOT / 'ios').is_dir():
    ROOT = ROOT / 'ios'
SOURCES = ROOT / 'PhiMod/Sources'


def body(text, signature):
    begin = text.index('{', text.index(signature))
    depth = 1
    for end in range(begin + 1, len(text)):
        depth += (text[end] == '{') - (text[end] == '}')
        if not depth:
            return text[begin + 1:end]
    raise AssertionError('unterminated body: ' + signature)


CASES = r'''
#include "../PhiMod/Sources/PMSongInterruptionWindow.hpp"
int main() {
 using State = decltype(FakeHost{}.uiState);
 // Frozen song clock before 159 counts nothing, regardless of elapsed wall time.
 {Run r; r.bind(); r.h.state.now=158.5f; r.h.state.playing=false;
  auto ticket=r.h.uiState.ticket();
  for(int n=0;n<10000;++n) {
   assert(!r.frame());
   assert(!r.h.uiState.claimAlert(ticket,10000.0+n,true));
  }
  assert(r.h.pauses==0 && r.h.triggers==0 && r.h.uiState.phase()==State::Phase::Playing);
  r.h.state.playing=true; r.h.state.now=159.015259f;
  assert(r.frame()); assert(r.h.pauses==1 && r.h.triggers==1);
 }
 // A paused due sample is retained; resuming at the same song time can fire.
 {Run r; r.bind(); r.h.state.now=159.015259f; r.h.state.playing=false;
  assert(!r.frame()); assert(r.h.triggers==0 && r.h.uiState.due(r.h.state.now));
  r.h.state.playing=true; assert(r.frame()); assert(r.h.triggers==1);
 }
 for(bool scene : {false,true}) {
  auto active=[scene](bool appActive, bool sceneActive) {
   return pmsonginterruption::windowActive(true,false,appActive,scene,sceneActive);
  };
  // Suspend after attachment but BEFORE first display: return starts a fresh 2s.
  {Run r; r.bind(); assert(r.frame()); auto ticket=r.h.uiState.ticket();
   assert(!r.h.uiState.firstDisplay(ticket,10,true,active(false,false)));
   assert(!r.h.uiState.claimAlert(ticket,1000,active(false,false)));
   assert(r.g.validHost() && r.h.uiState.owns(ticket) && r.g.holding());
   assert(!r.h.uiState.claimAlert(ticket,1000,active(true,true)));
   assert(r.h.uiState.firstDisplay(ticket,1000,true,active(true,true)));
   assert(!r.h.uiState.claimAlert(ticket,1001.999,true));
   assert(r.h.uiState.claimAlert(ticket,1002,true));
  }
  // Suspend AFTER first display: deadline persists; active return claims once.
  {Run r; r.bind(); assert(r.frame()); auto ticket=r.h.uiState.ticket();
   assert(r.h.uiState.firstDisplay(ticket,10,true,active(true,true)));
   assert(!r.h.uiState.claimAlert(ticket,11,true));
   for(double now : {12.0,1000.0})
    assert(!r.h.uiState.claimAlert(ticket,now,active(false,false)));
   assert(r.g.validHost() && r.h.uiState.owns(ticket));
   if(scene) assert(!r.h.uiState.claimAlert(ticket,1000,active(true,false)));
   // A focus callback restarting native audio is re-paused by existing hooks.
   r.h.playFlag=true; r.h.sound=true;
   assert(r.frame(Entry::Audio,13));
   assert(r.h.pauses==2 && !r.h.sound && r.h.resumes==0);
   assert(!r.h.uiState.firstDisplay(ticket,1001,true,active(true,true)));
   assert(r.h.uiState.claimAlert(ticket,1001,active(true,true)));
   assert(!r.h.uiState.claimAlert(ticket,1002,true));
   // User action may arrive across deactivation; claim remains once-only.
   assert(r.h.quits==0);
   assert(r.h.uiState.claimQuit(ticket)); r.h.quitCallback(); r.h.quitCallback();
   assert(!r.h.uiState.claimQuit(ticket));
   assert(r.h.quits==1 && r.h.resumes==0 && r.h.uiState.blocking() && r.g.holding());
   auto staleQuit=r.h.quitCallback; r.g.end(); staleQuit();
   assert(r.h.quits==1 && r.h.resumes==0 && !r.g.holding());
   assert(!r.h.uiState.claimAlert(ticket,2000,true));
  }
 }
 std::cout << "6 lifecycle scenarios passed (actual Owner/Gameplay, fake native adapter)\n";
 return 0;
}
'''


class SongInterruptionLifecycle(unittest.TestCase):
    def test_native_and_notification_source_contracts(self):
        ui = (SOURCES / 'PMSongInterruption.mm').read_text('utf-8-sig')
        native = (SOURCES / 'PMSongInterruptionGameplay.inc').read_text('utf-8-sig')
        observer = body(ui, '- (void)observe:(PMInterruptionTicket)ticket {')
        for name in ('UIApplicationWillResignActiveNotification', 'UIApplicationDidEnterBackgroundNotification',
                     'UIApplicationDidBecomeActiveNotification', 'UISceneWillDeactivateNotification',
                     'UISceneDidActivateNotification'):
            self.assertIn(name, observer)
        self.assertIn('owner.clock.paused = !activeWindow(owner.gameWindow)', observer)
        self.assertIn('[note.name isEqual:UISceneDidDisconnectNotification] && note.object == owner.gameScene', observer)
        self.assertIn('[note.name isEqual:UIWindowDidBecomeHiddenNotification] && note.object == owner.gameWindow', observer)
        self.assertEqual(observer.count('[owner invalidate:ticket]'), 1)
        for call in ('firstDisplay(', 'claimAlert(', 'claimQuit(', 'retirePlaying(', 'state.end(', 'close:'):
            self.assertNotIn(call, observer)
        step = body(ui, '- (void)step:(CADisplayLink *)clock {')
        self.assertLess(step.index('if (!active)'), step.index('state.firstDisplay('))
        self.assertLess(step.index('state.firstDisplay('), step.index('state.claimAlert('))
        self.assertIn('continuousSeconds()', step)
        self.assertIn('mach_continuous_time()', body(ui, 'static double continuousSeconds()'))
        # Pausing is eligibility, never a lifetime failure that consumes the attempt.
        live = body(native, 'bool live(const Owner&o)')
        for flag in ('"isPlaying"', '"playFlag"', '"levelBegan"'):
            self.assertNotIn(flag, live)
        self.assertIn('r.get<bool>(pc,"isPlaying")', body(native, 'bool eligible(const Owner&o)'))
        self.assertIn('owns(ticket)&&host.live(owner)', body(native, 'bool begin(Object level'))
        close = body(ui, '- (void)close:(PMInterruptionTicket)ticket {')
        self.assertIn('state.claimQuit(ticket)', close)
        self.assertNotIn('activeWindow(', close)
        self.assertNotIn('resume(', close)
        self.assertIn('self.quit = nil', close)

    def test_lifecycle_cpu(self):
        compiler = os.environ.get('CXX') or shutil.which('clang++') or shutil.which('g++') or shutil.which('cl')
        vcvars = Path('D:/Program Files (x86)/Microsoft Visual Studio/2019/Community/VC/Auxiliary/Build/vcvars64.bat')
        if not compiler and not (os.name == 'nt' and vcvars.is_file()):
            self.skipTest('C++17 compiler unavailable')
        base = Path(os.environ.get('PM_INTERRUPTION_TEST_TMP',
            'G:/phimod项目/本地测试归档/OS-trigger-fix-20261128' if os.name == 'nt' else '/tmp/pm-lifecycle'))
        if os.name == 'nt' and base.resolve().drive.upper() not in ('D:', 'G:'):
            self.fail('Lifecycle scratch must be on D: or G:')
        base.mkdir(parents=True, exist_ok=True)
        # Reuse the existing native adapter fixture; compile the production Owner
        # and Gameplay directly. This deliberately does not model UIKit delivery.
        fixture = (ROOT / 'tests/PMSongInterruptionGameplayTest.cpp').read_text('utf-8-sig')
        fixture = fixture[:fixture.index('int main()')]
        with tempfile.TemporaryDirectory(prefix='lifecycle-', dir=base) as folder:
            folder = Path(folder)
            source = folder / 'lifecycle.cpp'
            source.write_text(fixture + CASES, encoding='utf-8')
            output = folder / ('lifecycle.exe' if os.name == 'nt' else 'lifecycle')
            if not compiler or Path(compiler).name.lower() in ('cl', 'cl.exe'):
                command = [compiler or 'cl', '/nologo', '/std:c++17', '/EHsc', '/W4', '/WX', '/utf-8',
                           '/I' + str(ROOT / 'tests'), str(source), '/Fe:' + str(output), '/Fo:' + str(folder / 'lifecycle.obj')]
            else:
                command = [compiler, '-std=c++17', '-Wall', '-Wextra', '-Werror', '-I', str(ROOT / 'tests'), str(source), '-o', str(output)]
            if not compiler:
                script = folder / 'build.cmd'
                script.write_text('@echo off\ncall "' + str(vcvars) + '" >nul\nif errorlevel 1 exit /b %errorlevel%\n' +
                                  subprocess.list2cmdline(command) + '\n', encoding='utf-8')
                command = ['cmd.exe', '/d', '/c', str(script)]
            env = dict(os.environ, TEMP=str(folder), TMP=str(folder), PYTHONDONTWRITEBYTECODE='1')
            for invocation, timeout in ((command, 120), ([str(output)], 20)):
                result = subprocess.run(invocation, cwd=folder, env=env, capture_output=True, text=True, errors='replace', timeout=timeout)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('6 lifecycle scenarios passed', result.stdout)
            print(result.stdout.strip())


if __name__ == '__main__':
    unittest.main(verbosity=2)
