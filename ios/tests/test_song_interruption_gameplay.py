"""Bounded native interruption integration: production controller + adapter contracts."""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'PhiMod/Sources'
BACKEND = (SOURCES / 'PMHookBackend.mm').read_text('utf-8-sig')
HELPER = (SOURCES / 'PMSongInterruptionGameplay.inc').read_text('utf-8-sig')


def body(text, signature):
    start = text.index(signature)
    begin = text.index('{', start)
    depth = 1
    for end in range(begin + 1, len(text)):
        depth += (text[end] == '{') - (text[end] == '}')
        if not depth:
            return text[begin + 1:end]
    raise AssertionError('unterminated function: ' + signature)


class NativeSongInterruption(unittest.TestCase):
    def test_production_controller(self):
        compiler = os.environ.get('CXX') or shutil.which('clang++') or shutil.which('g++') or shutil.which('cl')
        vcvars = Path('D:/Program Files (x86)/Microsoft Visual Studio/2019/Community/VC/Auxiliary/Build/vcvars64.bat')
        if not compiler and not (os.name == 'nt' and vcvars.is_file()):
            self.skipTest('C++17 compiler unavailable')
        base = Path(os.environ.get('PM_NATIVE_INTERRUPTION_TMP', 'G:/phimod项目/本地测试归档/OS-blue-performance-fix-20261127/tests' if os.name == 'nt' else '/tmp/pm-native-interruption'))
        if os.name == 'nt' and base.resolve().drive.upper() not in ('D:', 'G:'):
            self.fail('Native interruption scratch must be on D: or G:')
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='native-', dir=base) as folder:
            folder = Path(folder)
            output = folder / ('native-owner.exe' if os.name == 'nt' else 'native-owner')
            source = ROOT / 'tests/PMSongInterruptionGameplayTest.cpp'
            msvc = not compiler or Path(compiler).name.lower() in ('cl', 'cl.exe')
            if msvc:
                command = [compiler or 'cl', '/nologo', '/std:c++17', '/EHsc', '/W4', '/WX', '/utf-8',
                           str(source), '/Fe:' + str(output), '/Fo:' + str(folder / 'native-owner.obj')]
            else:
                command = [compiler, '-std=c++17', '-Wall', '-Wextra', '-Werror', str(source), '-o', str(output)]
            if not compiler:
                script = folder / 'build.cmd'
                script.write_text('@echo off\ncall "' + str(vcvars) + '" >nul\nif errorlevel 1 exit /b %errorlevel%\n' +
                                  subprocess.list2cmdline(command) + '\n', encoding='utf8')
                command = ['cmd.exe', '/d', '/c', str(script)]
            env = dict(os.environ, TEMP=str(folder), TMP=str(folder), PYTHONDONTWRITEBYTECODE='1')
            for command, timeout in [(command, 120), ([str(output)], 20)]:
                result = subprocess.run(command, cwd=folder, env=env, capture_output=True, text=True, errors='replace', timeout=timeout)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('34 native gameplay groups passed', result.stdout)
            print(result.stdout.strip())

    def test_existing_hooks_hold_before_original_or_practice(self):
        entries = [('onProgressUpdate', 'Progress', 'pmpractice::beforeProgress'),
                   ('onJudgeUpdate', 'Judge', 'pmpractice::entryLoading'),
                   ('onAddressableAudioUpdate', 'Audio', 'pmpractice::audioBefore'),
                   ('onNoteManager', 'Notes', 'pmpractice::entryLoading')]
        for name, entry, competing in entries:
            function = body(BACKEND, 'void ' + name + '(P self,P mi)')
            gate = 'if(songinterruption::tick(songinterruption::Entry::' + entry + ',self))return;'
            self.assertIn(gate, function)
            self.assertLess(function.index(gate), function.index(competing))
            self.assertLess(function.index(gate), function.index('orig<'))
        manifest = json.loads((ROOT / 'tools/gameplay_hook_manifest.json').read_bytes())
        self.assertEqual(len(manifest), 88)
        self.assertNotIn('songinterruption', '\n'.join(x['id'] for x in manifest).lower())
        callbacks = BACKEND.split('P callbacks[h::Count]={', 1)[1].split('};', 1)[0]
        self.assertNotIn('songinterruption', callbacks)

    def test_progress_only_discovery_and_post_native_crossing(self):
        tick = body(HELPER, 'bool tick(Entry entry,Object object)')
        fast_path = 'if(entry!=Entry::Progress&&!frozen&&!recovering)return false;'
        self.assertLess(tick.index(fast_path), tick.index('host.matches('))
        self.assertLess(tick.index(fast_path), tick.index('host.live('))
        self.assertLess(tick.index(fast_path), tick.index('host.eligible('))
        progress = body(BACKEND, 'void onProgressUpdate(P self,P mi)')
        gate = 'if(songinterruption::tick(songinterruption::Entry::Progress,self))return;'
        self.assertEqual(progress.count(gate), 2)
        native = progress.index('orig<VoidFn>(h::progressUpdate)(self,mi)')
        self.assertLess(progress.index(gate), native)
        post = progress.index(gate, native)
        self.assertLess(native, post)
        self.assertLess(post, progress.index('pmsecretcourse::progressFrame'))
        self.assertLess(post, progress.index('updateStoryPresentation'))

    def test_exact_installed_identity_does_not_enable_hp(self):
        bind = body(BACKEND, 'bool bindDoor(')
        self.assertIn('!hpEligible&&!PMDoorReplayPending()&&!PMSongInterruptionPending()', bind)
        consume = bind.index('songinterruption::gameplay.begin(level,pc,identifier,slot)')
        for check in ('if(![key hasPrefix:prefix])return reject(', 'if(slot!=transport)return reject(',
                      'PMDoorConsumeReplay(group,slot,identifier)', 'if(installed&&slot>=0)'):
            self.assertLess(bind.index(check), consume)
        self.assertLess(consume, bind.index('if(!hpEligible)'))
        self.assertLess(bind.index('if(!hpEligible)'), bind.index('PMDoorBeginExactTrack'))
        self.assertIn('return terminal;', bind)
        self.assertNotIn('options.assisted', HELPER)
        self.assertNotIn('pmhp::', HELPER)
        self.assertNotIn('doorPlayEligible', HELPER)
        self.assertIn('!pmsecretcourse::active()', HELPER)
        normal = body(BACKEND, 'void onNormalStart(')
        self.assertLess(normal.index('PMCancelSongInterruptionLaunch();'), normal.index('pmstory::captureLaunch();'))

    def test_start_consumes_terminal_pending_without_reapplying_hp(self):
        awake = body(BACKEND, 'void onAwake(')
        self.assertLess(awake.index('prepareDoor('), awake.index('orig<VoidFn>(h::levelAwake)'))
        self.assertLess(awake.index('pmhp::prepare('), awake.index('orig<VoidFn>(h::levelAwake)'))
        self.assertNotIn('prepareSongInterruption(', awake)
        original = awake.index('orig<VoidFn>(h::levelAwake)')
        self.assertLess(awake.index('nativeHost.launch("Awake pending"'), original)
        self.assertGreater(awake.index('nativeHost.launch("Awake returned pending"'), original)
        prepare = body(BACKEND, 'void prepareDoor(')
        self.assertIn('if(!PMSongInterruptionPending())songinterruption::gameplay.end();', prepare)
        start = body(BACKEND, 'void onProgressStart(')
        self.assertLess(start.index('orig<VoidFn>(h::progressStart)(self,mi);', start.index('pmpractice::begin')),
                        start.index('prepareSongInterruption(R(),self)'))
        bind = body(BACKEND, 'bool bindDoor(')
        self.assertIn('if(interruptionOnly&&PMSongInterruptionPending())', bind)
        self.assertIn('!interruptionOnly&&applyChapterReplay(', bind)
        self.assertLess(bind.index('if(interruptionOnly)return terminal;'), bind.index('PMDoorBeginExactTrack'))
        terminal = body(BACKEND, 'void prepareSongInterruption(')
        self.assertLess(terminal.index('"progressControl")!=pc'), terminal.index('bindDoor('))
        self.assertIn('bindDoor(r,currentLevel,frozenOptions,true)', terminal)

    def test_verified_404_awake_start_machine_code(self):
        analysis = Path(os.environ.get('PHIGROS_404_ANALYSIS', 'G:/phimod项目/Phigros_4.0.4.ipa/analysis'))
        binary = analysis / 'UnityFramework'
        if not binary.is_file():
            self.skipTest('local retail 4.0.4 binary unavailable')
        from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
        decoder = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
        data = binary.read_bytes()
        def instruction(address):
            op = next(decoder.disasm(data[address:address + 4], address))
            return op.mnemonic, op.op_str
        # Awake attaches level mods; it does NOT initialize progressControl/levelInformation.
        self.assertEqual(instruction(0x1581B34), ('bl', '#0x154a738'))  # Doppelganger.TryAttach
        self.assertEqual(instruction(0x1581C0C), ('bl', '#0x37f2998'))  # InstantiateAsync
        awake = list(decoder.disasm(data[0x1581A4C:0x1581CD4], 0x1581A4C))
        self.assertFalse(any(op.mnemonic.startswith('st') and '[x19' in op.op_str for op in awake))
        # Start reads existing audioSource and LevelStartInfo.songsLevel, sets volume/index.
        self.assertEqual(instruction(0x1593258), ('ldr', 'x0, [x0, #0x38]'))
        self.assertEqual(instruction(0x1593268), ('bl', '#0x15c85fc'))
        self.assertEqual(instruction(0x15932AC), ('ldr', 'x0, [x8, #0x38]'))
        self.assertEqual(instruction(0x15932B4), ('bl', '#0x14cb004'))
        self.assertEqual(instruction(0x15932B8), ('str', 'w0, [x19, #0xd8]'))
        # LevelControl.Start's coroutine marks chartLoaded only after asynchronous chart setup.
        self.assertEqual(instruction(0x158582C), ('strb', 'w9, [x8, #0x68]'))
        dump = (analysis / 'dump.cs').read_text(encoding='utf-8-sig')
        # NativeHost.keep/eligible/live use Runtime.alive (Unity Object.op_Implicit).
        # In 4.0.4 every rooted component really is a Unity object, including Info.
        for component in ('LevelControl', 'ProgressControl', 'LevelInformation', 'JudgeControl',
                          'AddressableAudioSource', 'NoteUpdateManager'):
            self.assertIn('public class ' + component + ' : MonoBehaviour //', dump)
        self.assertIn('public sealed class AudioSource : AudioBehaviour //', dump)
        level = dump.split('public class LevelControl : MonoBehaviour', 1)[1].split('// Methods', 1)[0]
        self.assertIn('public ProgressControl progressControl; // 0x28', level)
        start_info = dump.split('public class LevelStartInfo //', 1)[1].split('// Properties', 1)[0]
        for field in ('public string songsId; // 0x10', 'public string songsLevel; // 0x38',
                      'public string chartAddressableKey; // 0x50'):
            self.assertIn(field, start_info)

    def test_scene_ownership_callbacks_and_story_fence(self):
        begin = body(HELPER, 'template<class Identifier> bool begin(')
        self.assertLess(begin.index('host.configure('), begin.index('host.begin('))
        self.assertIn('[this,ticket]', begin)
        self.assertIn('if(owns(ticket))invalidated()', begin)
        self.assertIn('gchandle_new(value,false)', HELPER)
        self.assertIn('gchandle_get_target', HELPER)
        self.assertIn('level!=currentLevel', HELPER)
        self.assertIn('"GetActiveScene"', HELPER)
        destroy = body(BACKEND, 'void onDestroy(')
        self.assertIn('if(self==currentLevel)songinterruption::gameplay.end();', destroy)
        self.assertLess(destroy.index('gameplay.end()'), destroy.index('currentLevel=nullptr'))
        for name in ('onProgressUpdate', 'onJudgeUpdate'):
            function = body(BACKEND, 'void ' + name + '(')
            self.assertLess(function.index('songinterruption::PauseFence'), function.index('StoryPauseScope'))
        self.assertIn('gameplay.unloaded(scene.handle)', BACKEND)

    def test_freeze_is_not_normal_pause_or_stock_coroutine(self):
        native = HELPER.split('struct NativeHost {', 1)[1]
        for field in ('"canPause",false', '"canLevelOver",false', '"stopJudge",true', '"isPlaying",false'):
            self.assertIn(field, body(native, 'void hold('))
        self.assertIn('"Pause"', body(native, 'void pause('))
        self.assertIn('if(R().get<bool>(object(o,Audio),"playFlag"))pause(o);', body(native, 'void repauseIfPlaying('))
        self.assertNotRegex(native, r'\.call\([^;]+"(?:Stop|Play)"')
        self.assertNotIn('DestructAnimation', native)
        self.assertNotIn('timeScale', native)
        self.assertNotIn('SaveBool', native)
        self.assertIn('guard.store(true)', body(native, 'void protect('))
        resume = body(native, 'void resume(')
        self.assertLess(resume.index('"Seek"'), resume.index('"PlayScheduled"'))
        self.assertLess(resume.index('"PlayScheduled"'), resume.index('"isPlaying"'))
        self.assertNotIn('"playFlag"', resume)
        self.assertNotIn('clocks(o,s)', resume)

    def test_only_user_action_can_quit(self):
        core = HELPER.split('#ifndef PM_SONG_INTERRUPTION_GAMEPLAY_TEST', 1)[0]
        self.assertEqual(core.count('host.quit();'), 1)
        close = body(core, 'void close(')
        self.assertIn('!owns(ticket)', close)
        self.assertIn('quitClaimed=true', close)
        self.assertLess(close.index('quitClaimed=true'), close.index('host.quit()'))
        native_quit = body(HELPER, ' void quit()')
        self.assertIn('"Application"),"Quit"', native_quit)
        self.assertIn('std::exit(EXIT_SUCCESS)', native_quit)
        self.assertEqual(HELPER.count('std::exit('), 1)

    def test_verified_404_resume_machine_code(self):
        analysis = Path(os.environ.get('PHIGROS_404_ANALYSIS', 'G:/phimod项目/Phigros_4.0.4.ipa/analysis'))
        binary = analysis / 'UnityFramework'
        if not binary.is_file():
            self.skipTest('local retail 4.0.4 binary unavailable')
        from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
        decoder = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
        def instruction(address):
            with binary.open('rb') as f:
                f.seek(address)
                raw = f.read(4)
            op = next(decoder.disasm(raw, address))
            return op.mnemonic, op.op_str
        self.assertEqual(instruction(0x15C8524), ('bl', '#0x391d194'))  # Pause physically stops.
        self.assertEqual(instruction(0x15C9114), ('bl', '#0x391cb90'))  # Seek physical cursor.
        self.assertEqual(instruction(0x15C9120), ('str', 's8, [x19, #0x40]'))
        self.assertEqual(instruction(0x15C9134), ('stp', 'd0, d1, [x19, #0x68]'))  # DSP reset.
        self.assertEqual(instruction(0x15C91FC), ('bl', '#0x391cf3c'))  # Physical PlayScheduled.
        self.assertEqual(instruction(0x15C9208), ('strb', 'wzr, [x19, #0xa0]'))
        self.assertEqual(instruction(0x15C9C20), ('strb', 'w9, [x8, #0x44]'))  # Native playFlag coroutine.


if __name__ == '__main__':
    unittest.main(verbosity=2)
