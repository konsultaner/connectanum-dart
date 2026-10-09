#!/usr/bin/env python3
"""Score a complete, independently inventoried union of Dart mutation shards."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import shutil
import sys

import run_dart_mutations as runner

PROVENANCE = ('schemaVersion', 'scope', 'runnerSha256', 'configSha256',
              'equivalentsSha256', 'commit', 'operatorScope', 'executionTimeoutSeconds')
TARGET_PROVENANCE = ('sources', 'tests', 'generated', 'selected', 'platform', 'testRunner',
                     'compiler', 'sourceHashes', 'testHashes', 'supportHashes', 'resolvedTests',
                     'mutationLineRanges', 'testName', 'equivalenceReasons', 'testCommands')


def merge(paths, expected, count):
    if len(paths) != count or count < 1 or len(expected['scope']) != 1:
        raise ValueError('Expected exactly one report per shard and one target')
    name = expected['scope'][0]
    inventory = expected['targets'][name]['inventory']
    expected_by_id = {runner.mutation_id(item): item for item in inventory}
    if len(expected_by_id) != len(inventory):
        raise ValueError('Duplicate full-inventory mutation IDs')
    outcomes = {}
    baseline_evidence = []
    seen = set()
    for path in paths:
        report = json.loads(path.read_text(), object_pairs_hook=runner.unique_json_object)
        if any(report.get(key) != expected.get(key) for key in PROVENANCE):
            raise ValueError('Shard provenance differs from independently generated inventory')
        shard = report.get('shard', {})
        index = shard.get('index')
        if (type(index) is not int or index in seen or not 0 <= index < count
                or shard.get('count') != count or not report.get('shardComplete')
                or report.get('complete') or report.get('baselineOnly')
                or report.get('gate') != expected['gate']
                or set(report.get('targets', {})) != {name}):
            raise ValueError('Missing, duplicate, incomplete or incompatible shard')
        seen.add(index)
        target = report['targets'][name]
        reference = expected['targets'][name]
        if (any(target.get(key) != reference.get(key) for key in TARGET_PROVENANCE)
                or target.get('inventory') != inventory):
            raise ValueError('Shard test/source/inventory identity differs')
        assigned = runner.partition_mutations(inventory, index, count)
        if target.get('assigned') != len(assigned) or len(target['outcomes']) != len(assigned):
            raise ValueError('Incomplete shard outcomes')
        assigned_ids = {runner.mutation_id(item) for item in assigned}
        observed = set()
        for outcome in target['outcomes']:
            identifier = outcome['id']
            if identifier in outcomes or identifier not in assigned_ids:
                raise ValueError('Duplicate or incorrectly assigned outcome')
            if any(outcome.get(key) != value for key, value in expected_by_id[identifier].items()):
                raise ValueError('Outcome mutation differs from inventory')
            if outcome.get('equivalence') != reference.get('equivalenceReasons', {}).get(identifier):
                raise ValueError('Outcome equivalence justification differs')
            if not outcome.get('mutationInputUnchanged'):
                raise ValueError('Applied mutation was overwritten')
            log_name = outcome['log']
            if Path(log_name).name != log_name:
                raise ValueError('Invalid outcome log path')
            log = path.parent / log_name
            if hashlib.sha256(log.read_bytes()).hexdigest() != outcome.get('logSha256'):
                raise ValueError('Mutation evidence digest mismatch')
            output = log.read_text()
            # Isolated test commands return the first nonpassing classification.
            # Recheck the final command rather than conflating reporter IDs.
            commands = output.split('\n' + '{"type": "connectanumTestCommand"')
            last_output = output if len(commands) == 1 else '{"type": "connectanumTestCommand"' + commands[-1]
            if runner.classify(outcome.get('exitCode'), last_output) != outcome['status']:
                raise ValueError('Mutation status differs from completed test evidence')
            if runner.kill_evidence(outcome['status'], output) != outcome.get('killEvidence'):
                raise ValueError('Mutation assertion evidence differs from raw log')
            outcomes[identifier] = outcome
            observed.add(identifier)
        if observed != assigned_ids:
            raise ValueError('Shard does not cover its assigned inventory')
        for baseline in ('baseline', 'restoredBaseline'):
            log = path.parent / f'{name}-{ "baseline" if baseline == "baseline" else "restored-baseline"}.log'
            if (target.get(baseline) != 'survived' or target.get(baseline + 'ExitCode') != 0
                    or hashlib.sha256(log.read_bytes()).hexdigest() != target.get(baseline + 'LogSha256')
                    or runner.classify(0, log.read_text()) != 'survived'):
                raise ValueError('Clean/restored baseline evidence did not pass')
            baseline_evidence.append({'shard': index, 'phase': baseline, 'status': 'survived',
                                      'log': f'{name}-shard-{index}-{baseline}.log',
                                      'sha256': target[baseline + 'LogSha256']})
    if set(outcomes) != set(expected_by_id):
        raise ValueError('Full mutation inventory was not completed')
    target = {**expected['targets'][name], 'outcomes': [outcomes[key] for key in sorted(outcomes)]}
    target.update(runner.summarize(target['outcomes']))
    target.update(baseline='survived', baselineExitCode=0, restoredBaseline='survived',
                  restoredBaselineExitCode=0, shardBaselineEvidence=baseline_evidence)
    target['gatePassed'] = runner.passes_assertion_gate(target, expected['gate']['threshold'])
    return {**expected, 'complete': True, 'baselineOnly': False,
            'shardsVerified': count, 'targets': {name: target},
            'gate': {**expected['gate'], 'passed': target['gatePassed']}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--target', required=True)
    parser.add_argument('--shard-count', type=int, required=True)
    args = parser.parse_args()
    paths = sorted(args.input.rglob('mutation-report.json'))
    args.output.mkdir(parents=True, exist_ok=False)
    inventory_dir = args.output / 'independent-inventory'
    subprocess.run([sys.executable, str(runner.ROOT / 'tool/run_dart_mutations.py'),
                    '--target', args.target, '--list', '--output', str(inventory_dir)], check=True)
    expected = json.loads((inventory_dir / 'mutation-report.json').read_text())
    report = merge(paths, expected, args.shard_count)
    # Keep the accepted aggregate independently auditable with sibling raw logs.
    for path in paths:
        shard = json.loads(path.read_text())
        target = shard['targets'][args.target]
        index = shard['shard']['index']
        for outcome in target['outcomes']:
            shutil.copy2(path.parent / outcome['log'], args.output / outcome['log'])
        for phase, label in (('baseline', 'baseline'), ('restoredBaseline', 'restored-baseline')):
            shutil.copy2(path.parent / f'{args.target}-{label}.log',
                         args.output / f'{args.target}-shard-{index}-{phase}.log')
    report['aggregatorSha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    (args.output / 'mutation-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'{args.target}: complete union assertion score '
          f'{report["targets"][args.target]["adjustedAssertionScoreLowerBound"]}; '
          f'gate {report["gate"]["passed"]}')
    return 0 if report['gate']['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
