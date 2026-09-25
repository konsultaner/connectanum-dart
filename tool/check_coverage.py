#!/usr/bin/env python3
"""Merge LCOV by source/line and enforce measured floors without rounding."""

import argparse
import json
import math
from fractions import Fraction
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_SCOPES = {'library': ('lib',), 'packaging': ('bin', 'hook', 'tool'),
                 'application': ('lib', 'bin')}
APPLICATION_COMPONENTS = ('shared', 'server', 'client')


def read_lcov(paths, scope='library'):
    directories = SOURCE_SCOPES[scope]
    sources = {}
    for path in paths:
        current = None
        for line in path.read_text().splitlines():
            if line.startswith('SF:'):
                current = line[3:].replace('\\', '/')
                if current.startswith('/') or current[1:3] == ':/':
                    marker = '/examples/wamp_app/' if scope == 'application' else '/packages/'
                    if marker not in current:
                        current = None
                        continue
                    current = marker.lstrip('/') + current.split(marker, 1)[1]
                parts = current.split('/')
                if scope == 'application':
                    in_scope = (len(parts) >= 5 and parts[:2] == ['examples', 'wamp_app']
                                and parts[2] in APPLICATION_COMPONENTS and parts[3] in directories)
                else:
                    in_scope = len(parts) >= 4 and parts[0] == 'packages' and parts[2] in directories
                if not (in_scope and current.endswith('.dart')
                        and not any(part in ('', '.', '..') for part in parts)):
                    current = None
                    continue
                sources.setdefault(current, {})
            elif line.startswith('DA:') and current:
                number, hits, *_ = line[3:].split(',')
                number, hits = int(number), int(hits)
                if number <= 0 or hits < 0:
                    raise ValueError('Invalid LCOV line/count')
                sources[current][number] = max(sources[current].get(number, 0), hits)
            elif line == 'end_of_record':
                current = None
    return sources


def stats(lines):
    total = len(lines)
    covered = sum(hits > 0 for hits in lines.values())
    return {'covered': covered, 'total': total, 'percent': 100 * covered / total if total else None}


def report(sources, root, runtime='vm', scope='library'):
    files = {name: {**stats(lines), 'uncovered': sorted(n for n, hits in lines.items() if hits == 0)}
             for name, lines in sorted(sources.items())}
    package_lines = {}
    for name, lines in sources.items():
        package = name.split('/')[2 if scope == 'application' else 1]
        package_lines.setdefault(package, {}).update({(name, n): hits for n, hits in lines.items()})
    measured = {name for name, lines in sources.items() if lines}
    if scope == 'application':
        inventory = (path for component in APPLICATION_COMPONENTS
                     for directory in SOURCE_SCOPES[scope]
                     for path in (root / 'examples/wamp_app' / component).glob(f'{directory}/**/*.dart'))
        unmeasured_scopes = ['Rust', 'package libraries', 'package hooks/executables']
    else:
        inventory = (path for directory in SOURCE_SCOPES[scope]
                     for path in (root / 'packages').glob(f'*/{directory}/**/*.dart'))
        unmeasured_scopes = ['Rust', 'hooks/executables' if scope == 'library' else 'package libraries',
                             'standalone applications']
    unmeasured = sorted(path.relative_to(root).as_posix() for path in inventory
                        if path.relative_to(root).as_posix() not in measured)
    return {'schemaVersion': 1, 'measurement': f'Dart {runtime} executable lines in LCOV',
            'sourceScope': scope,
            'packages': {name: stats(lines) for name, lines in sorted(package_lines.items())},
            'overall': stats({(name, n): h for name, lines in sources.items() for n, h in lines.items()}),
            'files': files, 'unmeasuredSources': unmeasured,
            'unmeasuredScopes': unmeasured_scopes
             + (['browser-only code'] if runtime == 'vm' else ['unselected browser/VM suites'])}


def component_stats(result, definitions):
    components = {}
    for name, definition in definitions.items():
        sources = definition.get('sources')
        floor = definition.get('floor')
        if (not isinstance(sources, list) or not sources
                or not all(isinstance(source, str) and source for source in sources)
                or len(set(sources)) != len(sources)
                or isinstance(floor, bool) or not isinstance(floor, (int, float))
                or not math.isfinite(floor) or not 0 <= floor <= 100):
            raise ValueError(f'{name}: invalid component sources or floor')
        measured = [result['files'].get(source, {}) for source in sources]
        total = sum(item.get('total', 0) for item in measured)
        covered = sum(item.get('covered', 0) for item in measured)
        components[name] = {
            'sources': sources, 'floor': floor, 'covered': covered, 'total': total,
            'percent': 100 * covered / total if total else None,
            'missingSources': [source for source, item in zip(sources, measured) if not item.get('total')],
        }
    return components


def findings(result, policy, require_target=False):
    problems = []
    if policy.get('sourceScope', 'library') != result.get('sourceScope', 'library'):
        problems.append(f'Coverage source scope {result.get("sourceScope")} '
                        f'does not match policy {policy.get("sourceScope", "library")}')
    for name in policy.get('requiredSources', []):
        if not result['files'].get(name, {}).get('total'):
            problems.append(f'{name}: previously measured source missing from coverage')
    for section in ('packages', 'files'):
        for name, floor in policy.get(section, {}).items():
            threshold = policy['target'] if require_target else floor
            item = result[section].get(name)
            if item is None or not item['total']:
                problems.append(f'{name}: no executable coverage data')
            elif item['covered'] * 100 < Fraction(str(threshold)) * item['total']:
                problems.append(f'{name}: {item["percent"]:.3f}% below {threshold}%')
    for name, item in component_stats(result, policy.get('components', {})).items():
        threshold = policy['target'] if require_target else policy['components'][name]['floor']
        for source in item['missingSources']:
            problems.append(f'{name}: missing executable coverage for {source}')
        if not item['total']:
            problems.append(f'{name}: no executable coverage data')
        elif item['covered'] * 100 < Fraction(str(threshold)) * item['total']:
            problems.append(f'{name}: {item["percent"]:.3f}% below {threshold}%')
    for package in policy.get('componentPackages', []):
        if not result['packages'].get(package, {}).get('total'):
            problems.append(f'{package}: no executable coverage data')
        prefix = (f'examples/wamp_app/{package}/' if result.get('sourceScope') == 'application'
                  else f'packages/{package}/')
        for source, item in result['files'].items():
            if source.startswith(prefix) and item['total']:
                owners = sum(source in definition['sources']
                             for definition in policy.get('components', {}).values())
                if owners != 1:
                    problems.append(f'{source}: expected exactly one component, found {owners}')
    if require_target:
        for name, item in result['files'].items():
            if item['total'] and item['covered'] * 100 < Fraction(str(policy['target'])) * item['total']:
                problem = f'{name}: {item["percent"]:.3f}% below {policy["target"]}%'
                if problem not in problems:
                    problems.append(problem)
        if result['unmeasuredSources']:
            problems.append(f'{len(result["unmeasuredSources"])} sources lack executable coverage; classify declarations separately before claiming completeness')
        if result['unmeasuredScopes']:
            problems.append('Unmeasured runtimes/scopes: ' + ', '.join(result['unmeasuredScopes']))
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('lcov', type=Path, nargs='+')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--policy', type=Path, required=True)
    parser.add_argument('--require-target', action='store_true')
    parser.add_argument('--runtime', choices=['vm', 'chrome', 'combined'], default='vm')
    parser.add_argument('--scope', choices=SOURCE_SCOPES, default='library')
    args = parser.parse_args()
    result = report(read_lcov(args.lcov, args.scope), ROOT, args.runtime, args.scope)
    policy = json.loads(args.policy.read_text())
    result['components'] = component_stats(result, policy.get('components', {}))
    problems = findings(result, policy, args.require_target)
    result.update({'target': policy['target'], 'findings': problems})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    for name, item in result['packages'].items():
        percent = f'{item["percent"]:.3f}%' if item['percent'] is not None else 'unmeasured'
        print(f'{name}: {percent} ({item["covered"]}/{item["total"]})')
    for name, item in result['components'].items():
        percent = f'{item["percent"]:.3f}%' if item['percent'] is not None else 'unmeasured'
        print(f'Component {name}: {percent} ({item["covered"]}/{item["total"]})')
    print(f'Unmeasured {args.scope} source files: {len(result["unmeasuredSources"])}')
    for problem in problems:
        print('FAIL: ' + problem)
    return int(bool(problems))


if __name__ == '__main__':
    raise SystemExit(main())
