"""Generate the HP course note-count index from a supplied IPA (requires UnityPy)."""
import argparse
import base64
import json
from pathlib import Path
import re
import struct
from zipfile import ZipFile

import UnityPy


def chart_assets(catalog):
    keys, buckets, entries = (base64.b64decode(catalog['m_' + field + 'DataString'])
                              for field in ('Key', 'Bucket', 'Entry'))
    index = []
    position = 4
    for _ in range(struct.unpack_from('<I', buckets)[0]):
        offset, count = struct.unpack_from('<II', buckets, position)
        refs = struct.unpack_from('<' + 'I' * count, buckets, position + 8)
        position += 8 + 4 * count
        key = ''
        if keys[offset] == 0:
            length = struct.unpack_from('<I', keys, offset + 1)[0]
            key = keys[offset + 5:offset + 5 + length].decode('utf8')
        index.append((key, refs))

    def entry(ref):
        return struct.unpack_from('<7i', entries, 4 + 28 * ref)

    bundles = {}
    expected = set()
    for path, refs in index:
        match = re.fullmatch(r'Assets/Tracks/([^/]+)/Chart_([^/]+)\.json', path, re.I)
        if not match:
            continue
        identifier = '|'.join(match.groups())
        expected.add(identifier)
        target = entry(refs[0])
        for dependency in index[target[2]][1]:
            bundle = catalog['m_InternalIds'][entry(dependency)[0]].split('/')[-1]
            if bundle.endswith('.bundle'):
                bundles.setdefault(bundle, []).append((identifier, path, catalog['m_InternalIds'][target[0]]))
    return bundles, expected


def generate(ipa):
    counts = {}
    with ZipFile(ipa) as archive:
        catalogs = [name for name in archive.namelist() if name.endswith('.app/Data/Raw/aa/catalog.json')]
        catalog, = catalogs
        bundles, expected = chart_assets(json.loads(archive.read(catalog)))
        for bundle, charts in bundles.items():
            env = UnityPy.load(archive.read(catalog.rsplit('/', 1)[0] + '/iOS/' + bundle))
            for identifier, path, internal in charts:
                resource = next((env.container[name] for name in (internal, path, path.lower()) if name in env.container), None)
                if resource is None or resource.type.name != 'TextAsset':
                    continue
                lines = json.loads(resource.read().m_Script)['judgeLineList']
                counts[identifier] = sum(len(line.get(side, [])) for line in lines for side in ('notesAbove', 'notesBelow'))
    if not counts or counts.keys() != expected:
        raise ValueError(f'Incomplete chart index: {len(counts)}/{len(expected)}')
    return '// Playable note counts keyed by bundled chart ID and difficulty.\n' + ''.join(
        '    @' + json.dumps(key, ensure_ascii=False) + ': @' + str(count) + ',\n' for key, count in sorted(counts.items()))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.write_text(generate(args.ipa), encoding='utf8')
