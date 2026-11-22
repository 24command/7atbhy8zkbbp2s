"""Build dormant stock OS scene copies for the verified iOS 4.0.4 player.

The player uses stripped little-endian v22 SerializedFiles. Preserve object IDs,
script type indices, externals, and all stock scene files. The only new active
GameObject has a Transform and no other components.
"""
import hashlib
import struct
from pathlib import Path

ROOT_NAME = 'PhiModStockOSHost'
PREFIX = 'Assets/PhiMod/OS/'
DONORS = (
    (22, 'SaturnOS/SaturnOS', '64f29009e0529e31849c24b2ef7ddb4b9ba4d167c41d234d26ec04770a2ed51e'),
    (23, 'Chapter8/Chapter8SelectMusic', '178007ea9b92263625a12335bbe40effb82a1242bef9bcaf55b2221654846e7f'),
    (28, 'Chapter9/Chapter9SelectMusic', '62baedc11d75cc080f90ebef1f85f26f27369dbb4fe43f650e6521fecdc6f9b6'),
    (30, 'Chapter9/Chapter9Phase2', '30922cdc1f4cbd1916c81b8f565a18db7d0d9fef950ff9e2ec89c3791b6b63df'),
)
MANAGERS_HASH = 'fe4d958fe1ab8cbe1f1dc1584077c1062dd09778891cabaca333294dc4f5d598'


def aligned(n, boundary=4):
    return (n + boundary - 1) & -boundary


def string(text):
    raw = text.encode('utf-8')
    return struct.pack('<I', len(raw)) + raw.ljust(aligned(len(raw)), b'\0')


def ptr(path_id):
    return struct.pack('<iq', 0, path_id)


class SerializedFile:
    def __init__(self, raw):
        if struct.unpack_from('>I', raw, 8)[0] != 22 or raw[16] != 0:
            raise ValueError('Expected a little-endian v22 serialized file')
        meta_size, size, data = struct.unpack_from('>IQQ', raw, 20)
        if size != len(raw) or raw[48:59] != b'2022.3.62f2' or data < 48 + meta_size:
            raise ValueError('Unexpected Unity serialized header')
        p = raw.index(0, 48) + 5
        if raw[p] != 0:
            raise ValueError('Expected stripped type trees')
        p += 1
        type_count, = struct.unpack_from('<I', raw, p)
        p += 4
        self.types = []
        for _ in range(type_count):
            class_id, = struct.unpack_from('<i', raw, p)
            self.types.append(class_id)
            p += 23 + (16 if class_id == 114 else 0)
        self.prefix = raw[:p]
        count, = struct.unpack_from('<I', raw, p)
        p = aligned(p + 4)
        self.objects = {}
        for _ in range(count):
            path_id, offset, length, index = struct.unpack_from('<qQII', raw, p)
            self.objects[path_id] = (index, raw[data+offset:data+offset+length])
            p += 24
        self.tail = raw[p:48+meta_size]

    def encode(self):
        meta = bytearray(self.prefix + struct.pack('<I', len(self.objects)))
        meta.extend(bytes(aligned(len(meta))-len(meta)))
        data = bytearray()
        for path_id, (index, payload) in sorted(self.objects.items()):
            data.extend(bytes(aligned(len(data), 8)-len(data)))
            meta.extend(struct.pack('<qQII', path_id, len(data), len(payload), index))
            data.extend(payload)
        meta.extend(self.tail)
        start = aligned(len(meta), 16)
        struct.pack_into('>IQQ', meta, 20, len(meta)-48, start+len(data), start)
        return bytes(meta).ljust(start, b'\0') + data


def scene_paths(payload):
    count, = struct.unpack_from('<I', payload)
    paths = []
    pos = 4
    for _ in range(count):
        size, = struct.unpack_from('<I', payload, pos)
        paths.append(payload[pos+4:pos+4+size].decode())
        pos += 4 + aligned(size)
    return paths, payload[pos:]


def build_settings(raw):
    sf = SerializedFile(raw)
    (oid,) = [key for key, (t, _) in sf.objects.items() if sf.types[t] == 141]
    index, data = sf.objects[oid]
    paths, tail = scene_paths(data)
    if len(paths) != 38 or paths[7] != 'Assets/Phigros2/SongSelector/SongSelector.unity':
        raise ValueError('Unexpected selector/build indices')
    for source, name, _ in DONORS:
        if paths[source] != 'Assets/Phigros2/' + name + '.unity':
            raise ValueError('Stock scene path mismatch: ' + name)
        paths.append(PREFIX + 'PM' + name.rsplit('/', 1)[-1] + '.unity')
    sf.objects[oid] = index, struct.pack('<I', len(paths)) + b''.join(map(string, paths)) + tail
    return sf.encode()


def dormant_scene(raw):
    sf = SerializedFile(raw)
    anchor = max(sf.objects) + 1
    transform = anchor + 1
    children = []
    for path_id, (index, data) in list(sf.objects.items()):
        if sf.types[index] == 114 and struct.unpack_from('<iq', data, 16) in (
                (1, 199), (1, 218), (1, 712), (1, 913)):
            # Serialize the phase controller disabled before the first activation.
            sf.objects[path_id] = index, data[:12] + b'\0' + data[13:]
        if sf.types[index] not in (4, 224):  # Transform or RectTransform
            continue
        count, = struct.unpack_from('<I', data, 52)
        father = 56 + 12*count
        if data[father:father+12] != ptr(0):
            continue
        children.append(path_id)
        sf.objects[path_id] = index, data[:father] + ptr(transform) + data[father+12:]
        go, = struct.unpack_from('<q', data, 4)
        t, obj = sf.objects[go]
        components, = struct.unpack_from('<I', obj)
        name = 8 + components*12
        length, = struct.unpack_from('<I', obj, name)
        active = name + 4 + aligned(length) + 2
        if sf.types[t] != 1 or active+1 != len(obj):
            raise ValueError('Unexpected root GameObject layout')
        sf.objects[go] = t, obj[:active] + b'\0'
    if not children:
        raise ValueError('Missing stock root transforms')
    sf.objects[anchor] = sf.types.index(1), (struct.pack('<I', 1) + ptr(transform) +
        struct.pack('<I', 0) + string(ROOT_NAME) + struct.pack('<HB', 0, 1))
    sf.objects[transform] = sf.types.index(4), (ptr(anchor) + struct.pack('<10fI',
        0, 0, 0, 1, 0, 0, 0, 1, 1, 1, len(children)) + b''.join(map(ptr, children)) + ptr(0))
    return sf.encode()


def checked(path, expected):
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != expected:
        raise ValueError('4.0.4 source hash mismatch: ' + str(path))
    return raw


def install(data: Path):
    managers = data / 'globalgamemanagers'
    updated = build_settings(checked(managers, MANAGERS_HASH))
    copies = {}
    for dest, (source, _, digest) in enumerate(DONORS, 38):
        path = data / f'level{dest}'
        if path.exists():
            raise ValueError('Donor build index already occupied: ' + str(path))
        copies[path] = dormant_scene(checked(data / f'level{source}', digest))
    for path, raw in copies.items():
        path.write_bytes(raw)
    managers.write_bytes(updated)
