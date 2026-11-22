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
