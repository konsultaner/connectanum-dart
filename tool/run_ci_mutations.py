#!/usr/bin/env python3
"""Run grouped complete targets after a single workspace bootstrap."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--group', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    groups = json.loads((ROOT / 'tool/ci_mutation_groups.json').read_text())
    if args.group not in groups:
        parser.error('Unknown CI mutation group')
    # One runner snapshots/resolves once, yet inventories and scores each target.
    command = [str(ROOT / 'bin/test-mutations'), '--output', str(args.output)]
    for target in groups[args.group]:
        command += ['--target', target]
    return subprocess.run(command, cwd=ROOT).returncode


if __name__ == '__main__':
    raise SystemExit(main())
