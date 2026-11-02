from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]/'PhiMod/Sources'
class AvatarCropNavigation(unittest.TestCase):
 def test_crop_is_presented_with_visible_navigation_bar(self):
  s=(R/'PMAvatarUI.mm').read_text(encoding='utf-8')
  self.assertIn('initWithRootViewController:crop',s)
  self.assertIn('setNavigationBarHidden:NO',s)
  self.assertIn('presentViewController:navigation',s)
  self.assertNotIn('presentViewController:crop',s)
  self.assertIn('UIModalPresentationFullScreen',s)
 def test_existing_actions_and_dismiss_completion_preserved(self):
  s=(R/'PMImageCropController.mm').read_text(encoding='utf-8')
  for action in ('@selector(save)','@selector(cancel)','@selector(rotate)'):self.assertIn(action,s)
  self.assertIn('dismissViewControllerAnimated:YES completion:',s)
if __name__=='__main__':unittest.main()
