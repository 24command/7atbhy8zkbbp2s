"""Focused source contracts; UIKit animation/layout still needs an iPad check."""
from pathlib import Path
import re
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / 'PhiMod/Sources/PMChapterManageUI.mm').read_text(encoding='utf-8')
PICKER = SOURCE.split('// One request per presentation container', 1)[1].split('@implementation PMChapterSongList', 1)[0]


def section(start, end):
    return PICKER.split(start, 1)[1].split(end, 1)[0]


class ChapterPickerPageTests(unittest.TestCase):
    def test_standalone_scrollable_page_not_anchored_action_sheet(self):
        self.assertIn('PMChapterPickerPage : UITableViewController', PICKER)
        self.assertIn('initWithRootViewController:self', PICKER)
        self.assertIn('UIUserInterfaceIdiomPad', PICKER)
        self.assertIn('UIModalPresentationFormSheet : UIModalPresentationFullScreen', PICKER)
        self.assertIn('setNavigationBarHidden:NO', PICKER)
        self.assertIn('UITableViewAutomaticDimension', PICKER)
        self.assertIn('self.tableView.alwaysBounceVertical = YES', PICKER)
        for obsolete in ('alertControllerWithTitle:', 'sourceRect', 'popoverPresentationController', 'addAction:'):
            self.assertNotIn(obsolete, PICKER)

    def test_empty_page_can_cancel_and_long_names_wrap(self):
        self.assertIn('if (!self.chapters.count)', PICKER)
        self.assertIn('self.tableView.backgroundView = empty', PICKER)
        self.assertIn('UIBarButtonSystemItemCancel', PICKER)
        self.assertIn('cell.textLabel.numberOfLines = 0', PICKER)
        self.assertIn('cell.detailTextLabel.numberOfLines = 0', PICKER)
        self.assertIn('adjustsFontForContentSizeCategory = YES', PICKER)
        self.assertIn('return self.chapters.count', PICKER)

    def test_main_queue_handoff_and_single_request_per_container(self):
        entry = section('void PMChooseChapter(', '@implementation PMChapterSongList')
        self.assertLess(entry.index('dispatch_async(dispatch_get_main_queue()'), entry.index('objc_getAssociatedObject'))
        self.assertIn('while (owner.parentViewController)', entry)
        self.assertIn('if (objc_getAssociatedObject(owner, &PMChapterPickerRequestKey)) return', entry)
        self.assertLess(entry.index('objc_setAssociatedObject'), entry.index('[page presentWhenReady]'))
        self.assertNotRegex(PICKER, r'\bbusy\s*=')

    def test_transition_guards_precede_presentation(self):
        present = section('- (void)presentWhenReady {', '@end\n\nvoid PMChooseChapter')
        for controller in ('owner', 'source', 'modal'):
            for flag in ('isBeingPresented', 'isBeingDismissed', 'transitionCoordinator'):
                self.assertLess(present.index(f'{controller}.{flag}'), present.index('[owner presentViewController:'))
        self.assertIn('!source.view.window', present)
        self.assertIn('!owner.view.window', present)
        self.assertIn('self.presentationStarted) return', present)

    def test_operation_sheet_is_dismissed_before_presenting(self):
        present = section('- (void)presentWhenReady {', '@end\n\nvoid PMChooseChapter')
        self.assertIn('source.presentedViewController ?: owner.presentedViewController', present)
        self.assertIn('((UIAlertController *)modal).preferredStyle != UIAlertControllerStyleActionSheet', present)
        dismiss = present.index('[modal dismissViewControllerAnimated:YES completion:^{')
        resume = present.index('[self presentWhenReady]', dismiss)
        show = present.index('[owner presentViewController:')
        self.assertLess(dismiss, resume)
        self.assertLess(resume, show)
        unrelated = present[present.index('if (![modal isKindOfClass:'):dismiss]
        self.assertIn('[self releaseRequest]; return', unrelated)

    def test_transition_retry_uses_completion_and_weak_main_queue_fallback(self):
        retry = section('- (void)retryAfterTransitionOf:', '- (void)presentWhenReady {')
        self.assertIn('if (self.waiting) return', retry)
        self.assertIn('__weak PMChapterPickerPage *weakSelf', retry)
        self.assertIn('animateAlongsideTransition:nil completion:', retry)
        self.assertIn('dispatch_async(dispatch_get_main_queue(), retry)', retry)
        self.assertIn('dispatch_after(', retry)
        self.assertIn('if (!page.waiting) return', retry)

    def test_pending_request_has_deadline_and_abandoned_handoff_cleanup(self):
        self.assertIn('NSProcessInfo.processInfo.systemUptime >= self.deadline', PICKER)
        entry = section('void PMChooseChapter(', '@implementation PMChapterSongList')
        self.assertIn('page.deadline = NSProcessInfo.processInfo.systemUptime + 5.0', entry)
        self.assertIn('__weak PMChapterPickerPage *weakPage', entry)
        self.assertIn('if (!pending.presentationStarted || !pending.navigationController.presentingViewController)', entry)
        self.assertIn('[pending releaseRequest]', entry)

    def test_selection_enabled_only_after_presentation_completion(self):
        present = section('- (void)presentWhenReady {', '@end\n\nvoid PMChooseChapter')
        self.assertLess(present.index('completion:^{', present.index('[owner presentViewController:')), present.index('self.ready = YES'))
        close = section('- (void)finishWithIdentifier:', '- (void)releaseRequest {')
        self.assertIn('!self.ready || self.finishing', close)
        self.assertIn('navigation.isBeingPresented || navigation.isBeingDismissed || navigation.transitionCoordinator', close)
        self.assertLess(close.index('self.finishing = YES'), close.index('[navigation dismissViewControllerAnimated:'))
        self.assertIn('self.tableView.userInteractionEnabled = NO', close)

    def test_choice_occurs_once_after_dismissal_and_gate_release(self):
        close = section('- (void)finishWithIdentifier:', '- (void)releaseRequest {')
        dismiss = close.index('[navigation dismissViewControllerAnimated:YES completion:^{')
        release = close.index('[self releaseRequest]', dismiss)
        callback = close.index('callback(identifier)', release)
        self.assertLess(dismiss, release)
        self.assertLess(release, callback)
        self.assertEqual(PICKER.count('callback(identifier)'), 1)
        self.assertIn('if (visible && identifier.length && callback)', close)
        self.assertIn('source.view.window', close)
        self.assertIn('!owner.isBeingDismissed', close)

    def test_cancel_swipe_and_external_dismissal_release_without_choice(self):
        self.assertIn('- (void)cancel { [self finishWithIdentifier:nil]; }', PICKER)
        cleanup = section('- (void)presentationControllerDidDismiss:', '- (void)retryAfterTransitionOf:')
        self.assertIn('- (void)viewDidDisappear:', cleanup)
        self.assertIn('if (!self.finishing) [self releaseRequest]', cleanup)
        self.assertIn('!self.navigationController.presentingViewController', cleanup)
        self.assertEqual(cleanup.count('[self releaseRequest]'), 2)
        self.assertNotIn('callback(', cleanup)
        self.assertIn('navigation.presentationController.delegate = self', PICKER)

    def test_release_is_idempotent_and_cannot_clear_a_new_request(self):
        cleanup = section('- (void)releaseRequest {', '- (void)presentationControllerDidDismiss:')
        self.assertIn('self.chosen = nil', cleanup)
        self.assertIn('self.waiting = NO', cleanup)
        self.assertIn('objc_getAssociatedObject(owner, &PMChapterPickerRequestKey) == self', cleanup)
        self.assertIn('&PMChapterPickerRequestKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC', cleanup)

    def test_rows_use_cached_data_and_tolerate_missing_local_chapters(self):
        rows = section('static NSArray<NSDictionary *> *PMChapterPickerRows(void)', '@interface PMChapterPickerPage')
        self.assertIn('pmcontent::cachedOfficialSnapshot()', rows)
        self.assertIn('[PMChapterPickerArray(db[@"chapters"]) mutableCopy]', rows)
        self.assertIn('addObjectsFromArray:PMChapterPickerArray(official[@"chapters"])', rows)
        for guard in ('isKindOfClass:NSDictionary.class', 'isKindOfClass:NSArray.class', 'isKindOfClass:NSString.class'):
            self.assertIn(guard, PICKER)
        for call in ('[PMHookBackend', 'commit:', 'assignSongs:', 'pmcontent::apply', 'pmbridge::Runtime'):
            self.assertNotIn(call, PICKER)

    def test_metadata_priority_and_identifier_fallback_are_explicit(self):
        rows = section('static NSArray<NSDictionary *> *PMChapterPickerRows(void)', '@interface PMChapterPickerPage')
        candidates = ['patch[@"title"]', 'chapter[@"name"]', 'chapter[@"title"]', 'info[@"title"]', '?: identifier']
        positions = [rows.index(candidate) for candidate in candidates]
        self.assertEqual(positions, sorted(positions))
        self.assertIn('db[@"chapterOverrides"]', rows)
        self.assertIn('if (!identifier || [seen containsObject:identifier]) continue', rows)
        self.assertIn('[seen addObject:identifier]', rows)
        self.assertIn('@{@"id":identifier, @"title":title}', rows)

    def test_localization_token_pattern_rejects_keys_not_readable_names(self):
        readable = section('static NSString *PMChapterPickerReadableTitle', 'static NSArray<NSDictionary *> *PMChapterPickerRows')
        pattern = re.search(r'NSString \*pattern = @"([^"]+)";', readable).group(1)
        for token in ('Chapter_01_Title', 'chapter.mainstory1.title', 'MainStory8', 'SideStory2.title',
                      'chapterName', 'CHAPTER_TITLE_1', 'IN.Chapter.8.Title', 'loc:chapter_1', 'i18n.chapter.1'):
            with self.subTest(token=token):
                self.assertRegex(token, pattern)
        for title in ('Chapter One', 'Collection', 'Chapterhouse', 'Main Story 8', 'Side Story',
                      '过去的章节', 'Ad Astra', 'Rrhar’il', 'A.B. Collection'):
            with self.subTest(title=title):
                self.assertNotRegex(title, pattern)
        for prefix in ('#', '$', '@', '{', '<'):
            self.assertIn(f'[text hasPrefix:@"{prefix}"]', readable)
        self.assertIn('return text;', readable)


if __name__ == '__main__':
    unittest.main()
