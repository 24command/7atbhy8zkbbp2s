"""Stock 4.0.4 accepted-Start audio: SEPlayer.Play(6), not a generic click.

PHIGROS_404_ANALYSIS/PHIGROS_404_IPA enable binary/serialized-asset evidence.
The coordinator accepts the cue once before chapterStartIntro; audio lookup
failure is nonfatal and does not cancel a working Start path.
"""
import json
import os
from pathlib import Path
import re
import tempfile
import unittest
from zipfile import ZipFile

from test_native_os_chrome import ref, u32
from native_os_donors import SerializedFile
from test_native_os_transition_support import compile_cpp, run_cpp

IOS = Path(__file__).resolve().parents[1]
SOURCES = IOS / 'PhiMod/Sources'


class StartSoundAdapter(unittest.TestCase):
    def test_dispatch_is_separate_from_animation_and_selector(self):
        source = (SOURCES / 'PMNativeOSPlayTransition.inc').read_text('utf-8-sig')
        helper = (SOURCES / 'PMNativeOSStartSound.inc').read_text('utf-8-sig')
        self.assertIn('staticValue<P>(r.klass("SEPlayer"),"Play","SEPlayer.play")', helper)
        self.assertIn('int index=6;', helper)
        self.assertEqual(helper.count('r.call(callback,"Invoke",{"System.Int32"},{&index})'), 1)
        self.assertIn('if(!NSThread.isMainThread)return false;', helper)
        self.assertIn('entrance::require(callback,', helper)
        self.assertEqual(source.count('#include "PMNativeOSStartSound.inc"'), 1)
        self.assertNotIn('playStartSound(', source)  # no animation/capture replay
        self.assertEqual(helper.count('playStartSound('), 1)
        for forbidden in ('"PlayUnity"', '"PlayNA"', '"PlayHitFx"', '"NormalStart"',
                          'hook(', 'MSHook', 'dispatch_after', 'dispatch_async'):
            self.assertNotIn(forbidden, helper)

    def test_exact_once_dispatch_and_failure_without_fallback(self):
        function = (SOURCES / 'PMNativeOSStartSound.inc').read_text('utf-8-sig')
        code = r'''#include <cassert>
#include <cstring>
#include <initializer_list>
#include <stdexcept>
#include "HEADER"
using P=void*;
struct { bool isMainThread=true; } NSThread;
namespace pmbridge {
struct Runtime {
    int reads=0, calls=0, lastIndex=-1;
    bool fail=false;
    P callback=this, lastCallback=nullptr;
    P klass(const char *name){assert(!strcmp(name,"SEPlayer"));return this;}
    template<class T> T staticValue(P type,const char *field,const char *kind){
        assert(type==this && !strcmp(field,"Play") && !strcmp(kind,"SEPlayer.play"));
        ++reads; return static_cast<T>(callback);
    }
    P call(P target,const char *name,std::initializer_list<const char*> types,
           std::initializer_list<P> args){
        assert(target==callback && !strcmp(name,"Invoke") && types.size()==1 && args.size()==1);
        assert(!strcmp(*types.begin(),"System.Int32"));
        lastIndex=*static_cast<int*>(*args.begin());lastCallback=target;++calls;
        if(fail)throw std::runtime_error("managed audio failure");
        return nullptr; // a successful managed void Invoke returns null
    }
};
}
namespace pmnativeosscene {
using pmbridge::Runtime;
namespace entrance {
void require(bool ok,const char *message){if(!ok)throw std::runtime_error(message);}
template<class F> bool checked(F work){try{work();return true;}catch(const std::exception&){return false;}}
}
FUNCTION
}
int main(){
    pmbridge::Runtime r;
    NSThread.isMainThread=false;
    assert(!pmnativeosscene::playStartSound(r) && r.reads==0 && r.calls==0);
    NSThread.isMainThread=true;
    r.callback=nullptr;
    assert(!pmnativeosscene::playStartSound(r) && r.reads==1 && r.calls==0);
    r.callback=&r;
    assert(pmnativeosscene::playStartSound(r) && r.calls==1 && r.lastIndex==6);
    int replacement=0;r.callback=&replacement;
    assert(pmnativeosscene::playStartSound(r) && r.calls==2 && r.lastCallback==&replacement);
    r.fail=true;
    assert(!pmnativeosscene::playStartSound(r) && r.calls==3); // no fallback/retry
    assert(r.reads==4 && r.lastIndex==6);
}
'''
        code = code.replace('HEADER', (SOURCES / 'PMNativeOSStartSound.hpp').as_posix()).replace('FUNCTION', function)
        with tempfile.TemporaryDirectory(prefix='os-start-sound-') as directory:
            run_cpp(self, compile_cpp(code, directory, 'start-sound'))

    def test_main_owned_coordinator_acceptance_boundary(self):
        source = (SOURCES / 'PMNativeOSCoordinator.mm').read_text('utf-8-sig')
        start = source.split('bool playSelection(Runtime &r,NSDictionary *card,NSDictionary *choice){', 1)[1].split('bool wantsOSHome(', 1)[0]
        call = 'scene::playStartSound(r)'
        self.assertEqual(source.count(call), 1)
        at = start.index(call)
        self.assertLess(start.index('if(!song.info)'), at)
        self.assertLess(start.index('busy=true;', start.index('const Mode source=')), at)
        self.assertLess(at, start.index('auto resume='))
        self.assertLess(at, start.index('pmunlock::chapterStartIntro'))
        self.assertIn('(void)scene::playStartSound(r);', re.sub(r'\s+', '', start))
        self.assertNotIn('if(!scene::playStartSound', re.sub(r'\s+', '', start))
        self.assertIn('#include "PMNativeOSStartSound.hpp"', source)


@unittest.skipUnless(os.getenv('PHIGROS_404_ANALYSIS'), 'requires retail 4.0.4 analysis')
class RetailStartSound(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
        cls.decoder = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
        cls.base = Path(os.environ['PHIGROS_404_ANALYSIS'])
        script = json.loads((cls.base / 'script.json').read_bytes())
        cls.methods = {e['Address']: e['Name'] for e in script['ScriptMethod']}
        cls.metadata = {e['Address']: e['Name'] for e in script['ScriptMetadata']}
        cls.method_metadata = {e['Address']: e for e in script['ScriptMetadataMethod']}
        cls.dump = (cls.base / 'dump.cs').read_text('utf-8-sig')

    def ops(self, address, size):
        with (self.base / 'UnityFramework').open('rb') as binary:
            binary.seek(address)
            return [(i.mnemonic, i.op_str) for i in self.decoder.disasm(binary.read(size), address)]

    def test_c8_and_both_c9_phases_dispatch_after_latch_before_work(self):
        self.assertEqual(self.metadata[0x48c3df8], 'SEPlayer_TypeInfo')
        se = re.search(r'^public class SEPlayer[^\n]*\n\{.*?^\}', self.dump, re.M | re.S)[0]
        self.assertIn('public static SEPlayer.play Play; // 0x8', se)
        delegate = re.search(r'^public sealed class SEPlayer.play[^\n]*\n\{.*?^\}', self.dump, re.M | re.S)[0]
        self.assertIn('public virtual void Invoke(int i)', delegate)
        # Start address, onPlay latch, static delegate load, invocation and next work.
        for name, begin, latch, slot, invoke, after, next_method, offset in (
            ('Chapter8SelectMusicControl$$Play', 0x153886c, 0x1538930, 0x1538934, 0x153895c,
             0x1538980, 'SongSelectorItem$$GetLevelStartInfo', 0x1fd),
            ('Phigros2.Chapter9.Chapter9Phase1Control$$Play', 0x14f5090, 0x14f5134, 0x14f5138, 0x14f5160,
             0x14f5168, 'Phigros2.Chapter9.Chapter9Phase1Control$$FadeOutBgm', 0x141),
            ('Phigros2.Chapter9.Scripts.Chapter9Phase2Control$$Play', 0x15163ac, 0x1516498, 0x151649c, 0x15164c4,
             0x15164cc, 'Phigros2.Chapter9.Scripts.Chapter9Phase2Control$$FadeOutBgm', 0x1d1),
        ):
            with self.subTest(name=name):
                self.assertEqual(self.methods[begin], name)
                self.assertEqual(self.ops(latch, 4), [('strb', f'w8, [x19, #{offset:#x}]')])
                self.assertEqual(self.ops(slot, 20), [
                    ('adrp', 'x8, #0x48c3000'), ('add', 'x8, x8, #0xdf8'),
                    ('ldr', 'x8, [x8]'), ('ldr', 'x8, [x8, #0xb8]'), ('ldr', 'x8, [x8, #8]')])
                self.assertEqual(self.ops(invoke-16, 20), [
                    ('ldr', 'x9, [x8, #0x18]'), ('ldr', 'x0, [x8, #0x40]'),
                    ('ldr', 'x2, [x8, #0x28]'), ('mov', 'w1, #6'), ('blr', 'x9')])
                self.assertLess(latch, invoke)
                self.assertLess(invoke, after)
                mnemonic, target = self.ops(after, 4)[0]
                self.assertEqual(mnemonic, 'bl')
                self.assertEqual(self.methods[int(target[1:], 16)], next_method)
        # Locked/repeated Start exits before the latch and sound; no early click.
        self.assertEqual(self.ops(0x1538908, 20), [
            ('ldrb', 'w8, [x0, #0x18]'), ('cmp', 'w8, #1'), ('b.ne', '#0x153891c'),
            ('ldrb', 'w8, [x19, #0x1fd]'), ('tbz', 'w8, #0, #0x153892c')])
        self.assertEqual(self.ops(0x1538928, 4), [('ret', '')])
        for address, offset, exit_at in ((0x14f50ec, 0x141, 0x14f5220), (0x1516450, 0x1d1, 0x15166d8)):
            self.assertEqual(self.ops(address, 8), [
                ('ldrb', f'w8, [x19, #{offset:#x}]'), ('tbnz', f'w8, #0, #{exit_at:#x}')])
        for address, exit_at in ((0x14f5128, 0x14f5220), (0x151648c, 0x15166d8)):
            self.assertEqual(self.ops(address, 12), [
                ('ldrb', 'w8, [x0, #0x18]'), ('cmp', 'w8, #1'), ('b.ne', f'#{exit_at:#x}')])
        # C8's intro/save decision is later; the cue is not deferred to commit.
        self.assertEqual(self.ops(0x15389c0, 4), [('bl', '#0x14b07d0')])
        self.assertEqual(self.methods[0x14b07d0], 'SaveManagement$$LoadBool')

    def test_installed_delegate_uses_stock_backend_and_volume(self):
        self.assertEqual(self.method_metadata[0x48ea908]['MethodAddress'], 0x14b3c7c)
        self.assertEqual(self.method_metadata[0x48ea8f8]['MethodAddress'], 0x14b3ab4)
        self.assertEqual(self.ops(0x14b3488, 8), [('adrp', 'x26, #0x48ea000'), ('add', 'x26, x26, #0x908')])
        self.assertEqual(self.ops(0x14b3758, 8), [('adrp', 'x8, #0x48ea000'), ('add', 'x8, x8, #0x8f8')])
        for store in (0x14b36bc, 0x14b37b4):
            self.assertEqual(self.ops(store, 4), [('str', 'x20, [x8, #8]')])
        self.assertEqual(self.methods[0x14b3c7c], 'SEPlayer$$PlayUnity')
        self.assertEqual(self.methods[0x14b3ab4], 'SEPlayer$$PlayNA')
        self.assertEqual(self.ops(0x14b3d28, 4), [('ldr', 's0, [x8, #0xbc]')])
        self.assertEqual(self.ops(0x14b3b6c, 4), [('ldr', 's0, [x8, #0xbc]')])
        for address, target, name in ((0x14b3d34, 0x15c85fc, 'AddressableAudioSource$$set_Volume'),
                                      (0x14b3d7c, 0x15c885c, 'AddressableAudioSource$$Play'),
                                      (0x14b3b30, 0x15db794, 'E7.Native.NativeSource$$Play'),
                                      (0x14b3b78, 0x15dba84, 'E7.Native.NativeSource$$SetVolume')):
            self.assertIn(self.ops(address, 4)[0], [('bl', f'#{target:#x}'), ('b', f'#{target:#x}')])
            self.assertEqual(self.methods[target], name)


class RetailStartSoundAsset(unittest.TestCase):
    @unittest.skipUnless(os.getenv('PHIGROS_404_IPA'), 'requires retail 4.0.4 IPA')
    def test_index_six_is_tap7_in_both_serialized_backends(self):
        with ZipFile(os.environ['PHIGROS_404_IPA']) as ipa:
            def asset(name): return SerializedFile(ipa.read('Payload/Phigros.app/Data/' + name))
            scripts = asset('globalgamemanagers.assets')
            kind, script = scripts.objects[41]
            self.assertEqual(scripts.types[kind], 115)
            self.assertIn(b'SEPlayer', script)
            scene = asset('level0')
            kind, player = scene.objects[56]
            self.assertEqual(scene.types[kind], 114)
            self.assertEqual(ref(player, 16), (1, 41))
            self.assertEqual(u32(player, 28), 0)  # empty MonoBehaviour name
            count, pos = u32(player, 32), 36
            names = []
            for _ in range(count):
                n = u32(player, pos)
                names.append(player[pos+4:pos+4+n])
                pos = (pos+4+n+3) & ~3
            self.assertEqual(count, 16)
            self.assertEqual(names[6], b'Tap7')
            self.assertEqual(u32(player, pos), 16)
            self.assertEqual(ref(player, pos+4+12*6), (2, 30))
            externals = re.findall(rb'(?:[\w.]+\.assets|Library/unity default resources)\0', scene.tail)
            self.assertEqual(externals[1], b'sharedassets0.assets\0')
            shared = asset('sharedassets0.assets')
            kind, clip = shared.objects[30]
            self.assertEqual(shared.types[kind], 83)  # actual AudioClip, not guessed label
            self.assertEqual(clip[4:4+u32(clip, 0)], b'Tap7')


if __name__ == '__main__':
    unittest.main()
