import unittest
from pathlib import Path
class BackgroundFill(unittest.TestCase):
 def test_browsing_and_course_cells_use_sharp_bounded_art(self):
  sources=Path(__file__).resolve().parents[1]/'PhiMod/Sources'
  runtime=(sources/'PMContentRuntime.mm').read_text('utf8')
  observer=runtime.split('void observeSelector(',1)[1].split('struct VariantCoverState',1)[0]
  self.assertIn('selectorThumbnailKey(id)',observer)
  self.assertNotIn('coverBlurAssetCode',observer)
  self.assertIn('if(thumbnail)maxSide=384;',runtime)
  self.assertIn('image(r,path,false,false,{.5f,.5f},false,true)',runtime)
  for source in ('PMChallengeSelection.inc','PMDifficultyPager.inc'):
   self.assertIn('selectorThumbnailKey(chart[@"id"])',(sources/source).read_text('utf8'))
 def test_quick_start_uses_gameplay_assets_not_pending_preview(self):
  sources=Path(__file__).resolve().parents[1]/'PhiMod/Sources'
  runtime=(sources/'PMContentRuntime.mm').read_text('utf8')
  bind=runtime.split('void levelInfo(',1)[1].split('void ensureVisualChart(',1)[0]
  self.assertIn('{"musicAddressableKey","playMusic"}',bind)
  self.assertIn('{"illustrationKey","courseImage"}',bind)
  deferred=runtime.split('bool assetConstructor(',1)[1].split('try{std::string cacheKey',1)[0]
  for key in ('thumb','playMusic','courseImage'):self.assertNotIn('@"'+key+'"',deferred)
  lookup=runtime.split('NSString*gameplayChartID(',1)[1].split('\n}',1)[0]
  self.assertLess(lookup.index('chartAddressableKey'),lookup.index('songsId'))
  self.assertIn('ensureVisualChart(r);',runtime.split('void beforeInformation(',1)[1])
  self.assertEqual((sources/'PMRuntimeFeatures.mm').read_text('utf8').count('pmcontent::gameplayChartID(r)'),2)
 def test_cover_dimensions_preserve_aspect(self):
  for w,h in ((1920,1080),(1280,720),(512,512),(1080,1920),(2048,512),(4096,2304)):
   ppu=min(w/38.4,h/21.6)
   self.assertGreaterEqual(w/ppu+1e-6,38.4)
   self.assertGreaterEqual(h/ppu+1e-6,21.6)
   self.assertAlmostEqual((w/ppu)/(h/ppu),w/h)
 def test_background_only_routing(self):
  s=(Path(__file__).resolve().parents[1]/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  self.assertIn('bool background=false',s)
  self.assertIn('background?std::min(actualW/38.4f,actualH/21.6f):lineTexture?100.f*actualW/sourceW:100.f',s)
  self.assertIn('[lower containsString:@"blur"]?@"blur"',s)
  self.assertIn('bool blurred=[kind isEqualToString:@"chapterBlur"]||[kind isEqualToString:@"blur"]||[kind isEqualToString:@"courseBlur"]',s)
  self.assertIn('obj=image(r,path,blurred,false,{.5f,.5f},blurred)',s)
  self.assertIn('sprite=image(r,path,false,true,anchor);',s)
 def test_course_cold_art_is_ready_for_the_native_loader(self):
  sources=Path(__file__).resolve().parents[1]/'PhiMod/Sources'
  hook=(sources/'PMHookBackend.mm').read_text('utf8').split('bool onChallengeAdvance(',1)[1].split('void onChallengeResultStart',1)[0]
  self.assertLess(hook.index('pmchallenge::advance(r)'),hook.index('prepareChallengeArtwork(r)'))
  self.assertLess(hook.index('prepareChallengeArtwork(r)'),hook.index('orig<JudgeFn>(h::challengeAdvance)'))
  bind=(sources/'PMDifficultyPager.inc').read_text('utf8').split('void prepareChallengeArtwork(',1)[1].split('void difficultyTransitionLabel(',1)[0]
  for value in ('challengeEntryChart(r,entry)','/courseImage@','/courseBlur@','"BuildBlurImageId"','r.put(copy,"coverAssetCode"','r.put(copy,"coverBlurAssetCode"'):
   self.assertIn(value,bind)
  aset=(sources/'PMContentRuntime.mm').read_text('utf8').split('bool assetConstructor(',1)[1].split('try{std::string cacheKey',1)[0]
  self.assertIn('selectorAssets[self]',aset)
  self.assertNotIn('courseImage',aset)
  self.assertNotIn('courseBlur',aset)
 def test_chapter_blur_uses_the_card_mask_and_active_background(self):
  s=(Path(__file__).resolve().parents[1]/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  assign=s.split('void applyCachedChapterCover(',1)[1].split('void syncChapterCoverFallbacks',1)[0]
  self.assertLess(assign.index('fitChapterCardCover(r,loader)'),assign.index('if(!strcmp(loaderField,"cover"))'))
  ready=s.split('void chapterReady(',1)[1].split('void*loadSkinAudio',1)[0]
  for text in ('/chapterBlur@','"_nowChapterIndex"','"_nowBackgroundIndex"','r.arrayAt(backgrounds,active)','r.get<P>(card,"coverBlurAssetCode")','r.call(loader,"set_Code"'):
   self.assertIn(text,ready)
if __name__=='__main__':unittest.main()
