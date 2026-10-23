"""Private selected-layout reader for Linux v6.17 BTF v1, never a guessed ABI.

Format source: https://github.com/torvalds/linux/blob/v6.17/Documentation/bpf/btf.rst
"""
from pathlib import Path
import argparse
import hashlib
import json
import struct

CAP = 32 * 1024 * 1024


def inspect(data):
    if not 24 <= len(data) <= CAP:
        raise ValueError('BTF size outside bounded complete-file range')
    endian = '<' if data[:2] == b'\x9f\xeb' else '>' if data[:2] == b'\xeb\x9f' else None
    if endian is None:
        raise ValueError('BTF magic')
    magic, version, flags, header, type_off, type_len, str_off, str_len = struct.unpack_from(endian + 'HBB5I', data)
    if version != 1 or flags != 0 or not 24 <= header <= len(data):
        raise ValueError('Unsupported BTF header')
    start, end = header + type_off, header + type_off + type_len
    first_string, last_string = header + str_off, header + str_off + str_len
    if not (header <= start <= end <= len(data) and header <= first_string < last_string == len(data)
            and (end <= first_string or last_string <= start)):
        raise ValueError('BTF section bounds/overlap/completeness')
    strings = data[first_string:last_string]
    if strings[0] != 0 or strings[-1] != 0:
        raise ValueError('BTF string table boundary')

    def name(offset):
        if not 0 <= offset < len(strings):
            raise ValueError('BTF name offset')
        finish = strings.find(b'\0', offset)
        if finish < 0 or finish - offset > 4096:
            raise ValueError('BTF name length/terminator')
        return strings[offset:finish].decode('utf-8', errors='strict')

    types = [None]
    position = start
    while position < end:
        if position + 12 > end:
            raise ValueError('Truncated BTF common type')
        name_off, info, size_type = struct.unpack_from(endian + 'III', data, position)
        kind, count, flag = (info >> 24) & 31, info & 65535, info >> 31
        if info & 0x60ff0000:
            raise ValueError('Unsupported BTF info bits')
        if kind not in range(1, 20):
            raise ValueError('Unknown BTF kind')
        extra = {1: 4, 3: 12, 4: 12 * count, 5: 12 * count, 6: 8 * count,
                 13: 8 * count, 14: 4, 15: 12 * count, 17: 4, 19: 12 * count}.get(kind, 0)
        if position + 12 + extra > end:
            raise ValueError('Truncated BTF kind payload')
        members = []
        if kind in (4, 5):
            for index in range(count):
                member_name, member_type, member_offset = struct.unpack_from(endian + 'III', data, position + 12 + index * 12)
                members.append({'name': name(member_name), 'type_id': member_type,
                                'bit_offset': member_offset & 0xffffff if flag else member_offset,
                                'bitfield_width': member_offset >> 24 if flag else 0})
        integer = None
        if kind == 1:
            raw_int = struct.unpack_from(endian + 'I', data, position + 12)[0]
            integer = {'encoding': raw_int >> 24, 'offset': (raw_int >> 16) & 255, 'bits': raw_int & 255}
        types.append({'id': len(types), 'name': name(name_off), 'kind': kind,
                      'size_or_type': size_type, 'integer': integer, 'members': members})
        position += 12 + extra
    if position != end:
        raise ValueError('BTF type section tail')

    def resolve(type_id):
        visited = set()
        while True:
            if type_id in visited or not 0 < type_id < len(types):
                raise ValueError('Invalid/cyclic selected BTF type reference')
            visited.add(type_id)
            item = types[type_id]
            if item['kind'] not in (8, 9, 10, 11, 18):
                return {'id': type_id, 'name': item['name'], 'kind': item['kind'], 'integer': item['integer'],
                        'size_bytes': item['size_or_type'] if item['kind'] in (1, 4, 5, 6, 16, 19) else None}
            type_id = item['size_or_type']

    selected = []
    for item in types[1:]:
        if item['kind'] in (4, 5, 7) and item['name'] in ('inode', 'file', 'socket', 'socket_alloc'):
            selected.append({**item, 'members': [{**member, 'resolved_type': resolve(member['type_id'])} for member in item['members']]})
    return {'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data), 'endian': endian,
            'type_count': len(types) - 1, 'selected': selected,
            'scope': 'Selected running-kernel BTF metadata only; no generated offsets, memory read, attachment or kernel-path proof.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('path', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    with args.path.open('rb') as stream:
        data = stream.read(CAP + 1)
    result = inspect(data)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'selected'}))
    for item in result['selected']:
        print(item['name'], 'kind', item['kind'], 'size/type', item['size_or_type'],
              'inode fields', [m for m in item['members'] if m['name'] in ('i_ino', 'f_inode', 'vfs_inode')])
