"""Actual additive managed adapter plus native Map lifecycle wiring contracts."""
from pathlib import Path
import json
import os
import tempfile
import unittest
from test_native_os_transition_support import compile_cpp, run_cpp
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'PhiMod' / 'Sources'

def body(text, marker, end):
    return text.split(marker, 1)[1].split(end, 1)[0]

class MapBlend(unittest.TestCase):
    def test_numerical_and_actual_adapter(self):
        fixture = Path(__file__).with_name('PMNativeOSMapBlendTest.cpp')
        with tempfile.TemporaryDirectory(prefix='pm-additive-') as directory:
            executable = compile_cpp('#include "' + fixture.as_posix() + '"\n', directory, 'blend')
            run_cpp(self, executable)

    def test_actual_map_root_and_material_wiring(self):
        native = (SRC/'PMNativeOSMap.mm').read_text(encoding='utf-8-sig')
        media = (SRC/'PMNativeOSMapMedia.inc').read_text(encoding='utf-8-sig')
        helper = (SRC/'PMNativeOSMapBlend.inc').read_text(encoding='utf-8-sig')
        self.assertIn('float rootOpacity=0;', native)
        prepare = body(native, 'bool prepare(Runtime', 'ReadinessResult pollPrepared')
        self.assertIn('m.rootOpacity = 0', prepare)
        self.assertLess(prepare.index('hideAdditive(m)'), prepare.index('"SetActive",true'))
        self.assertLess(prepare.index('"set_alpha"'), prepare.index('hideAdditive(m)'))
        present = body(native, 'bool present(Runtime', '// May run Lua')
        self.assertIn('setRootOpacity(m,visible ? 1.f : 0.f)', present)
        self.assertLess(present.index('m.input = acceptInput'),present.index('setRootOpacity'))
        switch = body(native,'bool displayPage(Runtime','bool setElement(Runtime')
        self.assertLess(switch.index('hideAdditive(m)'),switch.index('m.page = screen'))
        self.assertIn('refresh(*current, current->time())',native)
        refresh = body(native,'void refresh(Map &m','bool matches(Runtime')
        self.assertIn('if (!active) { syncAdditive(m,item); continue; }',refresh)
        self.assertLess(refresh.index('item.inheritedAlpha = inherited'),refresh.rindex('syncAdditive(m,item)'))
        dispose = body(native,'void dispose(Map &m','void stretch(Runtime')
        self.assertIn('hideAdditive(m)',dispose)
        self.assertIn('m.assets.rbegin()',dispose)
        self.assertIn('destroy(m, *i)',dispose)
        self.assertIn('for (Handle h : m.handles) if (h) m.r.gchandle_free(h)',dispose)
        self.assertIn('m.assets.push_back(owned)',helper)
        self.assertNotIn('Shader", "Find',helper)
        for bad in ('_SrcBlend','_DstBlend','UI/Default','SetFloat','SetInt'):
            self.assertNotIn(bad,helper)
        self.assertIn('r.object_get_class(shader)!=shaderType',helper)
        self.assertIn('"get_isSupported"',helper)
        self.assertIn('Handle shaderHandle=m.keep(shader)',helper)
        self.assertIn('m.r.call(m.get(graphic),"set_material"',helper)
        self.assertIn('if (n.blend == PMOSBlendAdd) additiveMaterial(m);',native)
        self.assertIn('bindAdditive(m,item.additive,picture.go',native)
        self.assertIn('if (additive) bindAdditive(m,*additive,childObject.go,media->raw);',media)
        self.assertIn('n.blend == PMOSBlendAdd ? &item.additive : nullptr',native)
        self.assertIn('blend::graphicColor(item.additive,rendering::color(value),item.tint!=0)',native)
        self.assertIn('bool spriteTint = n.kind == PMOSImage && rendering::rgbTracks(n);',native)
        self.assertIn('set_alphaHitTestMinimumThreshold',native)
        # Existing node/pixel budgets and mask hierarchy remain unchanged.
        self.assertIn('page.nodes > PMOSMaxNodes',native)
        self.assertIn('residency::dimensionLimit(surfaces)',native)
        self.assertIn('add(r, go, "UnityEngine.UI", "RectMask2D")',native)


    def test_verified_retail_shader_evidence_when_available(self):
        evidence = Path(os.getenv('PM_SHADER_EVIDENCE', 'G:/PhiMod-package30/kld-audit/raw-mono'))
        if not (evidence/'phigros-shader-capabilities.json').is_file():
            self.skipTest('requires supplied retail shader evidence')
        cap = json.loads((evidence/'phigros-shader-capabilities.json').read_text(encoding='utf-8-sig'))
        shader = next(row for row in cap if row['pathID'] == 139)
        self.assertEqual(shader['name'], 'UI/TrueShadow-Additive')
        self.assertFalse(shader['dynamicBlendBinding'])
        blend = shader['passes'][0]['rtBlend0']
        self.assertEqual(blend['srcBlend']['val'], 5)  # SrcAlpha, not One.
        self.assertEqual(blend['destBlend']['val'], 1) # One, not OneMinusSrcAlpha.
        resources = json.loads((evidence/'phigros-shader-resource-keys.json').read_text(encoding='utf-8-sig'))
        entry = next(row for row in resources if row['key'] == 'shaders/trueshadow-additive')
        self.assertEqual(entry['reference']['m_PathID'], 139)
        self.assertEqual(entry['targetFile'], 'resources.assets')
        metal = (evidence/'phigros-shader-139-metal.txt').read_text(encoding='utf-8-sig')
        self.assertIn('output.COLOR0.xyz = half3(input.COLOR0.www * input.COLOR0.xyz)', metal)
        self.assertIn('_MainTex.sample(sampler_MainTex', metal)
        self.assertIn('u_xlat0 = u_xlat0 * float4(input.COLOR0)', metal)

if __name__=='__main__':unittest.main()
