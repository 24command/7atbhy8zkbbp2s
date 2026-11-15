"""Source regressions for the copy-import picker handoff (no UIKit on host)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
UI = (ROOT / "PhiMod/Sources/PMContentUI.mm").read_text(encoding="utf-8")
STORE = (ROOT / "PhiMod/Sources/PMContentStore.mm").read_text(encoding="utf-8")
ARCHIVE = (ROOT / "PhiMod/Sources/PMArchive.mm").read_text(encoding="utf-8")


def method(source, signature):
    start = source.index(signature)
    end = source.find("\n- (", start + len(signature))
    return source[start:end if end >= 0 else len(source)]


class ImportPickerLifecycleTests(unittest.TestCase):
    def test_copy_selection_survives_dismissal(self):
        body = method(UI, "- (void)importFiles {")
        self.assertIn("asCopy:YES", body)
        self.assertNotIn("asCopy:NO", body)
        self.assertIn("p.allowsMultipleSelection=YES", body)
        self.assertIn("self.importPicker=p", body)
        self.assertIn("self.busy||self.importPicker", body)

    def test_selection_is_consumed_before_single_worker_enqueue(self):
        delegate = method(UI, "- (void)documentPicker:")
        self.assertIn("if(picker==self.importPicker)", delegate)
        self.assertEqual(delegate.count("[self importSelectedURLs:urls picker:picker]"), 1)
        self.assertIn("if(self.busy||!urls.count||!self.imageID)return", delegate)
        body = method(UI, "- (void)importSelectedURLs:")
        enqueue = body.index("dispatch_async(self.worker,^{")
        self.assertEqual(body.count("dispatch_async(self.worker,^{"), 1)
        self.assertLess(body.index("self.importPicker=nil;picker.delegate=nil"), enqueue)
        self.assertLess(body.index("self.busy=YES"), enqueue)
        self.assertIn("NSArray<NSURL*>*selected=[urls copy]", body)
        self.assertIn("NSString*chapter=[self.selectedChapter copy]", body)

    def test_import_never_waits_for_dismissal_completion(self):
        body = method(UI, "- (void)importSelectedURLs:")
        self.assertIn("completion:^{[self showPendingImportMessage];}", body)
        self.assertNotIn("completion:start", body)
        self.assertNotIn("void (^start)", body)
        self.assertIn("if(picker.presentingViewController&&!picker.isBeingDismissed)", body)
        self.assertLess(body.index("dismissViewControllerAnimated"), body.index("dispatch_async(self.worker"))

    def test_provider_reads_and_scopes_stay_on_serial_worker(self):
        body = method(UI, "- (void)importSelectedURLs:")
        before_worker = body[:body.index("dispatch_async(self.worker,^{")]
        for forbidden in ("PMScopedFileAccess", "startAccessingSecurityScopedResource", "importURL:", "NSFileCoordinator", "dataWithContentsOf"):
            self.assertNotIn(forbidden, before_worker)
        self.assertNotIn("PMScopedFileAccess", UI)
        self.assertIn("DISPATCH_QUEUE_SERIAL", UI)
        self.assertIn("for(NSURL*url in selected){@autoreleasepool{", body)
        self.assertIn("@try{ok=[PMContentStore.shared importURL:url chapter:chapter error:&e];}", body)
        self.assertIn("NSFileCoordinator", ARCHIVE)
        self.assertIn("coordinateReadingItemAtURL:url", ARCHIVE)

    def test_per_file_cleanup_remains_in_importer_finally(self):
        body = method(STORE, "- (BOOL)importURL:")
        cleanup = body[body.rindex("@finally{"):]
        self.assertIn("if(access)[url stopAccessingSecurityScopedResource]", cleanup)
        self.assertIn("[f removeItemAtPath:stage error:nil]", cleanup)
        self.assertIn("if(!ok)for(NSString*p in moved)", cleanup)

    def test_batch_continues_after_errors_and_bounds_retained_details(self):
        body = method(UI, "- (void)importSelectedURLs:")
        self.assertIn("@catch(NSException*exception)", body)
        self.assertIn("if(ok)done++;else{", body)
        self.assertIn("++failed", body)
        self.assertIn("if(errors.count<20)", body)
        self.assertIn("detail.length>512", body)
        self.assertIn("substringToIndex:512", body)
        self.assertIn("failed-errors.count", body)
        loop = body[body.index("for(NSURL*url in selected)"):body.index("if(failed>errors.count)")]
        self.assertNotIn("return;", loop)
        self.assertNotIn("break;", loop)
        self.assertIn("self.busy=NO;[self reload];self.pendingImportMessage=summary", body)

    def test_empty_selection_and_cancel_clear_picker_without_starting_batch(self):
        body = method(UI, "- (void)importSelectedURLs:")
        self.assertIn("else self.pendingImportMessage=", body)
        self.assertLess(body.index("if(!selected.count)return"), body.index("dispatch_async(self.worker"))
        cancel = method(UI, "- (void)documentPickerWasCancelled:")
        self.assertIn("self.importPicker=nil;picker.delegate=nil", cancel)
        self.assertIn("self.imageID=nil;self.imageIsChapter=NO", cancel)
        self.assertIn("cleanupExports:self.pendingExports", cancel)
        self.assertNotIn("dispatch_async(self.worker", cancel)

    def test_result_waits_for_visible_manager_and_has_multiple_delivery_paths(self):
        body = method(UI, "- (void)showPendingImportMessage {")
        for check in ("!self.pendingImportMessage", "!self.view.window", "self.presentedViewController", "self.isBeingDismissed", "self.transitionCoordinator"):
            self.assertIn(check, body)
        self.assertIn("dispatch_after", body)
        self.assertIn("__weak PMContentController*weakSelf=self", body)
        self.assertIn("self.pendingImportMessage=nil;[self message:message]", body)
        self.assertIn("[self showPendingImportMessage]", method(UI, "- (void)viewDidAppear:"))
        body = method(UI, "- (void)importSelectedURLs:")
        self.assertIn("self.pendingImportMessage=summary;[self showPendingImportMessage]", body)

    def test_image_and_export_paths_keep_their_existing_behavior(self):
        delegate = method(UI, "- (void)documentPicker:")
        image = delegate[delegate.index("void (^start)(void)"):]
        for required in ("UIImage imageWithContentsOfFile:url.path", "startAccessingSecurityScopedResource", "stopAccessingSecurityScopedResource", "imageIsChapter?1.35625:(16.0/9.0)", "crop.allowsCompleteCover=YES", "completion:start", "UIImagePNGRepresentation(result)"):
            self.assertIn(required, image)
        self.assertIn("cleanupExports:self.pendingExports", delegate)
        export = method(UI, "- (void)export:")
        self.assertIn("initForExportingURLs:@[url] asCopy:YES", export)
        self.assertIn("self.pendingExports=@[url]", export)


if __name__ == "__main__":
    unittest.main()
