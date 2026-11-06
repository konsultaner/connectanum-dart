#!/usr/bin/env python3
"""Require complete gateway sources and every changed shared executable line."""
import argparse
import json
from pathlib import Path
import re
import subprocess

from check_coverage import ROOT, read_lcov

WHOLE = (
    'packages/connectanum_client/lib/src/mqtt/qos0_client.dart',
    'packages/connectanum_router/lib/src/mqtt/gateway_policy.dart',
    'packages/connectanum_router/lib/src/router/router_instance/router_mqtt.dart',
    'packages/connectanum_bench/lib/src/mqtt_gateway_measurement.dart',
    'packages/connectanum_bench/lib/src/mqtt_gateway_worker.dart',
    'packages/connectanum_bench/bin/mqtt_gateway_worker.dart',
)
SHARED = (
    'packages/connectanum_client/lib/src/protocol/session.dart',
    'packages/connectanum_core/lib/src/serializer/flatbuffers/serializer.dart',
    'packages/connectanum_core/lib/src/serializer/flatbuffers/message_writer.dart',
    'packages/connectanum_core/lib/src/serializer/flatbuffers/wire_writer.dart',
    'packages/connectanum_core/lib/src/serializer/flatbuffers/cbor_encoding.dart',
    'packages/connectanum_core/lib/src/serializer/cbor/serializer.dart',
    'packages/connectanum_router/lib/src/router/router_instance/router_worker.dart',
    'packages/connectanum_router/lib/src/native/runtime.dart',
    'packages/connectanum_client/lib/src/transport/native/message_binding.dart',
    'packages/connectanum_client/lib/src/transport/native/native_transports_io.dart',
    'packages/connectanum_router/lib/src/router/router_instance/router_binding.dart',
    'packages/connectanum_router/lib/src/router/router_instance/router_boss.dart',
    'packages/connectanum_router/lib/src/router/router_instance/router_internal_session.dart',
    'packages/connectanum_router/lib/src/router/router_instance/router_worker_session.dart',
    'packages/connectanum_router/lib/src/router/state/commands.dart',
    'packages/connectanum_router/lib/src/router/state/store.dart',
)
PYTHON_SOURCES = {'tool/check_ci_needs.py', 'tool/run_mqtt_gateway_benchmark.py', 'tool/mqtt_gateway_paho_peer.py',
                  'tool/mqtt_gateway_reference_server.py', 'tool/check_mqtt_gateway_coverage.py'}


def require_python_coverage(report_path):
    files = json.loads(Path(report_path).read_text()).get('files', {})
    if set(files) != PYTHON_SOURCES or any(
        row.get('summary', {}).get('num_statements', 0) <= 0 or
        row['summary'].get('missing_lines') != 0 or row['summary'].get('excluded_lines') != 0
        for row in files.values()
    ):
        raise ValueError('Gateway tooling requires exact 100% coverage with zero exclusions')
    return sum(row['summary']['num_statements'] for row in files.values())


def added_lines(patch):
    files = {}
    current, position = None, None
    for line in patch.splitlines():
        if line.startswith('+++ '):
            current = line[6:] if line.startswith('+++ b/') else None
            position = None
        elif line.startswith('@@ '):
            match = re.match(r'@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@', line)
            if match is None or current is None:
                raise ValueError('Malformed Git coverage diff')
            position = int(match[1])
        elif position is not None:
            if line.startswith('+'):
                files.setdefault(current, set()).add(position)
                position += 1
            elif line.startswith(' '):
                position += 1
    return files


def check(sources, patch):
    changed = added_lines(patch)
    files = {}
    for name in (*WHOLE, *[name for name in SHARED if name in changed]):
        measured = sources.get(name)
        if not measured:
            files[name] = dict(missing=True, covered=0, total=0, uncovered=[])
            continue
        selected = measured if name in WHOLE else {line: hits for line, hits in measured.items() if line in changed[name]}
        uncovered = sorted(line for line, hits in selected.items() if not hits)
        files[name] = dict(missing=False, covered=len(selected)-len(uncovered),
                           total=len(selected), uncovered=uncovered)
    return dict(passed=all(not row['missing'] and not row['uncovered'] for row in files.values()),
                covered=sum(row['covered'] for row in files.values()),
                total=sum(row['total'] for row in files.values()), files=files)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('lcov', nargs='+', type=Path)
    parser.add_argument('--base', default='HEAD')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args(argv)
    sources = read_lcov(args.lcov)
    sources.update(read_lcov(args.lcov, scope='packaging'))
    patch = subprocess.check_output(['git', 'diff', '--no-ext-diff', '--unified=0',
                                     args.base, '--', *SHARED], cwd=ROOT, text=True)
    result = dict(check(sources, patch), source_base=args.base)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2)+'\n')
    print(f"Gateway coverage: {result['covered']}/{result['total']} executable lines")
    for name, row in result['files'].items():
        if row['missing'] or row['uncovered']:
            print(f"{name}: {'missing compiler coverage' if row['missing'] else row['uncovered']}")
    return int(not result['passed'])


if __name__ == '__main__':
    raise SystemExit(main())
