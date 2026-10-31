#!/usr/bin/env python3
"""Recompute complete supplemental case batches; never primary acceptance."""
from __future__ import annotations

import argparse
from collections import Counter
import itertools
import json
from pathlib import Path
import re
import sys

import run_wamp_serializer_campaign as campaign
import wamp_serializer_compare as compare
import wamp_serializer_extensions as extensions

LOCKFILES = ('pubspec.lock', 'native/bench/Cargo.lock', 'native/transport/Cargo.lock')


def revision(value):
    if not isinstance(value, str) or not re.fullmatch(r'(?:[0-9a-f]{40}|[0-9a-f]{64})', value):
        raise ValueError('expected source must be a full Git revision')
    return value


def select_artifact_ids(pages, source):
    """Select newest whole artifacts; never splice sample rows across attempts."""
    revision(source)
    prefix = f'wamp-flatbuffers-primary-{source}-'
    pattern = re.compile(re.escape(prefix) + r'([1-9][0-9]*)-(' + '|'.join(
        re.escape(name) for name in extensions.SHARDS) + r')$')
    latest = {}
    seen = set()
    if not isinstance(pages, list):
        raise ValueError('artifact metadata must contain paginated API objects')
    for page in pages:
        if not isinstance(page, dict) or not isinstance(page.get('artifacts'), list):
            raise ValueError('invalid artifact metadata page')
        for artifact in page['artifacts']:
            if not isinstance(artifact, dict) or not isinstance(artifact.get('name'), str):
                raise ValueError('invalid artifact metadata entry')
            if not artifact['name'].startswith(prefix):
                continue
            match = pattern.fullmatch(artifact['name'])
            if match is None:
                raise ValueError('unexpected case-batch artifact name')
            attempt, shard = int(match[1]), match[2]
            if (attempt, shard) in seen:
                raise ValueError('duplicate case-batch artifact in one attempt')
            seen.add((attempt, shard))
            if type(artifact.get('id')) is not int or artifact['id'] <= 0:
                raise ValueError('invalid artifact id')
            if shard not in latest or attempt > latest[shard][0]:
                latest[shard] = (attempt, artifact)
    if set(latest) != set(extensions.SHARDS):
        raise ValueError('missing supplemental case-batch artifact')
    if any(item[1].get('expired') is not False for item in latest.values()):
        raise ValueError('latest case-batch artifact is expired or unverified')
    return [latest[shard][1]['id'] for shard in extensions.SHARDS]


def object_file(path):
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise ValueError(f'{path.name} must be a JSON object')
    return value


def within(root, path):
    path = path.resolve(strict=True)
    if not path.is_relative_to(root.resolve()):
        raise ValueError('evidence path escapes its case-batch directory')
    return path


def verify_inputs(root, manifest):
    metadata = manifest['metadata']
    expected = {'policy.json': metadata['policy_sha256'],
                'router_config.json': metadata['router_config_sha256']}
    locks = metadata['lockfiles_sha256']
    if not isinstance(locks, dict) or set(locks) != set(LOCKFILES):
        raise ValueError('case batch must retain every canonical lockfile')
    expected.update(locks)
    for name, digest in expected.items():
        if campaign.sha256(within(root, root / 'inputs' / name)) != digest:
            raise ValueError(f'input hash differs: {name}')
    if metadata['policy_sha256'] != campaign.sha256(campaign.POLICY):
        raise ValueError('case batch substituted the checked-in policy')
    if campaign.scenario_directory_hash(root / 'scenarios') != metadata['scenario_sha256']:
        raise ValueError('scenario hash differs')
    setup = root.parent / 'setup'
    for key, name in [('driver', 'http_stream'), ('native_library', 'libct_ffi.so')]:
        path = within(root.parent, setup / name)
        if campaign.sha256(path) != metadata['artifacts_sha256'][key]:
            raise ValueError(f'artifact hash differs: {key}')


def jsonl(path):
    with path.open() as stream:
        for line in stream:
            if line.strip():
                value = json.loads(line)
                if not isinstance(value, dict):
                    raise ValueError('raw report must be an object')
                yield value


def verify_raw_rows(root, manifest):
    runs = manifest['warmup_runs'] + manifest['measured_runs']
    paths = [within(root, root / run['results']) for run in runs]
    if len(set(paths)) != len(paths):
        raise ValueError('case-batch passes reuse a report file')
    actual = jsonl(within(root, root / 'driver-results.jsonl'))
    per_pass = itertools.chain.from_iterable(jsonl(path) for path in paths)
    counts = Counter()
    total = 0
    for raw, recorded in itertools.zip_longest(actual, per_pass):
        # Canonical JSON also distinguishes booleans from numeric counters.
        if raw is None or recorded is None or json.dumps(raw, sort_keys=True) != json.dumps(recorded, sort_keys=True):
            raise ValueError('driver stream differs from completed pass reports')
        counts[raw['workload']] += 1
        total += 1
    expected = {name: len(runs) for case in manifest['cases'] for name in case['workloads'].values()}
    if dict(counts) != expected:
        raise ValueError('raw rows do not cover every case/codec/pass exactly')
    return total


def merge(root, source):
    revision(source)
    policy = object_file(campaign.POLICY)
    findings, children, cases, numeric = [], {}, {}, []
    provenance = []
    common = schedule = None
    total_rows = 0
    for path in sorted(root.glob('*/campaign/manifest.json')):
        try:
            manifest = object_file(path)
            metadata = manifest['metadata']
            shard = metadata.get('diagnostic_shard')
            if not isinstance(shard, str) or shard not in extensions.SHARDS:
                raise ValueError('unknown or unscoped supplemental case batch')
            if shard in children:
                raise ValueError('duplicate supplemental case batch')
            children[shard] = True
            if metadata.get('campaign_kind') != 'extension_diagnostic' or metadata.get('source_revision') != source:
                raise ValueError('case batch has a different source or campaign scope')
            identity = {key: metadata[key] for key in (
                'source_revision', 'policy_sha256', 'router_config_sha256',
                'lockfiles_sha256', 'artifacts_sha256', 'resource_mode', 'worker_lifetime')}
            identity['toolchains'] = {key: metadata['platform'][key] for key in ('dart_version', 'rustc_version')}
            if common is not None and identity != common:
                raise ValueError('case batches have different inputs or toolchains')
            common = identity
            counts = (len(manifest['warmup_runs']), len(manifest['measured_runs']))
            if schedule is not None and counts != schedule:
                raise ValueError('case batches have different repetition counts')
            schedule = counts
            verify_inputs(path.parent, manifest)
            result = compare.evaluate_campaign(manifest, path.parent, policy)
            if result['status'] != 'diagnostic_shard_complete' or result['primary_acceptance_eligible']:
                raise ValueError('case-batch evidence failed validation: ' + '; '.join(result['findings']))
            if object_file(path.parent / 'comparison.json') != result:
                raise ValueError('stored case-batch comparison differs from raw recomputation')
            rows = verify_raw_rows(path.parent, manifest)
            additions = {}
            for case in result['cases']:
                if case['id'] in cases or case['id'] in additions:
                    raise ValueError('duplicate case across supplemental batches')
                additions[case['id']] = {**case, 'execution_shard': shard}
            artifact = path.parent.parent.name
            attempt = re.fullmatch(
                re.escape(f'wamp-flatbuffers-primary-{source}-') + r'([1-9][0-9]*)-' + re.escape(shard), artifact)
            evidence = {'name': shard, 'cases': result['case_count'],
                        'artifact_name': artifact,
                        'workflow_attempt': int(attempt[1]) if attempt else None,
                        'manifest': str(path.relative_to(root)),
                        'manifest_sha256': campaign.sha256(path),
                        'raw_reports_sha256': campaign.sha256(path.parent / 'driver-results.jsonl'),
                        'platform': metadata['platform'],
                        'process_pids': manifest['execution']['observed_process_pids']}
            # Commit a batch only after every input, raw-row and comparison check.
            cases.update(additions)
            total_rows += rows
            numeric.extend(result['performance_findings'])
            provenance.append(evidence)
        except (OSError, ValueError, KeyError, TypeError) as error:
            findings.append(f'{path.parent.parent.name}: {error}')
    expected = extensions.extension_cases()
    if set(children) != set(extensions.SHARDS):
        findings.append('missing required supplemental case batches')
    if set(cases) != {case['id'] for case in expected}:
        findings.append('case batches do not cover the complete disjoint declared inventory')
    if schedule is not None and total_rows != len(expected) * len(extensions.CODECS) * sum(schedule):
        findings.append('complete supplemental row count differs from the declared schedule')
    result = {'schema_version': 1, 'status': 'failed' if findings else 'diagnostic_complete',
              'primary_acceptance_eligible': False, 'source_manifest': 'manifest.json',
              'policy': policy, 'case_count': len(cases), 'row_count': total_rows,
              'findings': findings, 'performance_findings': numeric,
              'cross_shard_absolute_comparisons': 'not_comparable',
              'execution_shards': provenance,
              'cases': [cases[case['id']] for case in expected if case['id'] in cases]}
    manifest = {'schema_version': 1, 'campaign_kind': 'extension_aggregate',
                'source_revision': source, 'diagnostic_inventory': extensions.INVENTORY,
                'inputs': common, 'execution_shards': provenance,
                'row_count': total_rows, 'case_count': len(cases),
                'cross_shard_absolute_comparisons': 'not_comparable'}
    return result, manifest


def markdown(result):
    text = compare.render_markdown(result)
    scope = ('\nCases remain paired within one controlled runner. Absolute costs across batches '
             'are not comparable and are not pooled. All batches and evidence guards are required; '
             'this report never establishes primary acceptance.\n\n'
             '| Batch | Attempt | Cases | CPU | Client / server PID |\n|---|---:|---:|---|---|\n')
    for shard in result['execution_shards']:
        cpu = str(shard['platform']['cpu_model']).replace('|', '\\|').replace('\n', ' ')
        pids = shard['process_pids']
        scope += f"| {shard['name']} | {shard['workflow_attempt'] or 'local'} | {shard['cases']} | {cpu} | {pids['client_process_metrics']} / {pids['server_process_metrics']} |\n"
    first, rest = text.split('\n', 1)
    return first + '\n' + scope + rest


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    select = commands.add_parser('select-artifacts')
    select.add_argument('--metadata', type=Path, required=True)
    select.add_argument('--source', required=True)
    aggregate = commands.add_parser('merge')
    aggregate.add_argument('--root', type=Path, required=True)
    aggregate.add_argument('--source', required=True)
    aggregate.add_argument('--output', type=Path, required=True)
    aggregate.add_argument('--jobs-result', default='success')
    args = parser.parse_args(argv)
    try:
        if args.command == 'select-artifacts':
            ids = select_artifact_ids(json.loads(args.metadata.read_text()), args.source)
            print('artifact_ids=' + ','.join(str(value) for value in ids))
            return 0
        result, manifest = merge(args.root, args.source)
        if args.jobs_result != 'success':
            result['findings'].append('not every case-batch CI job succeeded')
            result['status'] = 'failed'
        args.output.mkdir(parents=True, exist_ok=False)
        for name, value in [('comparison.json', result), ('manifest.json', manifest)]:
            (args.output / name).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
        (args.output / 'comparison.md').write_text(markdown(result))
        print(f"Supplemental inventory {result['status']}: {result['case_count']} cases, {result['row_count']} rows")
        return 0 if result['status'] == 'diagnostic_complete' else 1
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f'Supplemental aggregation failed: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
