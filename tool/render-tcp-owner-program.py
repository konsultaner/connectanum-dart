"""Derive a private old-bpftrace field workaround from actual complete BTF."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json

spec = importlib.util.spec_from_file_location('selected_live_btf', Path(__file__).with_name('inspect-btf-types.py'))
btf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(btf)


def render(data, template):
    result = btf.inspect(data)
    if result['endian'] != '<':
        raise ValueError('Private probe supports only the recorded little-endian x86-64 host')
    candidates = [item for item in result['selected'] if item['name'] == 'inode' and item['kind'] == 4]
    if len(candidates) != 1:
        raise ValueError('Need one unambiguous complete live inode type')
    inode = candidates[0]
    fields = [member for member in inode['members'] if member['name'] == 'i_ino']
    if len(fields) != 1:
        raise ValueError('Need one actual live inode-number field')
    field = fields[0]
    integer = field['resolved_type']
    offset = field['bit_offset'] // 8
    if not (field['bit_offset'] % 64 == 0 and field['bitfield_width'] == 0
            and integer['kind'] == 1 and integer['size_bytes'] == 8
            and integer['integer'] == {'encoding': 0, 'offset': 0, 'bits': 64}
            and 0 < offset <= 4096 and offset + 8 <= inode['size_or_type']):
        raise ValueError('Unsupported live inode-number field layout')
    expression = '$sk->sk_socket->file->f_inode->i_ino'
    if template.count(expression) != 3 or 'struct ct_probe_inode' in template:
        raise ValueError('Unexpected fixed probe template')
    # This prefix is generated from this running kernel's BTF, never guessed.
    # Eight-byte alignment above makes the C member offset exactly the BTF offset.
    declaration = ('struct ct_probe_inode {\n'
                   f'  char observed_prefix[{offset}];\n'
                   '  unsigned long long observed_ino;\n'
                   '};\n')
    source = template.replace(expression, '((struct ct_probe_inode *)$sk->sk_socket->file->f_inode)->observed_ino')
    source = declaration + '\n' + source
    source = '// Complete running-kernel BTF SHA256: ' + result['sha256'] + '\n' + source
    evidence = {'btf_sha256': result['sha256'], 'btf_bytes': result['bytes'],
                'inode_type_id': inode['id'], 'inode_size': inode['size_or_type'],
                'verified_field': field, 'generated_prefix_bytes': offset,
                'program_sha256': hashlib.sha256(source.encode()).hexdigest(),
                'scope': 'Private generated read-only field access; still requires compile/attach/lifecycle smoke. No kernel-path claim.'}
    return source, evidence


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--btf', type=Path, required=True)
    parser.add_argument('--template', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    with args.btf.open('rb') as stream:
        data = stream.read(btf.CAP + 1)
    source, evidence = render(data, args.template.read_text())
    args.output.write_text(source)
    args.output.with_suffix('.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps(evidence))
