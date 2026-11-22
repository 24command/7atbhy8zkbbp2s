"""Optional shipped-metadata check for the native map's Unity presentation calls."""
import os
from pathlib import Path
import re
import unittest


@unittest.skipUnless(os.environ.get('PHIGROS_404_ANALYSIS'), 'requires local 4.0.4 dump.cs')
class NativeMapMetadata(unittest.TestCase):
    def test_rendering_and_input_contracts(self):
        dump = (Path(os.environ['PHIGROS_404_ANALYSIS']) / 'dump.cs').read_text('utf-8-sig')
        contracts = {
            'UnityEngine.SceneManagement.Scene': ('get_path()',),
            'UnityEngine.GameObject': ('get_scene()', 'AddComponent(Type ', 'GetComponent(Type '),
            'UnityEngine.RectTransform': ('set_offsetMin(Vector2 ', 'set_offsetMax(Vector2 ',
                                          'set_anchorMin(Vector2 ', 'set_anchorMax(Vector2 '),
            'UnityEngine.UI.RectMask2D': ('PerformClipping()',),
            'UnityEngine.UI.AspectRatioFitter': ('set_aspectRatio(float ', 'set_aspectMode(AspectRatioFitter.AspectMode '),
            'UnityEngine.UI.Image': ('set_sprite(Sprite ',),
            'UnityEngine.UI.Text': ('set_font(Font ', 'set_alignment(TextAnchor ', 'set_supportRichText(bool ',
                                    'set_resizeTextMinSize(int ', 'set_resizeTextMaxSize(int ', 'set_text(string '),
            'UnityEngine.CanvasGroup': ('set_alpha(float ', 'set_interactable(bool ', 'set_blocksRaycasts(bool '),
            'UnityEngine.UI.Selectable': ('set_targetGraphic(Graphic ', 'set_transition(Selectable.Transition ', 'IsInteractable()'),
            'UnityEngine.UI.Button': ('Press()',),
        }
        for qualified, methods in contracts.items():
            namespace, name = qualified.rsplit('.', 1)
            with self.subTest(type=qualified):
                cls = re.search(r'^// Namespace: ' + re.escape(namespace) + r'\n(?:\[[^\n]*\]\n)*'
                                r'public [^\n]*(?:class|struct) ' + name + r'\b[^\n]*\n\{.*?^\}',
                                dump, re.M | re.S)
                self.assertIsNotNone(cls)
                for method in methods:
                    self.assertIn(method, cls[0], method)


if __name__ == '__main__':
    unittest.main()
