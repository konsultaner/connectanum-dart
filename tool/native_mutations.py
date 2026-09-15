#!/usr/bin/env python3
"""Audit cargo-mutants evidence without treating Cargo's exit 101 as a kill."""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re

import native_coverage


SUMMARY = re.compile(
    r'^test result: (ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored; '
    r'(\d+) measured; (\d+) filtered out;', re.M)
FAILURE = re.compile(
    r'^---- (.+) stdout ----\n(.*?)(?=^---- .+ stdout ----\n|^failures:\n|\Z)',
    re.M | re.S)
PANIC = re.compile(r"^thread .+ panicked at (.+):(\d+):(\d+):\n", re.M)
ASSERTION = re.compile(r'^assertion (?:failed:|`[^`]+` failed)', re.M)
CRASH = re.compile(
    r'signal: \d+|SIG(?:ABRT|SEGV|ILL|BUS|KILL)|stack overflow|fatal runtime error|'
    r'failed to run custom build|could not execute process|No space left on device')
TEST = re.compile(r'^test (.+) \.\.\. (ok|FAILED|ignored)$', re.M)


def source_for(path: str, scope: dict) -> str | None:
    normalized = Path(path).as_posix()
    if '..' in Path(path).parts:
        return None
    candidates = [source for source in scope['sources']
                  if source == normalized or source.endswith('/' + normalized)]
    return candidates[0] if len(candidates) == 1 else None


def test_assertion(body: str, scope: dict, mutant: dict | None) -> bool:
    panics = list(PANIC.finditer(body))
    if len(panics) != 1 or not ASSERTION.match(body[panics[0].end():]):
        return False
    panic = panics[0]
    source = source_for(panic[1], scope)
    if source is None:
        return False
    line = int(panic[2])
    if mutant and source == source_for(mutant['file'], scope):
        start, end = mutant['span']['start']['line'], mutant['span']['end']['line']
        inserted = mutant['replacement'].count('\n')
        # Function-body replacements move following tests in the compiled file.
        if start <= line <= start + inserted:
            return False
        if line > start + inserted:
            line += end - start - inserted
    info = scope['sources'][source]
    return 0 < line <= info['lineCount'] and (
        info['classification'] == 'test-only' or line in info['excludedLines'])


def classify(outcome: dict, log: str, scope: dict, mutant: dict | None) -> str:
    phases = outcome.get('phase_results', [])
    if not phases:
        return 'error'
    statuses = [phase.get('process_status') for phase in phases]
    if 'Timeout' in statuses:
        return 'timeout'
    if CRASH.search(log) or any(
            isinstance(status, dict) and 'Signalled' in status for status in statuses):
        return 'error'
    names = [phase.get('phase') for phase in phases]
    if names == ['Build'] and statuses == [{'Failure': 101}]:
        return 'compileError' if re.search(r'^error\[E\d+\]:', log, re.M) else 'error'
    if names != ['Build', 'Test'] or statuses[0] != 'Success':
        return 'error'
    summaries = list(SUMMARY.finditer(log))
    if not summaries:
        return 'error'
    passed = failed = 0
    for summary in summaries:
        ok, successes, failures, ignored, measured, _filtered = summary.groups()
        if int(ignored) or int(measured) or (ok == 'ok') != (int(failures) == 0):
            return 'error'
        passed += int(successes)
        failed += int(failures)
    running = [int(count) for count in re.findall(r'^running (\d+) tests?$', log, re.M)]
    if len(running) != len(summaries) or sum(running) != passed + failed or not passed + failed:
        return 'error'
    tests = TEST.findall(log)
    if len(tests) != passed + failed or sum(status == 'FAILED' for _, status in tests) != failed:
        return 'error'
    blocks = list(FAILURE.finditer(log))
    if not failed:
        return 'survived' if statuses[-1] == 'Success' and not blocks else 'error'
    if statuses[-1] != {'Failure': 101} or len(blocks) != failed:
        return 'error'
    if len({block[1] for block in blocks}) != failed:
        return 'error'
    if {name for name, status in tests if status == 'FAILED'} != {block[1] for block in blocks}:
        return 'error'
    return 'killed' if all(test_assertion(block[2], scope, mutant) for block in blocks) else 'error'


def identity(mutant: dict) -> str:
    return json.dumps({key: value for key, value in mutant.items() if key != 'diff'},
                      sort_keys=True, separators=(',', ':'))


def read_log(directory: Path, relative: str) -> tuple[str, str]:
    path = (directory / relative).resolve()
    if Path(relative).is_absolute() or '..' in Path(relative).parts or not path.is_relative_to(directory.resolve()):
        raise ValueError('Log path escapes the campaign directory')
    data = path.read_bytes()
    return data.decode('utf-8'), hashlib.sha256(data).hexdigest()


def audit(directory: Path, scope: dict) -> dict:
    inventory_bytes = (directory / 'mutants.json').read_bytes()
    outcomes_bytes = (directory / 'outcomes.json').read_bytes()
    inventory, run = json.loads(inventory_bytes), json.loads(outcomes_bytes)
    if run.get('cargo_mutants_version') != '27.1.0' or not run.get('end_time'):
        raise ValueError('Require a completed cargo-mutants 27.1.0 campaign')
    if not isinstance(inventory, list) or not inventory:
        raise ValueError('Require a nonempty complete inventory')
    expected = {identity(mutant): mutant for mutant in inventory}
    if len(expected) != len(inventory):
        raise ValueError('Duplicate inventory entry')
    for mutant in inventory:
        source = source_for(mutant['file'], scope)
        if source is None:
            raise ValueError('Mutant source missing from verified source scope')
        info = scope['sources'][source]
        start, end = mutant['span']['start']['line'], mutant['span']['end']['line']
        if not 0 < start <= end <= info['lineCount'] or info['classification'] != 'production-candidate':
            raise ValueError('Mutant outside production-candidate source')
        if any(line in info['excludedLines'] for line in range(start, end + 1)):
            raise ValueError('Mutant overlaps test/helper-only source')
    baselines = [item for item in run['outcomes'] if item['scenario'] == 'Baseline']
    if len(baselines) != 1:
        raise ValueError('Require exactly one clean baseline')
    baseline_log, baseline_hash = read_log(directory, baselines[0]['log_path'])
    if baselines[0]['summary'] != 'Success' or classify(baselines[0], baseline_log, scope, None) != 'survived':
        raise ValueError('Baseline did not finish a nonempty, unskipped passing suite')
    baseline_tests = sorted(name for name, _ in TEST.findall(baseline_log))
    results, seen = [], set()
    seen_logs = {(directory / baselines[0]['log_path']).resolve()}
    for item in run['outcomes']:
        if item['scenario'] == 'Baseline':
            continue
        mutant = item['scenario']['Mutant']
        key = identity(mutant)
        if key not in expected or key in seen:
            raise ValueError('Unexpected or duplicate mutant outcome')
        seen.add(key)
        log_path = (directory / item['log_path']).resolve()
        if log_path in seen_logs:
            raise ValueError('Distinct scenarios must retain distinct logs')
        seen_logs.add(log_path)
        log, log_hash = read_log(directory, item['log_path'])
        status = classify(item, log, scope, mutant)
        expected_summary = {'killed': 'CaughtMutant', 'survived': 'MissedMutant',
                            'compileError': 'Unviable', 'timeout': 'Timeout'}.get(status)
        if expected_summary and item['summary'] != expected_summary:
            raise ValueError('Cargo summary contradicts its phase/log evidence')
        if status in ('killed', 'survived') and sorted(name for name, _ in TEST.findall(log)) != baseline_tests:
            status = 'error'
        results.append({'mutant': mutant, 'status': status,
                        'cargoSummary': item['summary'], 'log': item['log_path'],
                        'logSha256': log_hash})
    if seen != set(expected) or run.get('total_mutants') != len(expected):
        raise ValueError('Incomplete inventory/outcome correspondence')
    counts = Counter(result['status'] for result in results)
    operators = defaultdict(Counter)
    for result in results:
        operators[result['mutant']['genre']][result['status']] += 1
    viable = len(results) - counts['compileError']
    score = 100 * counts['killed'] / viable if viable else None
    return {
        'schemaVersion': 1, 'host': scope['host'], 'generated': len(results),
        'scope': 'complete supplied production-candidate inventory; cfg-inactive candidates are not excluded',
        'productionReadinessEstablished': False,
        'evidenceClean': not counts['error'] and not counts['timeout'] and viable > 0,
        'counts': dict(counts), 'viableCandidates': viable, 'rawCandidateScore': score,
        'adjustedCandidateScore': score, 'equivalents': [], 'operators': dict(operators),
        'baselineTests': baseline_tests,
        'baselineLogSha256': baseline_hash,
        'inventorySha256': hashlib.sha256(inventory_bytes).hexdigest(),
        'outcomesSha256': hashlib.sha256(outcomes_bytes).hexdigest(), 'results': results,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--scope', type=Path, required=True)
    parser.add_argument('--analyzer', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    scope = json.loads(args.scope.read_text())
    if native_coverage.snapshot(native_coverage.REPO, scope['roots'], args.analyzer) != scope:
        raise ValueError('Native source/test/build scope changed since snapshot')
    report = audit(args.run, scope)
    report['scopeSha256'] = native_coverage.digest(args.scope)
    with args.output.open('x') as output:
        json.dump(report, output, indent=2)
        output.write('\n')
    print(json.dumps({key: value for key, value in report.items() if key != 'results'}, indent=2))
    return 0 if report['evidenceClean'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
