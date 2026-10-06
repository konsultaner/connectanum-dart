#!/usr/bin/env python3
"""Collect a complete native target inventory in a private source snapshot."""

import argparse
from contextlib import contextmanager, nullcontext
from dataclasses import asdict
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import threading
import time

import native_coverage
import native_mutations
import native_mutation_resources as resources
from run_dart_mutations import run


FIXTURES = ('native/bench/bench_tls.crt', 'native/bench/bench_tls.key')
TOOL_INPUTS = ('run_native_mutations.py', 'native_mutations.py',
               'native_coverage.py', 'run_dart_mutations.py', 'native_mutation_batches.py',
               'run_native_mutation_campaign.py', 'native_mutation_timing.py',
               'native_mutation_resources.py')
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


def native_sharding(inventory):
    # cargo-mutants 27.1.0 StructField discovery bypasses regex filters. Its
    # post-discovery sharding still assigns each candidate exactly once.
    return any(item.get('genre') == 'StructField' for item in inventory)


def inventory_matches(actual, expected, *, native_order=False):
    actual_ids = list(map(native_mutations.identity, actual))
    expected_ids = list(map(native_mutations.identity, expected))
    return actual_ids == expected_ids if native_order else sorted(actual_ids) == sorted(expected_ids)


def select_batch(inventory, index, count):
    if (type(index) is not int or type(count) is not int
            or not 0 <= index < count <= len(inventory)):
        raise ValueError('Require a nonempty batch with 0 <= index < count <= inventory size')
    names = [item['name'] for item in inventory]
    identities = [native_mutations.identity(item) for item in inventory]
    if len(set(names)) != len(names) or len(set(identities)) != len(identities):
        raise ValueError('Duplicate full inventory name or identity')
    ordered = inventory if native_sharding(inventory) else sorted(inventory, key=native_mutations.identity)
    return ordered[index::count]


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


def execution_fingerprint():
    environment = {key: value for key, value in os.environ.items()
                   if key.startswith(('CARGO_', 'RUST', 'CC', 'CXX', 'AR', 'LD'))}
    home = Path(os.environ.get('CARGO_HOME', Path.home() / '.cargo'))
    configs = {name: native_coverage.digest(home / name)
               for name in ('config', 'config.toml') if (home / name).is_file()}
    # Hash build configuration rather than retaining environment values, which
    # can contain registry credentials. Compiler identity is public metadata.
    configuration = json.dumps({'environment': environment, 'cargoHomeConfigs': configs}, sort_keys=True)
    return {'cargo': subprocess.check_output(['cargo', '--version'], text=True, timeout=10).strip(),
            'rustc': subprocess.check_output(['rustc', '--version', '--verbose'], text=True, timeout=10).strip(),
            'buildEnvironmentSha256': hashlib.sha256(configuration.encode()).hexdigest()}


def copy_private_input(source, destination):
    shutil.copy2(source, destination)
    # copy2/clonefile preserve stale times, making active scratch inputs eligible
    # for macOS dirhelper (and other age-based temp reapers). Keep bytes/mode,
    # not the source's age. Never touch the checkout or archived evidence.
    os.utime(destination, None)
    return destination


def copy_inputs(root, work, hashes):
    # Mutation writes must never follow a link back into the source checkout.
    shutil.copytree(root / 'native/transport', work / 'native/transport',
                    ignore=shutil.ignore_patterns('target', 'mutants.out*'), symlinks=False,
                    copy_function=copy_private_input)
    for relative in hashes:
        destination = work / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        copy_private_input(root / relative, destination)
    verify_inputs(work, hashes)
    verify_inputs(root, hashes)


def commands(work, output, target='core-rawsocket', exclusions=(), build_jobs=None):
    if build_jobs is not None and (type(build_jobs) is not int or build_jobs < 1):
        raise ValueError('Cargo build jobs must be a positive integer')
    source, test_filter = target_options(target)
    whole = target in WHOLE_COMPONENTS
    if exclusions and not whole:
        raise ValueError('Helper exclusions require a whole-component inventory')
    package = source.split('/')[0]
    # Whole-workspace protocol faults take ~111s across bounded serial failures.
    # Allow diagnostics to finish; panic/timeout evidence still cannot earn kills.
    test_timeout = '90' if target == 'core-protocol' else '30'
    if whole:
        test_timeout = '180'
    prefix = ['env', f'CARGO_TARGET_DIR={work / "target"}']
    if build_jobs is not None:
        prefix.append(f'CARGO_BUILD_JOBS={build_jobs}')
    manifest = str(work / 'native/transport/Cargo.toml')
    campaign = [*prefix, 'cargo', 'mutants', '--no-config', '--in-place',
                '--manifest-path', manifest, '--package', package,
                *([] if whole else ['--file', source]), '--features', 'ffi-test',
                '--test-workspace', 'false',
                '--timeout', test_timeout, '--build-timeout', '180',
                '--cargo-arg=--locked',
                # cargo-mutants 27.1.0 ignores test-workspace for its baseline.
                # Forward workspace selection to both phases without duplicating it.
                *(['--cargo-arg=--workspace'] if whole else []),
                '--output', str(output),
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
    if not inventory_matches(json.loads(filtered), partition['production'],
                             native_order=native_sharding(partition['production'])):
        raise RuntimeError('Filtered inventory differs from pinned production inventory')
    return partition


def collect(root, output, analyzer, target='core-rawsocket', batch=None, *,
            build_jobs=None, cancel_event=None, resource_limits=None):
    started = time.monotonic()
    target_options(target)
    if batch is not None and (target not in WHOLE_COMPONENTS or len(batch) != 2
            or any(type(item) is not int for item in batch)
            or not 0 <= batch[0] < batch[1]):
        raise ValueError('Batches require a whole component and valid zero-based index/count')
    output.mkdir(parents=True, exist_ok=False)
    scope = native_coverage.snapshot(root, native_coverage.ROOTS, analyzer)
    (output / 'source-scopes.json').write_text(json.dumps(scope, indent=2) + '\n')
    hashes = {**scope['inputHashes'], **{
        relative: native_coverage.digest(root / relative) for relative in FIXTURES}}
    tool_root = Path(__file__).resolve().parent
    tool_hashes = {name: native_coverage.digest(tool_root / name) for name in TOOL_INPUTS}
    manifest = {'complete': False, 'scope': target, 'inputHashes': hashes,
                'toolHashes': tool_hashes, 'executionFingerprint': execution_fingerprint(),
                'cargoMutantsVersion': subprocess.check_output(
                    ['cargo', 'mutants', '--version'], text=True).strip()}
    if resource_limits is not None:
        manifest['resourceLimits'] = asdict(resource_limits)
        cancel_event = cancel_event if cancel_event is not None else threading.Event()
    if manifest['cargoMutantsVersion'] != 'cargo-mutants 27.1.0':
        raise ValueError('Require cargo-mutants 27.1.0')
    manifest_path = output / 'run-manifest.json'

    def save():
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')

    def execute(command, timeout):
        if guard is not None:
            guard.check()
        if cancel_event is None:
            return run(command, work, timeout)
        return run(command, work, timeout, cancel_event=cancel_event)

    @contextmanager
    def workspace():
        with tempfile.TemporaryDirectory(prefix='connectanum-native-mutations-') as temporary:
            work = Path(temporary)
            observer = resources.DiskGuard(work, output, cancel_event, resource_limits) \
                if resource_limits is not None else nullcontext()
            try:
                with observer as guard:
                    yield work, guard
            finally:
                if resource_limits is not None:
                    for key, name in [('resourceSummarySha256', 'resource-summary.json'),
                                      ('resourceSamplesSha256', 'resources.jsonl')]:
                        if (output / name).is_file():
                            manifest[key] = native_coverage.digest(output / name)
                    save()

    save()
    with workspace() as (work, guard):
        copy_inputs(root, work, hashes)
        partition = prepare_inventory(work, output, scope, target) if target in WHOLE_COMPONENTS else None
        if partition is not None:
            verify_inputs(work, hashes)
            verify_inputs(root, hashes)
            manifest.update(rawInventorySha256=native_coverage.digest(output / 'raw-inventory.json'),
                            partitionSha256=native_coverage.digest(output / 'inventory-partition.json'),
                            filteredInventorySha256=native_coverage.digest(output / 'filtered-inventory.json'))
        campaign, restored = commands(work, output, target,
                                      partition['excluded'] if partition else (), build_jobs)
        expected_inventory = partition['production'] if partition else None
        if batch is not None:
            selected = select_batch(expected_inventory, *batch)
            if native_sharding(expected_inventory):
                selector = ['--shard', f'{batch[0]}/{batch[1]}', '--sharding', 'round-robin']
            else:
                expression = '^(?:' + '|'.join(re.escape(item['name']) for item in selected) + ')$'
                selector = ['--re', expression]
            campaign[campaign.index('--'):campaign.index('--')] = selector
            listed = subprocess.check_output(
                campaign[:campaign.index('--')] + ['--list', '--json'],
                cwd=work, text=True, timeout=120)
            selected_path = output / 'batch-inventory.json'
            selected_path.write_text(listed)
            if not inventory_matches(json.loads(listed), selected,
                                     native_order=native_sharding(expected_inventory)):
                raise RuntimeError('Selected batch differs from deterministic inventory partition')
            expected_inventory = selected
            manifest.update(batch={'index': batch[0], 'count': batch[1]},
                            batchInventorySha256=native_coverage.digest(selected_path))
        campaign_timeout = 86400 if target in WHOLE_COMPONENTS and batch is None else 14400
        manifest.update(campaignCommand=campaign, restoredCommand=restored)
        manifest['campaignTimeoutSeconds'] = campaign_timeout
        save()
        label = f'batch {batch[0]}/{batch[1]}' if batch is not None else 'complete inventory'
        print(f'Running isolated {target} mutation {label}.', flush=True)
        campaign_started = time.monotonic()
        code, log = execute(campaign, campaign_timeout)
        (output / 'campaign.log').write_text(log)
        manifest['campaignExitCode'] = code
        manifest['campaignSeconds'] = time.monotonic() - campaign_started
        save()
        if guard is not None:
            guard.check()
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
                    map(native_mutations.identity, expected_inventory)):
                raise RuntimeError('Executed inventory differs from pinned production inventory')
            if batch is not None and native_coverage.digest(output / 'batch-inventory.json') != manifest['batchInventorySha256']:
                raise RuntimeError('Pinned batch inventory changed during campaign')
        verify_inputs(work, hashes)
        verify_inputs(root, hashes)
        restored_started = time.monotonic()
        code, log = execute(restored, 180)
        (output / 'restored-baseline.log').write_text(log)
        manifest['restoredExitCode'] = code
        manifest['restoredSeconds'] = time.monotonic() - restored_started
        save()
        if guard is not None:
            guard.check()
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
        if execution_fingerprint() != manifest['executionFingerprint']:
            raise RuntimeError('Native execution configuration changed during collection')
        if guard is not None:
            # Settle the observer before committing completion. A final limit
            # violation must not leave an apparently reusable audited batch.
            guard.finish()
            guard.check()
        report.update(scopeSha256=native_coverage.digest(output / 'source-scopes.json'),
                      toolHashes=tool_hashes,
                      restoredBaselineLogSha256=native_coverage.digest(output / 'restored-baseline.log'))
        if batch is not None:
            report.update(batch=manifest['batch'], wholeComponentComplete=False)
        (output / 'audited-results.json').write_text(json.dumps(report, indent=2) + '\n')
        manifest.update(complete=True, evidenceClean=report['evidenceClean'],
                        elapsedSeconds=time.monotonic() - started)
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
    parser.add_argument('--batch', nargs=2, type=int, metavar=('INDEX', 'COUNT'),
                        help='Zero-based deterministic whole-component batch; retain each output separately')
    resources.add_arguments(parser)
    args = parser.parse_args()
    limits = resources.DiskLimits(args.disk_reserve_gib, args.max_cache_gib)
    if args.batch is not None:
        return collect(native_coverage.REPO, args.output.resolve(), args.analyzer.resolve(),
                       args.target, batch=args.batch, resource_limits=limits)
    return collect(native_coverage.REPO, args.output.resolve(), args.analyzer.resolve(), args.target,
                   resource_limits=limits)


if __name__ == '__main__':
    raise SystemExit(main())
