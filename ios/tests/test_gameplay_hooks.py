"""Emulate every offline gameplay entry gate, callback path and gateway.
No game binary is required in CI. Optional --unity audits the local real image.
"""
import argparse,json,random,struct,sys,unittest,tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import patch_gameplay_hooks as hook
import patch_judge_windows as judge
import inject_load_dylib as inject
from unicorn import Uc,UC_ARCH_ARM64,UC_MODE_ARM
from unicorn.arm64_const import *
GAME=None

def fixture():
    entries=json.loads(hook.MANIFEST.read_text())
    text_end=judge.align(max(e['rva'] for e in entries)+0x8000,0x4000)
    data_vm=text_end+0x10000
    def segment(name,vm,size,off,filesize,secs,prot):
        return struct.pack('<II16sQQQQIIII',0x19,72+80*len(secs),name,vm,size,off,filesize,prot,prot,len(secs),0)+b''.join(secs)
    commands=[segment(b'__TEXT',0,text_end,0,text_end,[judge.section(b'__text',b'__TEXT',0x4000,text_end-0x8000-0x4000,0x4000,0x80000400)],5),
              segment(b'__DATA',data_vm,0x10000,text_end,0x1000,[judge.section(b'__common',b'__DATA',data_vm+0x1000,0x1000,0,1)],3),
              struct.pack('<II16s',0x1b,24,judge.UUID)]
    b=bytearray(text_end+0x1000)
    b[:32]=struct.pack('<IIIIIIII',0xfeedfacf,0x100000c,0,6,len(commands),sum(map(len,commands)),0,0)
    b[32:32+sum(map(len,commands))]=b''.join(commands)
    for e in entries:b[e['rva']:e['rva']+4]=bytes.fromhex(e['bytes'])
    for site,old in zip(judge.SITES,judge.ORIGINAL):b[site:site+4]=old
    return bytes(b)

class GameplayGateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original=Path(GAME).read_bytes() if GAME else fixture()
        cls.judged,cls.judge_report=judge.patch_binary(cls.original)
        cls.patched,cls.report=hook.patch_binary(cls.judged)

    def test_protocol_manifest_and_fail_closed(self):
        r=self.report;c=r['code'];d=self.patched
        self.assertEqual(d[c:c+16],hook.MAGIC)
        self.assertEqual(struct.unpack_from('<IIQ',d,c+16),(1,37,r['state']))
        for i,e in enumerate(r['hooks']):
            self.assertEqual(struct.unpack_from('<IIQ',d,c+32+i*16),(e['rva'],int.from_bytes(bytes.fromhex(e['bytes']),'little'),e['gateway']))
        with self.assertRaises(ValueError):hook.patch_binary(d)
        bad=bytearray(self.judged);bad[r['hooks'][3]['rva']]^=1
        with self.assertRaises(ValueError):hook.patch_binary(bad)
        bad=bytearray(self.judged)
        pos=bad.index(judge.UUID);bad[pos]^=1
        with self.assertRaises(ValueError):hook.patch_binary(bad)
        self.assertEqual(self.judged[self.judge_report['code']:self.judge_report['code']+self.judge_report['code_size']],d[self.judge_report['code']:self.judge_report['code']+self.judge_report['code_size']])
        cmds=judge.parse(d)
        self.assertEqual([x for x in cmds if x.get('name')==b'__TEXT'][0]['raw'][60:64],struct.pack('<I',5))
        self.assertEqual([x for x in cmds if x.get('name')==b'__DATA'][0]['raw'][60:64],struct.pack('<I',3))

    def test_dependency_judge_and_gameplay_combination(self):
        dependency="@loader_path/../PhiMod.framework/PhiMod"
        with tempfile.TemporaryDirectory() as temp:
            binary=Path(temp)/'UnityFramework';binary.write_bytes(self.original)
            self.assertTrue(inject.inject(binary,dependency,False).startswith("inserted at "))
            with_judge,_=judge.patch_binary(binary.read_bytes())
            both,report=hook.patch_binary(with_judge)
            data=bytearray(both)
            _,_,commands=inject.parse_commands(data)
            names=[inject.dylib_name(data,p,n) for p,c,n in commands if c==inject.LC_LOAD_DYLIB]
            self.assertIn(dependency,names)
            self.assertEqual(report['state_size'],37*8)
            binary.write_bytes(both)
            self.assertEqual(inject.inject(binary,dependency,False),"already present")
            self.assertEqual(binary.read_bytes(),both)

    def test_all_37_gates_with_two_aslr_slides(self):
        rng=random.Random(40137)
        # Compare SP, all integer / vector banks, flags, and stack spill data.
        for slide in (0,0x100000000):
            uc=Uc(UC_ARCH_ARM64,UC_MODE_ARM);mapped=set()
            def ensure(addr,size):
                for page in range(addr&~4095,(addr+size+4095)&~4095,4096):
                    if page not in mapped:uc.mem_map(page,4096);mapped.add(page)
            r=self.report
            for address,size in ((slide+r['code'],r['code_size']),(slide+r['state'],r['state_size']),(0x800000,0x8000),(slide+0x7000000,4096)):
                ensure(address,size)
            uc.mem_write(slide+r['code'],self.patched[r['code']:r['code']+r['code_size']])
            callback=slide+0x7000000;uc.mem_write(callback,struct.pack('<I',0xd65f03c0))
            for e in r['hooks']:
                site=slide+e['rva'];ensure(site,8);uc.mem_write(site,self.patched[e['rva']:e['rva']+4])
                regs=[rng.getrandbits(64) for _ in range(31)];fp=[rng.getrandbits(128) for _ in range(32)];flags=rng.randrange(16)<<28;sp=0x804000
                stack=bytes(rng.getrandbits(8) for _ in range(0x2000))
                def reset():
                    uc.mem_write(sp-0x1000,stack)
                    for i,v in enumerate(regs):uc.reg_write(UC_ARM64_REG_X0+i,v) if i<29 else uc.reg_write((UC_ARM64_REG_X29,UC_ARM64_REG_X30)[i-29],v)
                    for i,v in enumerate(fp):uc.reg_write(UC_ARM64_REG_Q0+i,v)
                    uc.reg_write(UC_ARM64_REG_SP,sp);uc.reg_write(UC_ARM64_REG_NZCV,flags)
                def state():
                    return ([uc.reg_read(UC_ARM64_REG_X0+i) if i<29 else uc.reg_read((UC_ARM64_REG_X29,UC_ARM64_REG_X30)[i-29]) for i in range(31)],
                            [uc.reg_read(UC_ARM64_REG_Q0+i) for i in range(32)],uc.reg_read(UC_ARM64_REG_SP),uc.reg_read(UC_ARM64_REG_NZCV))
                gateway=slide+e['gateway'];old=bytes.fromhex(e['bytes'])
                # Execute unmodified original first instruction as a baseline.
                uc.mem_write(callback+0x100,old);reset();uc.emu_start(callback+0x100,callback+0x104,count=1)
                expected=state();expected_stack=bytes(uc.mem_read(sp-0x1000,0x2000))
                uc.mem_write(slide+e['slot'],struct.pack('<Q',0));reset();uc.emu_start(site,site+4,count=20)
                self.assertEqual(state(),expected,e['id']+' dormant')
                # Gate scratch below the original SP is deliberately caller-
                # clobbered; stack args AT/ABOVE original SP must not change.
                self.assertEqual(bytes(uc.mem_read(sp,0x1000)),expected_stack[0x1000:])
                # Callback route skips prologue, preserving original argument
                # banks/SP/LR/flags. IP1 x17 may be scratch per AAPCS64.
                uc.mem_write(slide+e['slot'],struct.pack('<Q',callback));reset();uc.emu_start(site,callback,count=20)
                got=state();want=list(regs);want[17]=callback
                self.assertEqual(got,(want,fp,sp,flags),e['id']+' callback')
                self.assertEqual(bytes(uc.mem_read(sp,0x1000)),stack[0x1000:])
                # C callback can call the gateway directly: no synthetic pop.
                reset();uc.emu_start(gateway,site+4,count=5)
                self.assertEqual(state(),expected,e['id']+' gateway')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--unity');args,rest=parser.parse_known_args();GAME=args.unity
    unittest.main(argv=[sys.argv[0]]+rest)