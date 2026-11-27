"""Adapter contracts for the portable first-frame behavioral tests.

Run PMNativeOSMapReadinessTest.cpp with any C++17 compiler; no Lua link needed.
This suite also checks VideoPlayer signatures when a local metadata dump exists.
"""
import os
from pathlib import Path
import re
import unittest

SOURCES = Path(__file__).resolve().parents[1] / 'PhiMod' / 'Sources'
MAP = (SOURCES / 'PMNativeOSMap.mm').read_text(encoding='utf-8')
MEDIA = (SOURCES / 'PMNativeOSMapMedia.inc').read_text(encoding='utf-8')


def between(text, start, end):
    return text.split(start, 1)[1].split(end, 1)[0]


class MapReadinessAdapter(unittest.TestCase):
    def test_poll_is_clock_and_input_free(self):
        poll = between(MAP, 'ReadinessResult pollPrepared(', 'bool present(')
        self.assertIn('preparation.owns(token,current->page)', poll)
        self.assertIn('refresh(m,0)', poll)
        for forbidden in ('puzzleInput(', 'dispatchNode(', 'm.time()', 'm.running =', 'm.elapsed ='):
            self.assertNotIn(forbidden, poll)

    def test_prepare_is_hidden_active_and_inert(self):
        prepare = between(MAP, 'bool prepare(', 'ReadinessResult pollPrepared(')
        self.assertIn('current->elapsed != 0', prepare)
        self.assertIn('current->visible || current->running', prepare)
        self.assertIn('m.input = false', prepare)
        self.assertIn('"set_interactable",false', prepare)
        self.assertIn('"set_blocksRaycasts",false', prepare)
        self.assertLess(prepare.index('"set_alpha"'), prepare.index('"SetActive",true'))
        refresh = between(MAP, 'void refresh(', 'bool matches(')
        self.assertIn('readiness::mediaMode(active,m.preparation.active(),m.visible,m.running)', refresh)
        self.assertIn('m.preparation.expired(wallTime())', refresh)

    def test_video_requires_decoded_frame_then_pauses(self):
        warm = between(MEDIA, 'void warmMedia(', 'void syncMedia(')
        self.assertIn('"Prepare"', warm)
        self.assertIn('"get_isPrepared"', warm)
        self.assertIn('get_frame', warm)
        self.assertIn('w < 1 || h < 1', warm)
        self.assertLess(warm.index('"get_frame"'), warm.index('attachMedia('))
        self.assertLess(warm.index('attachMedia('), warm.index('"Pause"'))
        self.assertNotIn('"Stop"', warm)

    def test_reveal_resumes_without_restarting(self):
        resume = between(MEDIA, 'if (media.first.release())', 'if (!media.playing)')
        self.assertIn('"Play"', resume)
        self.assertIn('g.due = t + g.delay', resume)
        for forbidden in ('"Stop"', '"Prepare"', 'make_shared<GifVisit>'):
            self.assertNotIn(forbidden, resume)
        present = between(MAP, 'bool present(', '// May run Lua')
        self.assertIn('running && m.preparation.active()', present)
        self.assertIn('m.preparation.invalidate()', present)
        self.assertIn('visible || m.preparation.active()', present)
        self.assertNotIn('stopMedia(', present)

    def test_cover_timeout_does_not_permanently_disable_slow_media(self):
        defer = between(MEDIA, 'void deferMedia(', 'void warmMedia(')
        for forbidden in ('media.failed = true', 'first.reset()', '"Stop"', 'gif.reset()'):
            self.assertNotIn(forbidden, defer)
        warm = between(MEDIA, 'void warmMedia(', 'void syncMedia(')
        self.assertIn('if (expired) { deferMedia(', warm)
        sync = MEDIA.split('void syncMedia(', 1)[1]
        self.assertLess(sync.index('warmMedia(m,media,false)'), sync.index('media.first.release()'))
        self.assertIn('if(media.failed || !media.first.held())return;', sync)
        self.assertIn('readiness::result(total,ready,failed,deferred)', MAP)

    def test_page_cancel_and_normal_hide_stop_staged_players(self):
        page = between(MAP, 'bool displayPage(', 'bool setElement(')
        self.assertIn('m.preparation.invalidate()', page)
        self.assertIn('stopMedia(m, *item.media)', page)
        stop = between(MEDIA, 'void stopMedia(', 'void failMedia(')
        self.assertIn('media.first.started()', stop)
        self.assertIn('media.gif.reset()', stop)
        self.assertIn('media.first.reset()', stop)
        self.assertIn('"Stop"', stop)
        sync = MEDIA.split('void syncMedia(', 1)[1]
        self.assertIn('if (!play) { stopMedia(m,media); return; }', sync)

    def test_fallback_is_logged_and_preserves_authored_still(self):
        fallback = between(MEDIA, 'void failMedia(', 'void attachMedia(')
        self.assertIn('PMDiagnosticsWrite', fallback)
        self.assertIn('media.path, reason', fallback)
        self.assertIn('media.received ? "Pause" : "Stop"', fallback)
        self.assertIn('if (!media.received)', fallback)
        self.assertNotIn('destroy(', fallback)
        self.assertNotIn('close(', fallback)
        warm = between(MEDIA, 'void warmMedia(', 'void syncMedia(')
        self.assertIn('if (expired) { deferMedia(', warm)
        self.assertNotIn('poll(false,false,expired)', warm)
        self.assertIn('first-frame deadline (3s)', warm)

    def test_gif_does_not_prefetch_or_advance_while_held(self):
        warm = between(MEDIA, 'void warmMedia(', 'void syncMedia(')
        self.assertIn('media.first.held()) return', warm)
        self.assertEqual(warm.count('requestGif(media)'), 1)
        self.assertIn('g.due = g.delay', warm)
        self.assertIn('std::weak_ptr<GifVisit>', MEDIA)
        self.assertIn('if (auto owner = visit.lock())', MEDIA)

    def test_reserved_timeline_resources_are_not_acquired(self):
        preflight = between(MAP, 'std::vector<int> preflight(', 'void validateParent(')
        self.assertLess(preflight.index('layout::reserved(page,n.screen)'), preflight.index('models[i]'))
        self.assertIn('layout::suppressed(page,n)', preflight) # Silhouette budget pass.
        build = between(MAP, 'void build(', 'void refresh(')
        self.assertIn('m.page = page.initialScreen', build)
        self.assertIn('m.transitionScreen = layout::reservedScreen(page)', build)
        self.assertLess(build.index('layout::suppressed(page,page.elements[i])'), build.index('models[i]'))
        self.assertIn('if (layout::suppressed(page,n))', build)
        # Item owns numeric/drag state; moving it must still reserve suppressed indices.
        self.assertIn('m.items.push_back(std::move(item)); // Reserve the index', build)
        page = between(MAP, 'bool displayPage(', 'bool setElement(')
        self.assertIn('layout::canDisplay(current->screens,current->transitionScreen,screen)', page)

    @unittest.skipUnless(os.environ.get('PHIGROS_404_ANALYSIS'), 'requires local 4.0.4 dump.cs')
    def test_video_metadata(self):
        dump = (Path(os.environ['PHIGROS_404_ANALYSIS']) / 'dump.cs').read_text('utf-8-sig')
        cls = re.search(r'^// Namespace: UnityEngine.Video\n(?:\[[^\n]*\]\n)*public [^\n]*class VideoPlayer\b[^\n]*\n\{.*?^\}', dump, re.M | re.S)
        self.assertIsNotNone(cls)
        for signature in ('Prepare()', 'get_isPrepared()', 'long get_frame()', 'Pause()', 'Play()', 'Stop()'):
            self.assertIn(signature, cls[0])


if __name__ == '__main__':
    unittest.main()
