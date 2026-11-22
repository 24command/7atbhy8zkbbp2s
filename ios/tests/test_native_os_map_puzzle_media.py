import os
import re
import unittest
from pathlib import Path


@unittest.skipUnless(os.environ.get('PHIGROS_404_ANALYSIS'), 'requires the local 4.0.4 metadata dump')
class NativePuzzleMedia(unittest.TestCase):
    def test_scene_api(self):
        dump = (Path(os.environ['PHIGROS_404_ANALYSIS']) / 'dump.cs').read_text('utf-8-sig')
        contracts = {
            'UnityEngine.Video.VideoPlayer': ('set_url(string ', 'set_renderMode(VideoRenderMode ', 'set_source(VideoSource ',
                'set_audioOutputMode(VideoAudioOutputMode ', 'set_isLooping(bool ', 'get_texture()', 'Play()', 'Stop()'),
            'UnityEngine.Video.VideoRenderMode': ('APIOnly = 4;',),
            'UnityEngine.Video.VideoAudioOutputMode': ('None = 0;',),
            'UnityEngine.Video.VideoSource': ('Url = 1;',),
            'UnityEngine.UI.RawImage': ('set_texture(Texture ',),
            'UnityEngine.UI.Image': ('set_alphaHitTestMinimumThreshold(float ',),
            'UnityEngine.EventSystems.EventTrigger': ('OnBeginDrag(PointerEventData ', 'OnEndDrag(PointerEventData ', 'get_triggers()'),
            'UnityEngine.EventSystems.EventTriggerType': ('BeginDrag = 13;', 'EndDrag = 14;'),
            'UnityEngine.EventSystems.PointerEventData': ('get_pointerPressRaycast()', 'get_pointerCurrentRaycast()',
                'get_pressPosition()', 'get_position()', 'get_pressEventCamera()', 'get_pointerDrag()'),
            'UnityEngine.RectTransformUtility': ('ScreenPointToLocalPointInRectangle(RectTransform rect, Vector2 screenPoint, Camera cam, out Vector2 localPoint)',),
            'System.Collections.Queue': ('Enqueue(object ', 'Dequeue()', '.ctor()', 'get_Count()'),
            'System.Delegate': ('CreateDelegate(Type type, object firstArgument, MethodInfo method)',),
        }
        for name, signatures in contracts.items():
            ns, cls = name.rsplit('.', 1)
            with self.subTest(cls=name):
                match = re.search(r'^// Namespace: ' + re.escape(ns) + r'\n(?:\[[^\n]*\]\n)*public [^\n]*(?:class|enum) '
                                  + cls + r'\b[^\n]*\n\{.*?^\}', dump, re.M | re.S)
                self.assertIsNotNone(match)
                for signature in signatures:
                    self.assertIn(signature, match[0], signature)


if __name__ == '__main__':
    unittest.main()
