"""4.0.4 contracts: raw ARM64 calls and the initializer backing the LIFE ladder."""
import hashlib
import os
from pathlib import Path
import re
import struct
import unittest

SRC = Path(__file__).resolve().parents[1] / 'PhiMod/Sources'

class SecretCourse(unittest.TestCase):
    def test_only_one_natural_outcome_writer(self):
        code = (SRC/'PMSecretCourseRuntime.mm').read_text('utf8')
        result = code.split('void result(Runtime &r){')[1].split('void menu(')[0]
        self.assertEqual(code.count('PMDoorRecordCourseOutcome('), 2)
        self.assertEqual(result.count('PMDoorRecordCourseOutcome(chapterID,doorID,launchedTier,'), 2)
        for condition in ('if(reported)return;reported=true;', 'secretChallengeLifeFailed', '!finishedLeg', 'entered!=count-1'):
            self.assertIn(condition, result)
        self.assertIn('launchedTier=index', code)
        for method in ('GetSavedTierIndex','GetSelectedTierIndex','SetSelectedTierIndex','BeginRun','RestartRun'):
            self.assertNotIn('"'+method+'"', code)

    @unittest.skipUnless(os.environ.get('PHIGROS_404_ANALYSIS'), 'requires the local iOS 4.0.4 dump')
    def test_stock_writers_and_tier_data(self):
        root = Path(os.environ['PHIGROS_404_ANALYSIS'])
        blob = (root/'UnityFramework').read_bytes()
        def calls(begin,end):
            targets=set()
            for pc in range(begin,end,4):
                word,=struct.unpack_from('<I',blob,pc)
                if word>>26 not in (5,37): continue  # B, BL
                imm=word & 0x3ffffff
                if imm & (1<<25): imm-=1<<26
                targets.add(pc+4*imm)
            return targets
        # Selector getter -> saved getter -> SaveInt. Also called by BeginRun.
        self.assertIn(0x152435c,calls(0x1524590,0x1524648))
        self.assertIn(0x14b04f8,calls(0x152435c,0x1524468))
        self.assertIn(0x1524590,calls(0x1524f78,0x1525194))
        # Native OnNonPerfect -> promotion; its stock writes are hooked, including tail calls.
        self.assertIn(0x15247fc,calls(0x14daaa4,0x14dad94))
        self.assertIn(0x14b0410,calls(0x15247fc,0x1524a14))
        # Native result Start -> hidden song navigation + stock success promotion.
        self.assertTrue({0x1522c54,0x1522e4c} <= calls(0x1522144,0x1522a00))
        self.assertIn(0x14ffc50,calls(0x15231c8,0x15232dc))
        manifest=(SRC.parent/'Core/PMHookManifest.hpp').read_text('utf8')
        for addr,label in (('14b04f8','SaveInt'),('14b0410','SaveBool')):
            self.assertRegex(manifest,'0x'+addr+'u,[^\n]+// '+label)
        tiers=struct.pack('<5i',1,10,50,100,200)
        self.assertIn(tiers,(root/'global-metadata.dat').read_bytes())
        pattern=rb'"Address": 76499328,\s*"Name": "[^"\n]*\.'+hashlib.sha256(tiers).hexdigest().upper().encode()+rb'"'
        self.assertRegex((root/'script.json').read_bytes(),pattern)
        # Rules .cctor resolves the array data at 0x48f4980 and allocates five ints.
        from capstone import Cs,CS_ARCH_ARM64,CS_MODE_ARM
        asm=[(i.mnemonic,i.op_str) for i in Cs(CS_ARCH_ARM64,CS_MODE_ARM).disasm(blob[0x15254b0:0x1525548],0x15254b0)]
        for ins in [('adrp','x21, #0x48f4000'),('add','x21, x21, #0x980'),('mov','w1, #5')]:self.assertIn(ins,asm)

if __name__=='__main__':unittest.main()
