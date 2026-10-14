"""Offline inventory: static matches only, not ABI or runtime verification."""
import argparse, hashlib, json, re
from pathlib import Path

def audit(source, dump):
    native_files = list((source / 'native').glob('*'))
    texts = [p.read_text(encoding='utf-8-sig') for p in native_files if p.suffix in ('.h','.cpp','.inc')]
    native = '\n'.join(texts)
    wanted = set(re.findall(r'klass\("([^"\n]*)",\s*"([^"\n]*)"\)', native))
    # Dump blocks are indexed by namespace and declared type, never a substring search.
    classes = {}
    ns = ''
    current = None
    for line in dump.read_text(encoding='utf-8-sig').splitlines():
        if line.startswith('// Namespace:'):
            ns = line.partition(':')[2].strip()
            current = None
        match = re.match(r'.*?\b(?:class|struct|enum)\s+([^ :]+).*// TypeDefIndex:', line)
        if match:
            current = (ns, match.group(1))
            if current in wanted: classes.setdefault(current, []).append(line)
        elif current in wanted:
            classes.setdefault(current, []).append(line)
    bridge=(source/'java/local/phimod/Bridge.java').read_text(encoding='utf-8-sig')
    methods=re.findall(r'public static native\s+([^;]+);',bridge)
    return {'dump_sha256':hashlib.sha256(dump.read_bytes()).hexdigest(),
            'class_references':[{'namespace':ns,'name':name,'found':(ns,name) in classes,
                'declaration':classes.get((ns,name),[''])[0]} for ns,name in sorted(wanted)],
            'android_native_bridge':methods,
            'warning':'Static declarations only; no Android offsets or runtime patches are generated.'},classes

def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--dump',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    result,classes=audit(a.source,a.dump);a.output.mkdir(parents=True,exist_ok=True)
    (a.output/'migration_inventory.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    (a.output/'referenced_types.cs.txt').write_text('\n'.join('\n'.join(v) for k,v in sorted(classes.items())),encoding='utf-8')
    print('Classes found:',sum(x['found'] for x in result['class_references']),'/',len(result['class_references']))
    print('Bridge methods:',len(result['android_native_bridge']))
if __name__=='__main__':main()
