#!/usr/bin/env python3
"""Version-gated, offline arm64 judge interception (before re-signing).

ProgressControl.Update overwrites JudgeControl windows every frame. Replace
exactly its three stores with direct branches to RX __TEXT padding. Each
trampoline records the engine value, then performs the original store or a
configured store. Config lives in a NEW zero-fill section in unused __DATA
VM tail, never in an existing BSS/common object. All other registers/flags and
FP/vector registers are preserved. Unloaded/disabled PhiMod => original logic.
No Apple/third-party libraries required; edits only the explicitly passed file.
"""
from __future__ import annotations
import argparse
import hashlib
from pathlib import Path
import struct

UUID=bytes.fromhex('6e181f31750a3044a73a1498dc2d56d4')
MAGIC=b'PMJudgeHook-v1\0\0' # also retained in the new framework
STATE_SIZE=40
SITES=(0x1592808,0x159287c,0x1592890)
ORIGINAL=(bytes.fromhex('004100fc'),bytes.fromhex('014100fc'),bytes.fromhex('000d00bd'))
TEXT_NAME=b'__pmjhook'
DATA_NAME=b'__pmjudge'

def align(x,n=16): return (x+n-1)&-n

def branch(pc,target):
    delta=target-pc
    if delta%4 or not -(1<<27)<=delta<(1<<27): raise ValueError('B target out of range')
    return 0x14000000|((delta//4)&0x3ffffff)

def adrp(reg,pc,target):
    delta=((target&~4095)-(pc&~4095))//4096
    if not -(1<<20)<=delta<(1<<20): raise ValueError('ADRP target out of range')
    return 0x90000000|((delta&3)<<29)|(((delta>>2)&0x7ffff)<<5)|reg

def trampoline(pc,data,site,original,kind):
    # stp x16,x17,[sp,#-16]!; adrp/add x16; record unmodified engine window
    words=[0xa9bf47f0, adrp(16,pc+4,data), 0x91000210|((data&4095)<<10)]
    if kind<2:
        # stur d0/d1,[x16,#24] (does not modify the FP source)
        words += [0xfc000000|(24<<12)|(16<<5)|kind]
    else:
        words += [0xbd000000|(8<<10)|(16<<5)] # str s0,[x16,#32]
    words += [0x52800031, 0x39000000|((4 if kind<2 else 5)<<10)|(16<<5)|17,
              0xb9400000|(16<<5)|17] # seen byte=1; ldr w17,[x16]
    cbz_index=len(words); words += [0]
    if kind<2:
        words += [0xf9400000|(1<<10)|(16<<5)|17, 0xf8000000|(4<<12)|(8<<5)|17]
    else:
        words += [0xb9400000|(4<<10)|(16<<5)|17, 0xb9000000|(3<<10)|(8<<5)|17]
    done_index=len(words); words += [0]
    normal_index=len(words); words += [struct.unpack('<I',original)[0]]
    restore_index=len(words); words += [0xa8c147f0,branch(pc+(len(words)+1)*4,site+4)]
    words[cbz_index]=0x34000000|((normal_index-cbz_index)<<5)|17
    words[done_index]=branch(pc+done_index*4,pc+restore_index*4)
    return struct.pack('<'+'I'*len(words),*words)

def parse(b):
    if struct.unpack_from('<II',b,0)!=(0xfeedfacf,0x100000c): raise ValueError('Expected thin arm64 Mach-O')
    n,size=struct.unpack_from('<II',b,16); p=32; cmds=[]; uuid=None
    for _ in range(n):
        cmd,length=struct.unpack_from('<II',b,p)
        if length<8 or p+length>32+size: raise ValueError('Invalid load commands')
        entry={'cmd':cmd,'raw':bytes(b[p:p+length])}
        if cmd==0x1b: uuid=bytes(b[p+8:p+24])
        if cmd==0x19:
            name=bytes(b[p+8:p+24]).rstrip(b'\0'); vm,vs,off,fs=struct.unpack_from('<QQQQ',b,p+24)
            ns=struct.unpack_from('<I',b,p+64)[0]; sections=[]
            for k in range(ns):
                q=p+72+k*80
                sn=bytes(b[q:q+16]).rstrip(b'\0'); addr,siz,fo=struct.unpack_from('<QQI',b,q+32)
                sections.append((sn,addr,siz,fo,struct.unpack_from('<I',b,q+64)[0]))
            entry.update(name=name,vm=vm,vs=vs,off=off,fs=fs,sections=sections)
        cmds.append(entry); p+=length
    if p!=32+size: raise ValueError('Load command size mismatch')
    if uuid!=UUID: raise ValueError('Unsupported UnityFramework UUID; not patching')
    return cmds

def section(name,segment,addr,size,offset,flags):
    return struct.pack('<16s16sQQIIIIIIII',name,segment,addr,size,offset,4,0,0,flags,0,0,0)

def patch_binary(raw):
    b=bytearray(raw);cmds=parse(b)
    text=next(c for c in cmds if c.get('name')==b'__TEXT')
    data=next(c for c in cmds if c.get('name')==b'__DATA')
    if text['vm']!=0 or text['off']!=0: raise ValueError('Unexpected TEXT mapping')
    if (struct.unpack_from('<I',text['raw'],60)[0]&7)!=5 or (struct.unpack_from('<I',data['raw'],60)[0]&7)!=3:
        raise ValueError('Unexpected segment protection; never create writable executable memory')
    if any(s[0] in (TEXT_NAME,DATA_NAME) for c in cmds for s in c.get('sections',[])):
        raise ValueError('Judge patch already present; package again from original Payload')
    for site,old in zip(SITES,ORIGINAL):
        if b[site:site+4]!=old: raise ValueError(f'Unexpected judge instruction at {site:#x}')
    code=align(max(s[1]+s[2] for s in text['sections']))
    state=align(max(s[1]+s[2] for s in data['sections']))
    if state<data['vm']+data['fs'] or state+STATE_SIZE>data['vm']+data['vs']:
        raise ValueError('No unused writable VM tail; not using occupied BSS')
    payload=bytearray(MAGIC+struct.pack('<IIQ',1,STATE_SIZE,state))
    patches=[]
    for kind,(site,old) in enumerate(zip(SITES,ORIGINAL)):
        pc=code+len(payload);stub=trampoline(pc,state,site,old,kind)
        payload+=stub; patches.append((site,branch(site,pc)))
    if code+len(payload)>text['vm']+text['fs']: raise ValueError('Insufficient RX padding')
    if any(b[code:code+len(payload)]): raise ValueError('RX padding is not zero')
    # Fully linked images must not have section relocations. nlist_64 section
    # ordinals after TEXT move up by one; segment indices/VM addresses do not.
    for c in cmds:
        if c['cmd']==0x19:
            for k in range(len(c['sections'])):
                if struct.unpack_from('<I',c['raw'],72+k*80+60)[0]:
                    raise ValueError('Unexpected section relocations')
        if c['cmd']==0xb and any(struct.unpack_from('<II',c['raw'],64)):
            raise ValueError('Unexpected external relocations')
        if c['cmd']==0xb and any(struct.unpack_from('<II',c['raw'],72)):
            raise ValueError('Unexpected local relocations')
        if c['cmd']==2: # LC_SYMTAB
            symoff,nsyms=struct.unpack_from('<II',c['raw'],8)
            for k in range(nsyms):
                q=symoff+k*16
                if b[q+4]&0x0e==0x0e and b[q+5]>len(text['sections']): b[q+5]+=1
    newcmds=[]
    for c in cmds:
        block=bytearray(c['raw'])
        if c is text or c is data:
            ns=len(c['sections']);struct.pack_into('<I',block,4,len(block)+80);struct.pack_into('<I',block,64,ns+1)
            block+=section(TEXT_NAME,b'__TEXT',code,len(payload),code,0x80000400) if c is text else section(DATA_NAME,b'__DATA',state,STATE_SIZE,0,1)
        newcmds.append(block)
    commands=b''.join(newcmds); oldend=32+struct.unpack_from('<I',b,20)[0];newend=32+len(commands)
    first=min(s[3] for c in cmds for s in c.get('sections',[]) if s[3])
    if newend>first or any(b[oldend:newend]): raise ValueError('Insufficient load-command padding')
    b[32:newend]=commands;struct.pack_into('<I',b,20,len(commands))
    b[code:code+len(payload)]=payload
    for site,word in patches: struct.pack_into('<I',b,site,word)
    return bytes(b),{'protocol':1,'code':code,'state':state,'sites':list(SITES),'code_size':len(payload),
                     'input_sha256':hashlib.sha256(raw).hexdigest(),'output_sha256':hashlib.sha256(b).hexdigest()}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('binary',type=Path);p.add_argument('--no-backup',action='store_true');a=p.parse_args()
    original=a.binary.read_bytes();patched,report=patch_binary(original)
    if not a.no_backup:
        backup=a.binary.with_name(a.binary.name+'.before-judge')
        if backup.exists(): raise ValueError('Backup already exists')
        backup.write_bytes(original)
    a.binary.write_bytes(patched)
    import json
    print(json.dumps(report,indent=2))
if __name__=='__main__': main()
