"""Execute this iOS UUID's actual IL2CPP instance setter, not an ABI mock.

Run with --unity path/to/UnityFramework; the game binary stays local.
"""
import argparse, struct, unittest
from pathlib import Path
from unicorn import Uc, UC_ARCH_ARM64, UC_MODE_ARM, UC_HOOK_CODE
from unicorn.arm64_const import UC_ARM64_REG_X0, UC_ARM64_REG_X1, UC_ARM64_REG_X2, UC_ARM64_REG_X30, UC_ARM64_REG_SP, UC_ARM64_REG_PC

IMAGE = None

class ReferenceSetterTest(unittest.TestCase):
 def setUp(self):
  if IMAGE is None:self.skipTest("Pass --unity path to the local UnityFramework binary")
 def run_setter(self, kind, pointer_argument, payload=b'', static=False):
  raw = Path(IMAGE).read_bytes()
  # Version-gate the export and dispatcher before executing fixed addresses.
  self.assertEqual(raw[0x1425a00:0x1425a04], bytes.fromhex('281880b9'))
  uc = Uc(UC_ARCH_ARM64, UC_MODE_ARM)
  for base, size in ((0x1420000,0x10000),(0x424e000,0x1000),(0x232000,0x1000)):
   uc.mem_map(base,size);uc.mem_write(base,raw[base:base+size])
  uc.mem_map(0x6000000,0x10000)
  obj, field, typ, value, stack, stop = (0x6000000,0x6000100,0x6000200,0x6000300,0x600f000,0x600f800)
  uc.mem_write(field+8,struct.pack('<Q',typ));uc.mem_write(field+24,struct.pack('<i',32))
  uc.mem_write(typ+8,struct.pack('<I',kind<<16))
  klass=0x6001000
  uc.mem_write(field+16,struct.pack('<Q',klass));uc.mem_write(klass+0xb8,struct.pack('<Q',obj))
  if payload:uc.mem_write(value,payload)
  uc.reg_write(UC_ARM64_REG_X0,obj);uc.reg_write(UC_ARM64_REG_X1,field)
  uc.reg_write(UC_ARM64_REG_X2,pointer_argument if pointer_argument is not None else value)
  if static:
   uc.reg_write(UC_ARM64_REG_X0,field)
   uc.reg_write(UC_ARM64_REG_X1,pointer_argument if pointer_argument is not None else value)
  uc.reg_write(UC_ARM64_REG_SP,stack);uc.reg_write(UC_ARM64_REG_X30,stop)
  # The GC barrier stores the object reference; no live GC exists in this test.
  def barrier(uc,address,size,user):
   if address==0x1429234:
    uc.reg_write(UC_ARM64_REG_PC,uc.reg_read(UC_ARM64_REG_X30))
   if address==0x232c34:
    uc.mem_write(uc.reg_read(UC_ARM64_REG_X0),struct.pack('<Q',uc.reg_read(UC_ARM64_REG_X1)))
    uc.emu_stop()
  uc.hook_add(UC_HOOK_CODE,barrier)
  uc.emu_start(0x1425ac8 if static else 0x1425a00,stop,count=100)
  return bytes(uc.mem_read(obj+32,8))
 def test_references_are_passed_directly_including_null(self):
  for kind in (0x0e,0x12,0x14,0x1c,0x1d):
   for reference in (0,0x6000800):
    with self.subTest(kind=kind,reference=reference):
     self.assertEqual(struct.unpack('<Q',self.run_setter(kind,reference))[0],reference)
 def test_address_of_reference_would_corrupt_the_field(self):
  actual=struct.unpack('<Q',self.run_setter(0x12,None,struct.pack('<Q',0x6000800)))[0]
  self.assertEqual(actual,0x6000300)
  self.assertNotEqual(actual,0x6000800)
 def test_scalar_values_still_require_addresses(self):
  self.assertEqual(self.run_setter(0x0c,None,struct.pack('<f',1.25))[:4],struct.pack('<f',1.25))
  self.assertEqual(self.run_setter(0x08,None,struct.pack('<i',-25))[:4],struct.pack('<i',-25))
 def test_static_references_and_scalars(self):
  for reference in (0,0x6000800):
   self.assertEqual(struct.unpack('<Q',self.run_setter(0x0e,reference,static=True))[0],reference)
  self.assertEqual(self.run_setter(0x0c,None,struct.pack('<f',.08),static=True)[:4],struct.pack('<f',.08))

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--unity',required=True)
 args,rest=parser.parse_known_args();IMAGE=args.unity
 unittest.main(argv=[__file__]+rest)
