from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]/'PhiMod/Sources'
class ChapterCrash(unittest.TestCase):
 def test_runtime_uses_mutable_factory(self):
  s=(R/'PMContentRuntime.mm').read_text(encoding='utf8')
  apply=s.split('void applyImpl(',1)[1].split('P image(',1)[0]
  self.assertIn('[chapters addObject:PMNativeChapter(',apply)
  self.assertNotIn('[chapters addObject:@{',apply)
  self.assertIn('addObject:PMMutableContentTree(local)',apply)
  self.assertIn('decltype(variants)nextVariants',apply)
  self.assertIn('variants.swap(nextVariants)',apply)
  self.assertIn('@catch(NSException*e)',apply)
 def test_native_chapter_start_survives_mod_exceptions(self):
  s=(R/'PMHookBackend.mm').read_text(encoding='utf8')
  guard=s.split('bool contentBoundary(',1)[1].split('void onChapterStart',1)[0]
  self.assertIn('@catch(NSException*e)',guard)
  self.assertIn('catch(const std::exception&e)',guard)
  hook=s.split('void onChapterStart(',1)[1].split('P onSongInfo',1)[0]
  self.assertEqual(hook.count('orig<VoidFn>(h::chapterStart)'),1)
  self.assertIn('if(prepared)',hook)
 def test_global_instantiate_requires_live_note_scope(self):
  s=(R/'PMHookBackend.mm').read_text(encoding='utf8')
  hook=s.split('P onSkinInstantiate(',1)[1].split('template<h::Index I>',1)[0]
  self.assertIn('[NSThread isMainThread]&&diagnosticJudgeControl',hook)
  self.assertEqual(hook.count('orig<P(*)(P,P)>'),1)
if __name__=='__main__':unittest.main()
