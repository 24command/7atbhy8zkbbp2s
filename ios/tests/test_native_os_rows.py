"""Source/metadata contracts for rows crossing a Single scene load, not a device test."""
import os
import re
import unittest
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / 'PhiMod/Sources'
ROWS = (SRC / 'PMNativeOSRows.inc').read_text('utf-8-sig')
CONTENT = (SRC / 'PMContentRuntime.mm').read_text('utf-8-sig')


class NativeOSRows(unittest.TestCase):
    def test_locked_members_are_read_only(self):
        gate = CONTENT.split('static BOOL checkedSong(Runtime &r', 1)[1].split('if(collect){', 1)
        self.assertIn('![chapterIDs containsObject:installedID]', gate[0])
        self.assertIn('if(sibling)return NO', gate[0])
        self.assertIn('checkpointOfficialOpen(r,song,official,slot)', gate[0])
        self.assertIn('courseMemberOpen(r,group,authored,!resolveSiblings)', gate[1].split('return collect(',1)[0])
        unlock = (SRC / 'PMUnlockRuntime.mm').read_text('utf8')
        opened = unlock.split('bool opened(',1)[1].split('bool chapterBlocked(',1)[0]
        self.assertLess(opened.index('!persist'), opened.index('[progress open:'))
        self.assertIn('chapterBlocked(r,group,chart,persist)',unlock)
        self.assertIn('opened(r,chart[@"id"],persist)',unlock)
        self.assertIn('coverPath(next.r,identifier,false)',ROWS)

    def test_map_rows_do_not_depend_on_selector_scroll_position(self):
        snapshot = ROWS.split('std::unique_ptr<Saved> snapshot(', 1)[1].split('} // namespace', 1)[0]
        self.assertNotIn('get<bool>(original,"visible")', snapshot)
        self.assertIn('r.call(original,"get_Unlocked")', snapshot)
        self.assertIn('r.put(row.get(),"visible",true)', snapshot)

    def test_best_effort_entries_and_empty_map(self):
        prepare = ROWS.split('bool prepare(',1)[1].split('bool lookup(',1)[0]
        loop = prepare.split('for(id entry in entries)',1)[1].split('if(!currentSelector(',1)[0]
        # A denied checkedSong, an invalid entry and a thrown row-specific error
        # must all reach the next entry. Only a successful snapshot enters rows.
        self.assertNotIn('return false;',loop)
        self.assertIn('continue;',loop)
        self.assertIn('catch(const std::exception',loop)
        self.assertIn('@catch(NSException',loop)
        self.assertLess(loop.index('if(!saved)return NO'),loop.index('rows.emplace('))
        self.assertNotIn('!entries.count',prepare)
        self.assertNotIn('rows.empty()',prepare)
        coordinator=(SRC/'PMNativeOSCoordinator.mm').read_text('utf8')
        self.assertIn('if(!rows::prepare(',coordinator)
        self.assertIn('if(rowFor(entry,row)){first=entry;break;}',coordinator)

    def test_revision_checked_at_publish_and_lookup(self):
        context=ROWS.split('static bool currentSelector(',1)[1].split('bool prepare(',1)[0]
        for check in ('applied!=revision','shared.revision!=revision','loadingSelector','chapterCode'):
            self.assertIn(check,context)
        before,after=ROWS.split('for(id entry in entries)',1)
        check='currentSelector(r,selector,chapter,next->revision)'
        self.assertIn(check,before)
        self.assertLess(after.index(check),after.index('batch=std::move(next)'))
        lookup=ROWS.split('bool lookup(',1)[1]
        self.assertLess(lookup.index('batch->revision!=PMContentStore.shared.revision'),lookup.index('sprite('))
        self.assertGreater(lookup.rindex('batch->revision!=PMContentStore.shared.revision'),lookup.index('sprite('))

    def test_local_and_native_cover_paths(self):
        self.assertIn('NSString *identifier=chart?chart[@"id"]:group;',ROWS)
        self.assertIn('coverFolder:identifier',ROWS)
        self.assertIn('if(chart&&!art)return {};',ROWS)
        self.assertIn('r.put(data.get(),"songsKey",r.managedString(identifier))',ROWS)
        self.assertIn('if(art){',ROWS)
        self.assertIn('"coverAssetCode","BuildCoverImageId"',ROWS)
        self.assertIn('"coverBlurAssetCode","BuildBlurImageId"',ROWS)
        self.assertIn('mask&(1<<slot)',ROWS)
        self.assertIn('saved.cover?sprite(batch->r,*saved.cover):nullptr',ROWS)

    def test_row_is_fresh_data_and_not_a_selector_clone(self):
        snap = ROWS.split('std::unique_ptr<Saved> snapshot(', 1)[1].split('} // namespace', 1)[0]
        self.assertNotIn('MemberwiseClone', snap)
        for name in ('SongSelectorItem', 'SongsItem', 'LevelRecord'):
            self.assertIn(f'r.object_new(r.klass("{name}"))', snap)
        fields = set(re.findall(r'r\.put\(row\.get\(\),"([^"]+)"', snap))
        self.assertTrue({'songInfo','records','coverAssetCode'} <= fields)
        self.assertFalse(fields & {'selectorItemUpside','selectorItemDownside','cover','coverRect','background','backgroundImage','lockMask','previewClipPlayer'})
        self.assertIn('PMDifficultyRecordLevel(chart)',snap)
        self.assertIn('{r.managedString(identifier),r.managedString(recordLevel)}',snap)
        self.assertIn('localCover(next,identifier)',snap)
        lookup = ROWS.split('bool lookup(', 1)[1]
        for forbidden in ('selector','checkedSong','GetSongRecord','coverPath','GetLevelStartInfo'):
            self.assertNotIn(forbidden,lookup)

    def test_capture_uses_native_row_mods_and_exact_content_assets(self):
        capture = ROWS.split('Root captureStart(', 1)[1].split('std::unique_ptr<Saved> snapshot(', 1)[0]
        self.assertIn('r.call(song,"MemberwiseClone")', capture)
        self.assertIn('"extraLevelMods","chartAssetCode"', capture)
        self.assertIn('r.put(item.get(),"songInfo",source.get())', capture)
        self.assertIn('"difficulty","charter"', capture)
        self.assertNotIn('"levels"', capture)  # keep the native transport label, e.g. AT
        self.assertLess(capture.index('r.call(item.get(),"GetLevelStartInfo"'),
                        capture.index('applyExactLevelInfo(r,group,chart,info.get())'))
        self.assertIn('Root info;', ROWS)
        self.assertIn('info(std::move(start))', ROWS)
        self.assertIn('applyExactLevelInfo(r,id,custom,info)', CONTENT)
        self.assertIn('if(capturingStartInfo(song))return', CONTENT)
        unlock = (SRC/'PMUnlockRuntime.mm').read_text('utf8')
        for entry, marker in [('songInfo','song'), ('itemInfo','info')]:
            hook = unlock.split(f'void {entry}(', 1)[1].split('\n', 1)[0]
            self.assertLess(hook.index(f'capturingStartInfo({marker})'), hook.index('difficultyForSong('))

    def test_resolve_rechecks_saved_member_after_selector_teardown(self):
        resolve = ROWS.split('Start resolveStart(', 1)[1].split('bool lookup(', 1)[0]
        for check in ['NSThread.isMainThread', 'batch==current', 'runtime==&r',
                      'applied==current->revision', 'shared.revision==current->revision',
                      'current->rows.find(key(sid,diff))', 'PMUnlockMediaBusy()']:
            self.assertIn(check, resolve)
        order = ['if(!valid())', 'checkpointOfficialGroupOpen(r,r.managedString(saved.group),official,saved.slot)',
                 'courseMemberOpen(r,saved.group,saved.chart,false)', '|| !valid()',
                 'return {saved.info.get(),saved.group,saved.slot,saved.chart[@"id"]?:saved.group}']
        self.assertEqual(sorted(resolve.index(s) for s in order), [resolve.index(s) for s in order])
        for forbidden in ['selector', 'songFor(', 'GetLevelStartInfo', 'sprite(']:
            self.assertNotIn(forbidden, resolve)

    @unittest.skipUnless(os.environ.get('PHIGROS_404_ANALYSIS'), 'requires local 4.0.4 dump')
    def test_native_launch_inputs_match_detached_capture(self):
        from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
        base = Path(os.environ['PHIGROS_404_ANALYSIS'])
        dump = (base/'dump.cs').read_text('utf-8-sig')
        def klass(name):
            return re.search(r'^public class '+name+r' [^\n]*\n\{.*?^}', dump, re.M|re.S)[0]
        def field(body, name):
            return int(re.search(r' '+name+r'; // 0x(\w+)', body)[1], 16)
        def start(body):
            return int(re.search(r'// RVA: 0x(\w+)[^\n]*\n\s*public LevelStartInfo GetLevelStartInfo', body)[1], 16)
        row, song, info = map(klass, ['SongSelectorItem','SongsItem','LevelStartInfo'])
        with (base/'UnityFramework').open('rb') as binary:
            binary.seek(start(row))
            asm = [(op.mnemonic, op.op_str) for op in Cs(CS_ARCH_ARM64, CS_MODE_ARM).disasm(binary.read(0x110), start(row))]
        cursor = 0
        for op in [('ldr', f'x0, [x20, #{field(row,"songInfo"):#x}]'), ('bl', f'#{start(song):#x}'),
                   ('ldr', f'x0, [x20, #{field(row,"extraLevelMods"):#x}]'),
                   ('ldr', f'x22, [x21, #{field(info,"levelMods"):#x}]'),
                   ('ldr', f'x0, [x20, #{field(row,"chartAssetCode"):#x}]'),
                   ('str', f'x0, [x21, #{field(info,"chartAddressableKey"):#x}]')]:
            cursor = asm.index(op, cursor) + 1

    @unittest.skipUnless(os.environ.get('PHIGROS_404_ANALYSIS'), 'requires local 4.0.4 dump')
    def test_dump_and_read_only_record_lookup(self):
        base=Path(os.environ['PHIGROS_404_ANALYSIS']); dump=(base/'dump.cs').read_text('utf-8-sig')
        def klass(name):
            return re.search(r'^public class '+name+r' [^\n]*\n\{.*?^}', dump, re.M|re.S)[0]
        self.assertIn('BuildCoverImageId(string songId, string levelName',dump)
        self.assertIn('BuildBlurImageId(string songId, string levelName',dump)
        row=klass('SongSelectorItem')
        for field in ('SongsItem songInfo;', 'List<LevelRecord> records;', 'PreviewClipPlayer previewClipPlayer;', 'RectTransform coverRect;'):
            self.assertIn(field,row)
        record=klass('LevelRecord')
        for field in ('int s;', 'float a;', 'int c;'): self.assertIn(field,record)
        method=re.search(r'// RVA: 0x(\w+)[^\n]+\n\s*public LevelRecord GetSongRecord\(string songsId, string songsLevel\)',klass('GameInformation'))
        start=int(method[1],16); self.assertEqual(start,0x14a6520)
        with (base/'UnityFramework').open('rb') as binary:
            binary.seek(start); data=binary.read(0x14a66bc-start)
        targets=set()
        for i in range(0,len(data),4):
            word=int.from_bytes(data[i:i+4],'little')
            if word>>26 in (5,37):
                imm=word&0x3ffffff
                targets.add(start+i+4*(imm-(1<<26) if imm&(1<<25) else imm))
        self.assertIn(0x14b16d4,targets)  # SaveManagement.LoadString
        self.assertFalse(targets & {0x14b0410,0x14b04f8,0x14b058c})

if __name__=='__main__': unittest.main()
