"""4.0.4 selector contracts. Set PHIGROS_404_ANALYSIS to the local analysis directory."""
import os
from pathlib import Path
import re
import unittest


class StoryNativeStart(unittest.TestCase):
    def test_checks_before_exact_arm(self):
        src = Path(__file__).resolve().parents[1] / 'PhiMod/Sources/PMContentRuntime.mm'
        start = src.read_text('utf8').split('static BOOL startCheckpointSong(Runtime &r,', 1)[1].split('void levelBegin(', 1)[0]
        arm = start.index('if(!arm(nativeGroup,slot,resolvedChartID))')
        for guard in ('checkpointOfficialOpen(r,song,official,slot)', 'r.get<int>(selector,"nowLevel")!=slot',
                      'r.get<bool>(selector,"onStart")', 'slot>=r.get<int>(item,"<PlayableLevelCount>k__BackingField")',
                      'r.call(item,"get_Unlocked")', 'r.call(start,"IsInteractable")'):
            self.assertLess(start.index(guard), arm, guard)
        self.assertLess(arm, start.index('r.call(selector,"NormalStart")'))

    @unittest.skipUnless(os.environ.get('PHIGROS_404_ANALYSIS'), 'requires local dump.cs and UnityFramework')
    def test_native_normal_start(self):
        from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
        analysis = Path(os.environ['PHIGROS_404_ANALYSIS'])
        dump = (analysis / 'dump.cs').read_text('utf-8-sig')

        def klass(name):
            return re.search(r'^public class ' + name + r' [^\n]*\n\{.*?^\}', dump, re.M | re.S)[0]

        def address(body, signature):
            return int(re.search(r'// RVA: 0x(\w+)[^\n]*\n\s*' + re.escape(signature), body)[1], 16)

        def field(body, name):
            return int(re.search(re.escape(name) + r'; // 0x(\w+)', body)[1], 16)

        selector, item = klass('SongSelector'), klass('SongSelectorItem')
        self.assertIn('public float[] difficulty;', klass('SongsItem'))
        self.assertIn('public void SetLevel(int levelIndex = -1)', selector)
        self.assertIn('public void CheckSongUnlock(string songsId, out int unlockType, out bool[] chartUnlocked, out bool appeared, out string unlockInfo)', klass('GameInformation'))
        start = address(selector, 'public void NormalStart()')
        launch = address(selector, 'private void GameStart(int songIndex, int levelIndex)')
        with (analysis / 'UnityFramework').open('rb') as binary:
            binary.seek(start)
            native = list(Cs(CS_ARCH_ARM64, CS_MODE_ARM).disasm(binary.read(0xB0), start))
        asm = [(i.mnemonic, i.op_str) for i in native]
        cursor = 0
        for op in [('ldrb', f'w8, [x19, #{field(selector,"bool onStart"):#x}]'),
                   ('ldrb', f'w8, [x0, #{field(item,"bool <Unlocked>k__BackingField"):#x}]'),
                   ('ldr', f'w8, [x0, #{field(item,"int <PlayableLevelCount>k__BackingField"):#x}]'),
                   ('ldr', f'w2, [x19, #{field(selector,"int nowLevel"):#x}]'),
                   ('cmp', 'w8, w2'), ('bl', f'#{launch:#x}'),
                   ('strb', f'w8, [x19, #{field(selector,"bool onStart"):#x}]')]:
            cursor = asm.index(op, cursor) + 1
        latch = asm.index(('ldrb', f'w8, [x19, #{field(selector,"bool onStart"):#x}]'))
        exits = [(i.mnemonic, i.op_str.split(', ')[-1]) for i in native[latch:cursor]
                 if i.mnemonic in ('tbnz', 'b.ne', 'b.le')]
        self.assertEqual([op for op, _ in exits], ['tbnz', 'b.ne', 'b.le'])
        self.assertEqual(len({target for _, target in exits}), 1)
        self.assertGreater(int(exits[0][1][1:], 16), native[cursor - 1].address)

        # GameStart passes the unchanged native difficulty to the row. The row
        # forwards it to SongsItem, including AT (the transport for named charts).
        signature = 'public LevelStartInfo GetLevelStartInfo(int level)'
        row_info = address(item, signature)
        song_info = address(klass('SongsItem'), signature)
        with (analysis / 'UnityFramework').open('rb') as binary:
            def instructions(begin, size):
                binary.seek(begin)
                return [(i.mnemonic, i.op_str) for i in
                        Cs(CS_ARCH_ARM64, CS_MODE_ARM).disasm(binary.read(size), begin)]
            game = instructions(launch, start - launch)
            row = instructions(row_info, 0x110)
        call = game.index(('bl', f'#{row_info:#x}'))
        self.assertIn(('mov', 'x20, x2'), game[:call])
        self.assertEqual(game[call-2:call], [('mov', 'x1, x20'), ('mov', 'x2, #0')])
        call = row.index(('bl', f'#{song_info:#x}'))
        self.assertIn(('mov', 'x19, x1'), row[:call])
        self.assertEqual(row[call-2:call], [('mov', 'x1, x19'), ('mov', 'x2, #0')])


if __name__ == '__main__':
    unittest.main()
