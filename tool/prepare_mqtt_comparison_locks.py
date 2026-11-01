#!/usr/bin/env python3
"""Restore exact candidate-evidence locks for a controlled broker comparison."""
import argparse
import hashlib
import json
from pathlib import Path

LOCKS = ('pubspec.lock', 'native/transport/Cargo.lock', 'native/bench/Cargo.lock')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def restore(evidence, expected, roots):
    evidence = evidence.resolve()
    matches = list(evidence.rglob('wamp-native-ppt-copy-proof/inputs.json'))
    if len(matches) != 1:
        raise ValueError('expected exactly one candidate owned-copy input receipt')
    path = matches[0]
    inputs = json.loads(path.read_text())
    result = json.loads(path.with_name('result.json').read_text())
    if inputs['head'] != expected or result['head'] != expected:
        raise ValueError('lock evidence belongs to another source')
    if not result['source_inputs_unchanged'] or not result['binaries_unchanged']:
        raise ValueError('candidate input/binary guards failed')
    observed = {}
    for name in LOCKS:
        retained = list(path.parent.glob(f'*/campaign/inputs/{name}'))
        if not retained:
            raise ValueError('missing retained canonical lock: ' + name)
        expected_hash = inputs['source_inputs'][name]
        for copy in retained:
            if not copy.resolve(strict=True).is_relative_to(evidence):
                raise ValueError('retained lock escapes its artifact')
            if sha(copy) != expected_hash:
                raise ValueError('retained lock hash differs: ' + name)
        observed[name] = expected_hash
        for root in roots:
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(retained[0].read_bytes())
    return observed


def verify(roots, hashes):
    for root in roots:
        for name, digest in hashes.items():
            if sha(root / name) != digest:
                raise ValueError('bootstrap changed canonical lock: ' + name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--candidate-ref', required=True)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--receipt', type=Path, required=True)
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    roots = (args.baseline.resolve(), args.candidate.resolve())
    if args.verify:
        receipt = json.loads(args.receipt.read_text())
        if receipt['source'] != args.candidate_ref:
            raise ValueError('lock receipt source differs')
        verify(roots, receipt['lock_hashes'])
    else:
        hashes = restore(args.evidence, args.candidate_ref, roots)
        args.receipt.write_text(json.dumps({
            'source': args.candidate_ref, 'lock_hashes': hashes,
            'scope': 'Exact candidate copy-evidence locks, not regenerated substitutes',
        }, indent=2) + '\n')


if __name__ == '__main__':
    main()
