#!/usr/bin/env python3
"""Collect a complete native target inventory in a private source snapshot."""

import argparse
import json
from pathlib import Path
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
}


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
    for relative in FIXTURES:
        destination = work / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / relative, destination)
    verify_inputs(work, hashes)
    verify_inputs(root, hashes)


def commands(work, output, target='core-rawsocket'):
    source, test_filter = target_options(target)
    prefix = ['env', f'CARGO_TARGET_DIR={work / "target"}']
    manifest = str(work / 'native/transport/Cargo.toml')
    campaign = [*prefix, 'cargo', 'mutants', '--no-config', '--in-place',
                '--manifest-path', manifest, '--package', 'ct_core',
                '--file', source, '--features', 'ffi-test',
                '--test-workspace', 'false', '--timeout', '30', '--build-timeout', '180',
                '--cargo-arg=--locked', '--output', str(output),
                '--', '--lib', '--', test_filter, '--test-threads=1']
    restored = [*prefix, 'cargo', 'test', '--manifest-path', manifest,
                '--locked', '--package', 'ct_core', '--features', 'ffi-test',
                '--lib', '--', test_filter, '--test-threads=1']
    return campaign, restored


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
        campaign, restored = commands(work, output, target)
        manifest.update(campaignCommand=campaign, restoredCommand=restored)
        save()
        print(f'Running complete isolated {target} mutation inventory.', flush=True)
        code, log = run(campaign, work, 14400)
        (output / 'campaign.log').write_text(log)
        manifest['campaignExitCode'] = code
        save()
        if code is None or 'connectanumInfrastructureError' in log:
            raise RuntimeError('Native campaign timed out or left unresolved process state')
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
