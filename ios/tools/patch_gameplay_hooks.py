#!/usr/bin/env python3
"""Install version-gated, dormant ARM64 entry gates BEFORE code signing.

No dlsym symbol interposition, MethodInfo writes, RWX or runtime text patching.
Each exact prologue is relocated to an RX gateway. With callback==0 the
original function executes. Callback pointers are ordinary writable DATA.
"""
from pathlib import Path
import argparse, hashlib, json, struct
from patch_judge_windows import parse, align, branch, adrp, section
MAGIC=b'PMGameplay-v2\0\0\0'
TEXT_NAME=b'__pmghook';DATA_NAME=b'__pmgame'
MANIFEST=Path(__file__).with_name('gameplay_hook_manifest.json')

def entry_gate(pc,slot,site,original):
    # Keep all argument banks, LR, NZCV, and stack arguments intact. x16/x17
    # are ABI IP scratch; dormant/original path restores both exactly.
    w=[0xa9bf47f0,adrp(16,pc+4,slot),0x91000210|((slot&4095)<<10),
       0xf9400210,0xb4000000|(5<<5)|16, # cbz x16,restore
       0xaa1003f1,0xf94003f0,0x910043ff,0xd61f0220,
       0xa8c147f0,struct.unpack('<I',original)[0],branch(pc+44,site+4)]
    # Gateway begins AFTER the restore: callable directly from the C callback.
    return struct.pack('<12I',*w),pc+40

def patch_binary(raw):
    b=bytearray(raw);cmds=parse(b);items=json.loads(MANIFEST.read_text())
    text=next(c for c in cmds if c.get('name')==b'__TEXT');data=next(c for c in cmds if c.get('name')==b'__DATA')
    if text['vm'] or text['off']:raise ValueError('Unexpected TEXT mapping')
    if struct.unpack_from('<I',text['raw'],60)[0]!=5 or struct.unpack_from('<I',data['raw'],60)[0]!=3:raise ValueError('Expected RX TEXT/RW DATA')
    if any(s[0] in (TEXT_NAME,DATA_NAME) for c in cmds for s in c.get('sections',[])):raise ValueError('Gameplay patch already installed')
    for e in items:
        site=e['rva'];old=bytes.fromhex(e['bytes']);word=int.from_bytes(old,'little')
        # Audited first instructions must be position-independent stack
        # prologues only. No ADR/ADRP/LDR literal/branches can be relocated.
        if not ((word&0x3b4003e0)==0x290003e0 or (word&0xff8003ff)==0xd10003ff):raise ValueError('Non-stack prologue encoding')
        if b[site:site+4]!=old:raise ValueError('Entry mismatch: '+e['name'])
    code=align(max(s[1]+s[2] for s in text['sections']));state=align(max(s[1]+s[2] for s in data['sections']));size=len(items)*8
    if state<data['vm']+data['fs'] or state+size>data['vm']+data['vs']:raise ValueError('No unused DATA VM tail')
    descriptor=32+16*len(items);payload=bytearray(MAGIC+struct.pack('<IIQ',2,len(items),state));stubs=bytearray();patches=[];report=[]
    for i,e in enumerate(items):
        pc=code+descriptor+len(stubs);old=bytes.fromhex(e['bytes']);stub,gateway=entry_gate(pc,state+i*8,e['rva'],old)
        payload+=struct.pack('<IIQ',e['rva'],int.from_bytes(old,'little'),gateway);stubs+=stub
        patches.append((e['rva'],branch(e['rva'],pc)));report.append(dict(e,gateway=gateway,gate=pc,slot=state+i*8))
    payload+=stubs
    if code+len(payload)>text['vm']+text['fs'] or any(b[code:code+len(payload)]):raise ValueError('No unused RX file tail')
    for c in cmds:
        if c['cmd']==0x19 and any(struct.unpack_from('<I',c['raw'],72+k*80+60)[0] for k in range(len(c['sections']))):raise ValueError('Section relocations unsupported')
        if c['cmd']==0xb and any(struct.unpack_from('<4I',c['raw'],64)):raise ValueError('Dynamic relocations unsupported')
        if c['cmd']==2:
            symoff,nsyms=struct.unpack_from('<II',c['raw'],8)
            for k in range(nsyms):
                q=symoff+k*16
                if b[q+4]&0x0e==0x0e and b[q+5]>len(text['sections']):
                    if b[q+5]==255:raise ValueError('Symbol section overflow')
                    b[q+5]+=1
    blocks=[]
    for c in cmds:
        block=bytearray(c['raw'])
        if c is text or c is data:
            struct.pack_into('<I',block,4,len(block)+80);struct.pack_into('<I',block,64,len(c['sections'])+1)
            block+=section(TEXT_NAME,b'__TEXT',code,len(payload),code,0x80000400) if c is text else section(DATA_NAME,b'__DATA',state,size,0,1)
        blocks.append(block)
    commands=b''.join(blocks);oldend=32+struct.unpack_from('<I',b,20)[0];newend=32+len(commands)
    first=min(s[3] for c in cmds for s in c.get('sections',[]) if s[3])
    if newend>first or any(b[oldend:newend]):raise ValueError('No load-command padding')
    b[32:newend]=commands;struct.pack_into('<I',b,20,len(commands));b[code:code+len(payload)]=payload
    for site,word in patches:struct.pack_into('<I',b,site,word)
    return bytes(b),{'version':2,'code':code,'code_size':len(payload),'state':state,'state_size':size,'hooks':report,'input_sha256':hashlib.sha256(raw).hexdigest(),'output_sha256':hashlib.sha256(b).hexdigest()}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('binary',type=Path);p.add_argument('--no-backup',action='store_true');a=p.parse_args()
    raw=a.binary.read_bytes();out,report=patch_binary(raw)
    if not a.no_backup:
        backup=a.binary.with_name(a.binary.name+'.before-gameplay')
        if backup.exists():raise ValueError('Backup exists')
        backup.write_bytes(raw)
    a.binary.write_bytes(out);print(json.dumps(report,indent=2))
if __name__=='__main__':main()
