from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class ContentMemoryContracts(unittest.TestCase):
 def test_chapter_conversion_drains_per_song_and_retains_failure(self):
  s=(ROOT/'PhiMod/Sources/PMContentStore.mm').read_text('utf8')
  block=s.split('for(NSDictionary*sourceSong in sourceSongs){NSError*songFailure=nil;',1)[1].split('NSMutableArray*mappedChapters=',1)[0]
  self.assertIn('@autoreleasepool{songOK=[&]() -> BOOL',block)
  self.assertIn('PMConvertChart',block)
  self.assertIn('PMNormalizeCoverFolder',block)
  self.assertIn('compactImportedSong',block)
  self.assertIn('if(!songOK){if(error)*error=songFailure',block)
  self.assertNotIn('error:error',block)
  self.assertNotIn('clone([self snapshot])',s)
  self.assertIn('@synchronized(self){published=self.db;}return clone(published)',s)
 def test_export_and_source_io_avoid_full_data_copies(self):
  s=(ROOT/'PhiMod/Sources/PMContentStore.mm').read_text('utf8')
  self.assertIn('PMWriteJSONFile(x,p,0,e)',s)
  self.assertIn('PMReadJSONFile([stage stringByAppendingPathComponent:@"chart.json"]',s)
  self.assertIn('PMCopySourceFile(sourceOriginal',s)
  self.assertNotIn('dataWithContentsOfFile:sourceOriginal',s)
  compact=(ROOT/'PhiMod/Sources/PMImportCompaction.inc').read_text('utf8')
  self.assertIn('PMFilesEqual(musicCandidate',compact)
  self.assertIn('@autoreleasepool{id x=PMReadJSONFile',compact)
 def test_list_refresh_decodes_bounded_thumbnails_off_main(self):
  ui=(ROOT/'PhiMod/Sources/PMContentUI.mm').read_text('utf8')
  cells=ui.split('cellForRowAtIndexPath:',1)[1].split('- (void)toggleBulkSelection',1)[0]
  self.assertNotIn('imageWithContentsOfFile',cells)
  self.assertIn('loadCover:folder cell:c',cells)
  self.assertIn('kCGImageSourceThumbnailMaxPixelSize:@384',ui)
  self.assertIn('coverWorker.maxConcurrentOperationCount=1',ui)
  self.assertIn('owner.coverRevision!=revision',ui)
  self.assertIn('visible.coverKey isEqualToString:key',ui)
  self.assertIn('self.coverCache.totalCostLimit=12*1024*1024',ui)
  self.assertIn('if(!owner||!owner.busy)',ui)
if __name__=='__main__':unittest.main()
