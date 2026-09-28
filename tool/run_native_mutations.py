#!/usr/bin/env python3
"""Collect a complete native target inventory in a private source snapshot."""

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

import native_coverage
import native_mutations
from run_dart_mutations import run


FIXTURES = ('native/bench/bench_tls.crt', 'native/bench/bench_tls.key')
TOOL_INPUTS = ('run_native_mutations.py', 'native_mutations.py',
               'native_coverage.py', 'run_dart_mutations.py')
TARGETS = {
    'core-rawsocket': ('ct_core/src/rawsocket.rs', 'rawsocket::tests'),
    'core-wamp': ('ct_core/src/wamp.rs', 'wamp::'),
    # Configuration influences every transport; use all core library tests.
    'core-config': ('ct_core/src/config.rs', ''),
    # Negotiation is exercised by transport integration tests as well as units.
    'core-protocol': ('ct_core/src/protocol.rs', ''),
    'core-all': ('ct_core/**', ''),
    'ffi-all': ('ct_ffi/**', ''),
}
WHOLE_COMPONENTS = frozenset(('core-all', 'ffi-all'))


def partition_inventory(inventory, scope):
    """Exclude only hash-pinned, AST-proven test helpers, retaining raw entries."""
    if not isinstance(inventory, list) or not inventory:
        raise ValueError('Require a nonempty raw native inventory')
    production, excluded, seen = [], [], set()
    for mutant in inventory:
        name = mutant['name']
        if name in seen:
            raise ValueError('Duplicate raw mutation name')
        seen.add(name)
        source = native_mutations.source_for(mutant['file'], scope)
        if source is None:
            raise ValueError('Mutant source missing from verified source scope')
        info = scope['sources'][source]
        span = {edge: [mutant['span'][edge]['line'], mutant['span'][edge]['column'] - 1]
                for edge in ('start', 'end')}
        if not (0 < span['start'][0] <= span['end'][0] <= info['lineCount']
                and span['start'][1] >= 0 and span['end'][1] >= 0
                and span['start'] <= span['end']):
            raise ValueError('Invalid mutation source span')
        if info['classification'] not in ('production-candidate', 'test-only'):
            raise ValueError('Unknown source classification')
        bodies = info.get('productionFunctionBodies', [])
        whole_body = info['classification'] == 'production-candidate' and (
            mutant.get('genre') == 'FnValue' and any(body['span'] == span for body in bodies))
        proofs = [item for item in info.get('exclusions', [])
                  if item['span']['start'] <= span['start']
                  and span['end'] <= item['span']['end']]
        if whole_body:
            if proofs:
                raise ValueError('Ambiguous production and test-only body')
            production.append(mutant)
            continue
        overlap = any(line in info['excludedLines']
                      for line in range(span['start'][0], span['end'][0] + 1)) or any(
            span['start'] < item['span']['end'] and item['span']['start'] < span['end']
            for item in info.get('exclusions', []))
        if info['classification'] == 'production-candidate' and not overlap:
            production.append(mutant)
            continue
        if not proofs and info['classification'] != 'test-only':
            raise ValueError('Unproved partial test/production overlap')
        digest = scope.get('inputHashes', {}).get(source, '')
        if not re.fullmatch(r'[0-9a-f]{64}', digest):
            raise ValueError('Missing source hash for helper exclusion')
        proof = proofs[0] if proofs else {'reason': 'AST test-only source', 'span': span}
        excluded.append({'mutant': mutant, 'source': source, 'sourceSha256': digest,
                         'reason': proof['reason'], 'span': proof['span']})
    if not production:
        raise ValueError('Require nonempty production mutation inventory')
    return {'production': production, 'excluded': excluded}


def target_options(target):
    if target not in TARGETS:
        raise ValueError(f'Unknown native mutation target: {target}')
    return TARGETS[target]


def verify_inputs(root, hashes):
    for relative, expected in hashes.items():
        if native_coverage.digest(root / relative) != expected:
            raise ValueError(f'Native snapshot input changed: {relative}')


def copy_inputs(root, work, hashes):
    # Mutation writes must never follow a link back into the source checkout.
    shutil.copytree(root / 'native/transport', work / 'native/transport',
                    ignore=shutil.ignore_patterns('target', 'mutants.out*'), symlinks=False)
    for relative in hashes:
        destination = work / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / relative, destination)
    verify_inputs(work, hashes)
    verify_inputs(root, hashes)


def commands(work, output, target='core-rawsocket', exclusions=()):
    source, test_filter = target_options(target)
    whole = target in WHOLE_COMPONENTS
    if exclusions and not whole:
        raise ValueError('Helper exclusions require a whole-component inventory')
    package = source.split('/')[0]
    # Protocol faults trigger multiple bounded network failures in the serial
    # suite (31-43 seconds observed); allow completion before auditing failures.
    test_timeout = '90' if whole or target == 'core-protocol' else '30'
    prefix = ['env', f'CARGO_TARGET_DIR={work / "target"}']
    manifest = str(work / 'native/transport/Cargo.toml')
    campaign = [*prefix, 'cargo', 'mutants', '--no-config', '--in-place',
                '--manifest-path', manifest, '--package', package,
                *([] if whole else ['--file', source]), '--features', 'ffi-test',
                '--test-workspace', 'true' if whole else 'false',
                '--timeout', test_timeout, '--build-timeout', '180',
                '--cargo-arg=--locked', '--output', str(output),
                *[arg for item in exclusions for arg in
                  ('--exclude-re', '^' + re.escape(item['mutant']['name']) + '$')],
                '--', *(['--all-targets', '--no-fail-fast', '--'] if whole else ['--lib', '--', test_filter]),
                '--test-threads=1']
    restored = [*prefix, 'cargo', 'test', '--manifest-path', manifest,
                '--locked', *(['--workspace'] if whole else ['--package', package]),
                '--features', 'ffi-test',
                *(['--all-targets', '--no-fail-fast', '--'] if whole else ['--lib', '--', test_filter]),
                '--test-threads=1']
    return campaign, restored


def prepare_inventory(work, output, scope, target):
    source, _ = target_options(target)
    command = ['cargo', 'mutants', '--no-config', '--manifest-path',
               str(work / 'native/transport/Cargo.toml'), '--package', source.split('/')[0],
               '--features', 'ffi-test', '--list', '--json']
    raw = subprocess.check_output(command, cwd=work, text=True, timeout=120)
    (output / 'raw-inventory.json').write_text(raw)
    partition = partition_inventory(json.loads(raw), scope)
    (output / 'inventory-partition.json').write_text(json.dumps(partition, indent=2) + '\n')
    campaign, _ = commands(work, output, target, partition['excluded'])
    filtered_command = campaign[:campaign.index('--')] + ['--list', '--json']
    filtered = subprocess.check_output(filtered_command, cwd=work, text=True, timeout=120)
    (output / 'filtered-inventory.json').write_text(filtered)
    if sorted(map(native_mutations.identity, json.loads(filtered))) != sorted(
            map(native_mutations.identity, partition['production'])):
        raise RuntimeError('Filtered inventory differs from pinned production inventory')
    return partition


def collect(root, output, analyzer, target='core-rawsocket'):
    target_options(target)
    output.mkdir(parents=True, exist_ok=False)
    scope = native_coverage.snapshot(root, native_coverage.ROOTS, analyzer)
    (output / 'source-scopes.json').write_text(json.dumps(scope, indent=2) + '\n')
    hashes = {**scope['inputHashes'], **{
        relative: native_coverage.digest(root / relative) for relative in FIXTURES}}
    tool_root = Path(__file__).resolve().parent
    tool_hashes = {name: native_coverage.digest(tool_root / name) for name in TOOL_INPUTS}
    manifest = {'complete': False, 'scope': target, 'inputHashes': hashes,
                'toolHashes': tool_hashes,
                'cargoMutantsVersion': subprocess.check_output(
                    ['cargo', 'mutants', '--version'], text=True).strip()}
    if manifest['cargoMutantsVersion'] != 'cargo-mutants 27.1.0':
        raise ValueError('Require cargo-mutants 27.1.0')
    manifest_path = output / 'run-manifest.json'

    def save():
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')

    save()
    with tempfile.TemporaryDirectory(prefix='connectanum-native-mutations-') as temporary:
        work = Path(temporary)
        copy_inputs(root, work, hashes)
        partition = prepare_inventory(work, output, scope, target) if target in WHOLE_COMPONENTS else None
        if partition is not None:
            verify_inputs(work, hashes)
            verify_inputs(root, hashes)
            manifest.update(rawInventorySha256=native_coverage.digest(output / 'raw-inventory.json'),
                            partitionSha256=native_coverage.digest(output / 'inventory-partition.json'),
                            filteredInventorySha256=native_coverage.digest(output / 'filtered-inventory.json'))
        campaign, restored = commands(work, output, target,
                                      partition['excluded'] if partition else ())
        campaign_timeout = 86400 if target in WHOLE_COMPONENTS else 14400
        manifest.update(campaignCommand=campaign, restoredCommand=restored)
        manifest['campaignTimeoutSeconds'] = campaign_timeout
        save()
        print(f'Running complete isolated {target} mutation inventory.', flush=True)
        code, log = run(campaign, work, campaign_timeout)
        (output / 'campaign.log').write_text(log)
        manifest['campaignExitCode'] = code
        save()
        if code is None or 'connectanumInfrastructureError' in log:
            raise RuntimeError('Native campaign timed out or left unresolved process state')
        if partition is not None:
            for key, filename in [('rawInventorySha256', 'raw-inventory.json'),
                                  ('partitionSha256', 'inventory-partition.json'),
                                  ('filteredInventorySha256', 'filtered-inventory.json')]:
                if native_coverage.digest(output / filename) != manifest[key]:
                    raise RuntimeError('Pinned inventory evidence changed during campaign')
            actual = json.loads((output / 'mutants.out/mutants.json').read_text())
            if sorted(map(native_mutations.identity, actual)) != sorted(
                    map(native_mutations.identity, partition['production'])):
                raise RuntimeError('Executed inventory differs from pinned production inventory')
        verify_inputs(work, hashes)
        verify_inputs(root, hashes)
        code, log = run(restored, work, 180)
        (output / 'restored-baseline.log').write_text(log)
        manifest['restoredExitCode'] = code
        save()
        evidence = {'phase_results': [
            {'phase': 'Build', 'process_status': 'Success'},
            {'phase': 'Test', 'process_status': 'Success' if code == 0 else {'Failure': code}}]}
        if code != 0 or 'connectanumInfrastructureError' in log or native_mutations.classify(
                evidence, log, scope, None) != 'survived':
            raise RuntimeError('Restored native baseline did not finish cleanly')
        verify_inputs(work, hashes)
        verify_inputs(root, hashes)
        report = native_mutations.audit(output / 'mutants.out', scope)
        if sorted(name for name, _ in native_mutations.TEST.findall(log)) != report['baselineTests']:
            raise RuntimeError('Restored baseline did not run the original test inventory')
        verify_inputs(work, hashes)
        verify_inputs(root, hashes)
        verify_inputs(tool_root, tool_hashes)
        report.update(scopeSha256=native_coverage.digest(output / 'source-scopes.json'),
                      toolHashes=tool_hashes,
                      restoredBaselineLogSha256=native_coverage.digest(output / 'restored-baseline.log'))
        (output / 'audited-results.json').write_text(json.dumps(report, indent=2) + '\n')
        manifest.update(complete=True, evidenceClean=report['evidenceClean'])
        save()
        print(json.dumps({'counts': report['counts'], 'evidenceClean': report['evidenceClean']}))
        # Preserve the diagnostic workflow's fail-on-survivor behavior. No
        # platform-active 95% gate is claimed by this candidate inventory.
        return 0 if report['evidenceClean'] and not report['counts'].get('survived', 0) else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--analyzer', type=Path, required=True)
    parser.add_argument('--target', choices=tuple(TARGETS), default='core-rawsocket')
    args = parser.parse_args()
    return collect(native_coverage.REPO, args.output.resolve(), args.analyzer.resolve(), args.target)


if __name__ == '__main__':
    raise SystemExit(main())
