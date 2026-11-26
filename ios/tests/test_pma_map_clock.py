"""PMA map wall-clock regression tests. GIF scheduling remains unchanged."""
from pathlib import Path
import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
MEDIA=(ROOT/'PhiMod/Sources/PMNativeOSMapMedia.inc').read_text(encoding='utf-8')
REGIONS={'decode': ('            if (!decoder->source) {', '        });\n        size_t count = decoder->count;'), 'live': ('            if (g.failed) { failMedia(m,media,@"GIF frame decode failed"); return; }', '\n        }\n        attachMedia(m,media,texture,aspect);')}
HASHES={'decode': '12cd53c1f11bd851ec693e07908d0d7159044944ae69c97fb55f04f05a619d13', 'live': 'dccce1de8867ad0738e18c96b0aef0497461b97ec769c51e8f1361e526b35238'}
def between(text,a,b):return text.split(a,1)[1].split(b,1)[0]
class PMAMapClock(unittest.TestCase):
    def test_gif_decode_and_clock_unchanged(self):
        for key,(start,end) in REGIONS.items():
            with self.subTest(section=key):
                self.assertEqual(hashlib.sha256(between(MEDIA,start,end).encode()).hexdigest(),HASHES[key])
    def test_preflight_and_reveal(self):
        warm=between(MEDIA,'void warmMedia(','void syncMedia(')
        self.assertEqual(warm.count('requestGif(media)'),1)
        self.assertIn('if (![media.path.pathExtension.lowercaseString isEqualToString:@"pma"])',warm)
        self.assertIn('g.sequenceClock.start(t,true)',MEDIA)
        self.assertIn('media.gif->sequenceClock.start(t,false)',MEDIA)
    def test_stale_completion_and_ready_frame(self):
        callback=between(MEDIA,'if (auto owner = visit.lock())','std::shared_ptr<Media> buildMedia')
        self.assertLess(callback.index('owner->pending = false'),callback.index('!owner->sequenceClock.accepts(ticket)'))
        self.assertIn('owner->frame != frame || owner->decoder != decoder',callback)
        self.assertIn('g.readySlot.before(wanted)',MEDIA)
        self.assertIn('if (g.ready && g.readySlot==wanted)',MEDIA)
        self.assertIn('g.sequenceClock.sample(t,g.count,g.delay,media.loop)',MEDIA)
        self.assertIn('if (!g.pending && !g.ready && !g.failed)',MEDIA)
        self.assertIn('g.sequenceClock.next(g.count,media.loop)',MEDIA)
        self.assertLess(MEDIA.index('g.sequenceClock.displayed(wanted)'),MEDIA.index('g.finished=!media.loop'))
    def test_actual_clock(self):
        compiler=os.environ.get('CXX') or shutil.which('clang++') or shutil.which('g++') or shutil.which('cl')
        if not compiler:self.skipTest('C++ compiler unavailable')
        with tempfile.TemporaryDirectory(prefix='pma-map-clock-') as folder:
            out=Path(folder)/('clock.exe' if os.name=='nt' else 'clock')
            source=ROOT/'tests/PMNativeOSMapSequenceClockTest.cpp'
            if Path(compiler).name.lower() in ('cl','cl.exe'):
                cmd=[compiler,'/nologo','/EHsc','/std:c++17','/W4','/WX',f'/Fe:{out}',f'/Fo:{Path(folder)/"clock.obj"}',str(source)]
            else:cmd=[compiler,'-std=c++17','-Wall','-Wextra','-Werror',str(source),'-o',str(out)]
            result=subprocess.run(cmd,cwd=folder,capture_output=True,text=True,errors='replace',timeout=60)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            result=subprocess.run([str(out)],capture_output=True,text=True,timeout=15)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn('PMA map clock: 7 groups passed',result.stdout)
if __name__=='__main__':unittest.main()
