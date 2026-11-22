"""Source/metadata contracts for rows crossing a Single scene load, not a device test."""
import os
import re
import unittest
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / 'PhiMod/Sources'
ROWS = (SRC / 'PMNativeOSRows.inc').read_text('utf-8-sig')
CONTENT = (SRC / 'PMContentRuntime.mm').read_text('utf-8-sig')


class NativeOSRows(unittest.TestCase):
    def test_checks_and_all_or_nothing_publication(self):
        checked = CONTENT.split('static BOOL checkedSong(Runtime &r', 1)[1].split('if(collect){', 1)
        self.assertIn('![chapterIDs containsObject:installedID]', checked[0])
        self.assertIn('if(sibling)return NO', checked[0])
        self.assertIn('checkpointOfficialOpen(r,song,official,slot)', checked[0])
        self.assertLess(checked[1].index('courseMemberOpen'), checked[1].index('return collect('))
        self.assertLess(checked[1].index('return collect('), checked[1].index('r.put(selector,"nowSong"'))
        build = ROWS.split('bool prepare(', 1)[1].split('bool lookup(', 1)[0]
        self.assertLess(build.index('release();'), build.index('checkedSong('))
        self.assertLess(build.index('revision!=PMContentStore.shared.revision'), build.index('batch=std::move(next)'))

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
        self.assertIn('if(!art)return {};',snap)
        lookup = ROWS.split('bool lookup(', 1)[1]
        for forbidden in ('selector','checkedSong','GetSongRecord','coverPath','PMContentStore.shared'):
            self.assertNotIn(forbidden,lookup)

    @unittest.skipUnless(os.environ.get('PHIGROS_404_ANALYSIS'), 'requires local 4.0.4 dump')
    def test_dump_and_read_only_record_lookup(self):
        base=Path(os.environ['PHIGROS_404_ANALYSIS']); dump=(base/'dump.cs').read_text('utf-8-sig')
        def klass(name):
            return re.search(r'^public class '+name+r' [^\n]*\n\{.*?^}', dump, re.M|re.S)[0]
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
