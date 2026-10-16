"""Execute the ACTUAL generated ARM64 code with Unicorn (dev dependency only).

    pip install unicorn
    python ios/tests/test_judge_patch.py --unity path/to/UnityFramework

CI without a game binary uses a synthetic Mach-O fixture and the same generator.
The game binary stays local. No copyrighted binary is checked in or uploaded.
"""
import argparse
from pathlib import Path
import random
import struct
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import patch_judge_windows as patch
from unicorn import Uc,UC_ARCH_ARM64,UC_MODE_ARM
from unicorn.arm64_const import *

GAME=None

def fixture():
    # Minimal linked arm64 image with the target stores and spare segment tails.
    text_end=0x1594000; data_vm=0x1600000
    commands=[]
    def segment(name,vm,size,off,filesize,secs,prot):
        return struct.pack('<II16sQQQQIIII',0x19,72+80*len(secs),name,vm,size,off,filesize,prot,prot,len(secs),0)+b''.join(secs)
    commands.append(segment(b'__TEXT',0,text_end,0,text_end,[patch.section(b'__text',b'__TEXT',0x4000,0x1590000-0x4000,0x4000,0x80000400)],5))
    commands.append(segment(b'__DATA',data_vm,0x4000,text_end,0x1000,[patch.section(b'__common',b'__DATA',data_vm+0x1000,0x1000,0,1)],3))
    commands.append(struct.pack('<II16s',0x1b,24,patch.UUID))
    commands.append(struct.pack('<IIIIII',2,24,text_end,1,0,0)) # a DATA symbol with n_sect=2
    header=struct.pack('<IIIIIIII',0xfeedfacf,0x100000c,0,6,len(commands),sum(map(len,commands)),0,0)
    b=bytearray(text_end+0x1000);b[:32]=header;b[32:32+sum(map(len,commands))]=b''.join(commands)
    # Text section must actually cover all sites, leave padding after the sites.
    struct.pack_into('<Q',b,32+72+40,0x1593000-0x4000)
    for site,old in zip(patch.SITES,patch.ORIGINAL):b[site:site+4]=old
    b[text_end+4]=0x0f;b[text_end+5]=2
    return bytes(b)

class JudgePatchTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original=Path(GAME).read_bytes() if GAME else fixture()
        cls.patched,cls.report=patch.patch_binary(cls.original)

    def test_version_and_repeat_guards(self):
        with self.assertRaises(ValueError):patch.patch_binary(self.patched)
        changed=bytearray(self.original);changed[patch.SITES[0]]^=1
        with self.assertRaises(ValueError):patch.patch_binary(changed)
        cmds=patch.parse(self.patched)
        self.assertTrue(any(s[0]==patch.DATA_NAME and s[2]==40 and s[4]==1 for c in cmds for s in c.get('sections',[])))
        # Every pre-existing nlist section ordinal after TEXT moves by one.
        oldtext=next(c for c in patch.parse(self.original) if c.get('name')==b'__TEXT')
        for c in cmds:
            if c['cmd']==2:
                off,num=struct.unpack_from('<II',c['raw'],8)
                for k in range(num):
                    q=off+k*16
                    before=self.original[q+5];after=self.patched[q+5]
                    expected=before+1 if self.original[q+4]&14==14 and before>len(oldtext['sections']) else before
                    self.assertEqual(after,expected)

    def test_arm64_stores_registers_flags_and_frames(self):
        code=self.report['code'];state=self.report['state'];rng=random.Random(401)
        # Test different ASLR slides too: PC-relative addressing must remain valid.
        for slide in (0,0x100000000):
            uc=Uc(UC_ARCH_ARM64,UC_MODE_ARM)
            for addr,size in ((code&~4095,0x2000),(state&~4095,0x1000),(0x100000,0x2000),(0x200000,0x2000)):
                uc.mem_map(slide+addr,size)
            uc.mem_write(slide+code,self.patched[code:code+self.report['code_size']])
            for site in patch.SITES:
                page=(site+slide)&~4095
                # All sites are within one page.
                if site==patch.SITES[0]:uc.mem_map(page,4096)
                uc.mem_write(slide+site,self.patched[site:site+4])
            for frame in range(90):
                enabled=frame%3!=0;p=rng.uniform(.001,.1);g=p+rng.uniform(.01,.2);b=max(.22,g+.04)
                engine=(rng.uniform(.03,.08),rng.uniform(.1,.18),rng.uniform(.19,.22))
                uc.mem_write(slide+state,struct.pack('<IBBHfffIfffI',int(enabled),0,0,0,p,g,b,0,0,0,0,0))
                for kind in ((0,2) if frame%2==0 else (1,2)):
                    site=patch.SITES[kind]
                    registers=[rng.getrandbits(64) for _ in range(31)]
                    # Explicit constants: X registers are not universally contiguous in Unicorn.
                    regs=[UC_ARM64_REG_X0,UC_ARM64_REG_X1,UC_ARM64_REG_X2,UC_ARM64_REG_X3,UC_ARM64_REG_X4,UC_ARM64_REG_X5,UC_ARM64_REG_X6,UC_ARM64_REG_X7,UC_ARM64_REG_X8,UC_ARM64_REG_X9,UC_ARM64_REG_X10,UC_ARM64_REG_X11,UC_ARM64_REG_X12,UC_ARM64_REG_X13,UC_ARM64_REG_X14,UC_ARM64_REG_X15,UC_ARM64_REG_X16,UC_ARM64_REG_X17,UC_ARM64_REG_X18,UC_ARM64_REG_X19,UC_ARM64_REG_X20,UC_ARM64_REG_X21,UC_ARM64_REG_X22,UC_ARM64_REG_X23,UC_ARM64_REG_X24,UC_ARM64_REG_X25,UC_ARM64_REG_X26,UC_ARM64_REG_X27,UC_ARM64_REG_X28,UC_ARM64_REG_X29,UC_ARM64_REG_X30]
                    for r,v in zip(regs,registers):uc.reg_write(r,v)
                    uc.reg_write(UC_ARM64_REG_X8,slide+0x100000)
                    uc.reg_write(UC_ARM64_REG_SP,slide+0x201000)
                    uc.reg_write(UC_ARM64_REG_NZCV,0xa0000000)
                    floats=struct.pack('<ff',*engine[:2]) if kind<2 else struct.pack('<f',engine[2])+b'\x00'*4
                    source=int.from_bytes(floats+b'\x73'*8,'little')
                    uc.reg_write(UC_ARM64_REG_Q0,source if kind!=1 else 123)
                    uc.reg_write(UC_ARM64_REG_Q1,source if kind==1 else 456)
                    before=[uc.reg_read(r) for r in regs]
                    q0=uc.reg_read(UC_ARM64_REG_Q0);q1=uc.reg_read(UC_ARM64_REG_Q1)
                    uc.emu_start(slide+site,slide+site+4,count=32)
                    self.assertEqual(uc.reg_read(UC_ARM64_REG_PC),slide+site+4)
                    self.assertEqual([uc.reg_read(r) for r in regs],before)
                    self.assertEqual(uc.reg_read(UC_ARM64_REG_SP),slide+0x201000)
                    self.assertEqual(uc.reg_read(UC_ARM64_REG_NZCV),0xa0000000)
                    self.assertEqual(uc.reg_read(UC_ARM64_REG_Q0),q0);self.assertEqual(uc.reg_read(UC_ARM64_REG_Q1),q1)
                    expected=(p,g,b) if enabled else engine
                    if kind<2:
                        self.assertEqual(bytes(uc.mem_read(slide+0x100004,8)),struct.pack('<ff',*expected[:2]))
                        self.assertEqual(bytes(uc.mem_read(slide+state+24,8)),struct.pack('<ff',*engine[:2]))
                    else:
                        self.assertEqual(bytes(uc.mem_read(slide+0x10000c,4)),struct.pack('<f',expected[2]))
                        self.assertEqual(bytes(uc.mem_read(slide+state+32,4)),struct.pack('<f',engine[2]))
                self.assertEqual(bytes(uc.mem_read(slide+state+4,2)),b'\1\1')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--unity');a,extra=p.parse_known_args();GAME=a.unity
    unittest.main(argv=[sys.argv[0]]+extra)
