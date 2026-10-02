#!/usr/bin/env python3
"""Audit immutable native mutation batches against one complete inventory."""

import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path

import native_coverage
import native_mutations
import run_native_mutations as collector


def combine_batches(reports, inventory):
    if not reports:
        raise ValueError('Require all batches')
    count = reports[0]['batch']['count']
    if type(count) is not int or count != len(reports):
        raise ValueError('Missing or extra batches')
    seen, results = set(), []
    baseline = reports[0]['baselineTests']
    if not baseline:
        raise ValueError('Missing baseline test inventory')
    for report in reports:
        batch = report['batch']
        index = batch['index']
        selected = collector.select_batch(inventory, index, count)
        if batch['count'] != count or index in seen:
            raise ValueError('Duplicate or inconsistent batch')
        seen.add(index)
        if report['baselineTests'] != baseline or report['host'] != reports[0]['host']:
            raise ValueError('Batch baseline/host differs')
        actual = [native_mutations.identity(item['mutant']) for item in report['results']]
        if sorted(actual) != sorted(map(native_mutations.identity, selected)):
            raise ValueError('Batch outcomes differ from full inventory partition')
        if any(item['status'] not in ('killed', 'survived', 'compileError', 'timeout', 'error')
               for item in report['results']):
            raise ValueError('Unknown mutation outcome')
        results.extend({**item, 'batchIndex': index} for item in report['results'])
    if seen != set(range(count)):
        raise ValueError('Missing batch index')
    results.sort(key=lambda item: native_mutations.identity(item['mutant']))
    counts = Counter(item['status'] for item in results)
    operators = defaultdict(Counter)
    for item in results:
        operators[item['mutant']['genre']][item['status']] += 1
    viable = len(results) - counts['compileError']
    score = 100 * counts['killed'] / viable if viable else None
    return {'schemaVersion': 1, 'scope': 'complete production inventory across audited batches',
            'host': reports[0]['host'], 'generated': len(results), 'counts': dict(counts),
            'viableCandidates': viable, 'rawCandidateScore': score,
            'adjustedCandidateScore': score, 'equivalents': [],
            'operators': dict(operators), 'baselineTests': baseline,
            'wholeComponentComplete': True, 'productionReadinessEstablished': False,
            'evidenceClean': bool(viable) and not counts['error'] and not counts['timeout'],
            'results': results}


def audit_batches(root, directories, analyzer):
    if not directories or len(set(path.resolve() for path in directories)) != len(directories):
        raise ValueError('Require distinct immutable batch directories')
    scope = native_coverage.snapshot(root, native_coverage.ROOTS, analyzer)
    inputs = {**scope['inputHashes'], **{
        name: native_coverage.digest(root / name) for name in collector.FIXTURES}}
    tool_root = Path(__file__).resolve().parent
    tools = {name: native_coverage.digest(tool_root / name) for name in collector.TOOL_INPUTS}
    reports, evidence = [], []
    full_inventory, target = None, None
    for directory in directories:
        manifest = json.loads((directory / 'run-manifest.json').read_text())
        if (manifest.get('complete') is not True or 'batch' not in manifest
                or manifest.get('scope') not in collector.WHOLE_COMPONENTS
                or manifest.get('cargoMutantsVersion') != 'cargo-mutants 27.1.0'
                or manifest.get('restoredExitCode') != 0
                or manifest.get('campaignExitCode') is None):
            raise ValueError('Batch collection did not complete')
        if manifest['inputHashes'] != inputs or manifest['toolHashes'] != tools:
            raise ValueError('Batch source/test/tool snapshot differs')
        if json.loads((directory / 'source-scopes.json').read_text()) != scope:
            raise ValueError('Batch AST scope differs')
        for key, name in [('rawInventorySha256', 'raw-inventory.json'),
                          ('partitionSha256', 'inventory-partition.json'),
                          ('filteredInventorySha256', 'filtered-inventory.json'),
                          ('batchInventorySha256', 'batch-inventory.json')]:
            if native_coverage.digest(directory / name) != manifest[key]:
                raise ValueError('Batch inventory evidence changed')
        raw = json.loads((directory / 'raw-inventory.json').read_text())
        partition = collector.partition_inventory(raw, scope)
        if partition != json.loads((directory / 'inventory-partition.json').read_text()):
            raise ValueError('Batch exclusions differ from AST proof')
        full = json.loads((directory / 'filtered-inventory.json').read_text())
        if sorted(map(native_mutations.identity, full)) != sorted(
                map(native_mutations.identity, partition['production'])):
            raise ValueError('Full inventory differs from production partition')
        if target is None:
            full_inventory, target = full, manifest['scope']
        if target != manifest['scope'] or full != full_inventory:
            raise ValueError('Batch full inventories or targets differ')
        selected = collector.select_batch(full, manifest['batch']['index'], manifest['batch']['count'])
        batch_inventory = json.loads((directory / 'batch-inventory.json').read_text())
        executed = json.loads((directory / 'mutants.out/mutants.json').read_text())
        for items in (batch_inventory, executed):
            if sorted(map(native_mutations.identity, items)) != sorted(map(native_mutations.identity, selected)):
                raise ValueError('Batch selected/executed inventory differs')
        report = native_mutations.audit(directory / 'mutants.out', scope)
        restored = (directory / 'restored-baseline.log').read_text()
        phases = {'phase_results': [{'phase': 'Build', 'process_status': 'Success'},
                                   {'phase': 'Test', 'process_status': 'Success'}]}
        if (native_mutations.classify(phases, restored, scope, None) != 'survived'
                or sorted(name for name, _ in native_mutations.TEST.findall(restored)) != report['baselineTests']):
            raise ValueError('Batch restored baseline differs or failed')
        report.update(batch=manifest['batch'], wholeComponentComplete=False,
                      scopeSha256=native_coverage.digest(directory / 'source-scopes.json'),
                      toolHashes=tools,
                      restoredBaselineLogSha256=native_coverage.digest(directory / 'restored-baseline.log'))
        if report != json.loads((directory / 'audited-results.json').read_text()):
            raise ValueError('Batch audit differs from retained evidence')
        reports.append(report)
        evidence.append({'directory': str(directory.resolve()),
                         'batch': manifest['batch'],
                         'manifestSha256': native_coverage.digest(directory / 'run-manifest.json'),
                         'reportSha256': native_coverage.digest(directory / 'audited-results.json')})
    result = combine_batches(reports, full_inventory)
    collector.verify_inputs(root, inputs)
    collector.verify_inputs(tool_root, tools)
    if native_coverage.snapshot(root, native_coverage.ROOTS, analyzer) != scope:
        raise ValueError('Native inventory changed during batch audit')
    result.update(target=target, inputHashes=inputs, toolHashes=tools, batches=evidence)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--analyzer', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('batches', nargs='+', type=Path)
    args = parser.parse_args()
    report = audit_batches(native_coverage.REPO, args.batches, args.analyzer)
    with args.output.open('x') as output:
        json.dump(report, output, indent=2)
        output.write('\n')
    print(json.dumps({key: report[key] for key in ('generated', 'counts', 'evidenceClean', 'adjustedCandidateScore')}))
    return 0 if report['evidenceClean'] and report['adjustedCandidateScore'] >= 95 else 1


if __name__ == '__main__':
    raise SystemExit(main())
