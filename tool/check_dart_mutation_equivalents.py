#!/usr/bin/env python3
"""Reject stale source-bound mutation proofs before expensive verification."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from run_dart_mutations import (
    ROOT, select_mutations, unique_json_object, validate_equivalents, validate_sources,
)


def validate_current_proofs(root, config, equivalents, generate=None):
    if not isinstance(config, dict) or not config or not isinstance(equivalents, dict):
        raise ValueError('mutation configuration and proofs must be mappings')
    active = {}
    for name, entries in equivalents.items():
        if name not in config:
            continue
        if not isinstance(entries, dict):
            raise ValueError(f'{name}: equivalent proofs must be a mapping')
        if entries:
            active[name] = entries
    sources = set()
    for name, entries in active.items():
        if not isinstance(entries, dict):
            raise ValueError(f'{name}: equivalent proofs must be a mapping')
        target_sources = config[name].get('sources')
        validate_sources(target_sources)
        sources.update(target_sources)
    if not active:
        return {'targets': 0, 'proofs': 0, 'sources': 0}
    hashes = {source: hashlib.sha256((root / source).read_bytes()).hexdigest()
              for source in sorted(sources)}
    for name, entries in active.items():
        target_hashes = {hashes[source] for source in config[name]['sources']}
        for identifier, entry in entries.items():
            if not isinstance(entry, dict) or entry.get('sourceHash') not in target_hashes:
                raise ValueError(f'{name}: Stale equivalent-mutation justification: {identifier}')
    if generate is None:
        def generate(paths):
            result = subprocess.run(
                ['dart', 'tool/dart_mutations.dart', *paths], cwd=root,
                capture_output=True, text=True, timeout=60, check=True,
            )
            return json.loads(result.stdout, object_pairs_hook=unique_json_object)
    mutations = generate(sorted(sources))
    if not isinstance(mutations, list) or any(not isinstance(item, dict) for item in mutations):
        raise ValueError('mutation generator must return an inventory of mappings')
    proofs = 0
    for name, entries in active.items():
        target = config[name]
        inventory = [mutation for mutation in mutations if mutation['file'] in target['sources']]
        selected, _ = select_mutations(inventory, target)
        validate_equivalents(entries, selected, hashes)
        proofs += len(entries)
    return {'targets': len(active), 'proofs': proofs, 'sources': len(sources)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=ROOT / 'tool/mutation_targets.json')
    parser.add_argument('--equivalents', type=Path, default=ROOT / 'tool/mutation_equivalents.json')
    args = parser.parse_args(argv)
    try:
        config = json.loads(args.config.read_text(), object_pairs_hook=unique_json_object)
        equivalents = json.loads(args.equivalents.read_text(), object_pairs_hook=unique_json_object)
        result = validate_current_proofs(ROOT, config, equivalents)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f'Mutation proof preflight failed: {error}', file=sys.stderr)
        return 1
    print(f"Validated {result['proofs']} mutation proofs across {result['targets']} targets "
          f"and {result['sources']} source files")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
