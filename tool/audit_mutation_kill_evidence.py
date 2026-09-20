#!/usr/bin/env python3
"""Add kill-cause diagnostics to a separate copy of a Dart mutation report.

Usage: python3 tool/audit_mutation_kill_evidence.py REPORT --output NEW_JSON
       [--reclassify-deadlines]
The original report and logs remain untouched; this does not rerun tests or
make historical source/test hashes match a newer worktree.
"""

import argparse
import hashlib
import json
from pathlib import Path

import run_dart_mutations as runner


def audit(report_path, *, reclassify_deadlines=False):
    report_path = Path(report_path).resolve(strict=True)
    original = report_path.read_bytes()
    report = json.loads(original, object_pairs_hook=runner.unique_json_object)
    if report.get('schemaVersion') != 1 or not isinstance(report.get('targets'), dict):
        raise ValueError('Expected a version 1 Dart mutation report')
    if 'killEvidenceAudit' in report:
        raise ValueError('Audit the original campaign report, not a derived audit')
    reclassified = 0
    for name, target in report['targets'].items():
        outcomes = target['outcomes']
        original_summary = runner.summarize(outcomes)
        for field in ('counts', 'viable', 'score', 'equivalent', 'adjustedScore'):
            if field in target and target[field] != original_summary[field]:
                raise ValueError(f'{name}: saved {field} differs from observed outcomes')
        historical = {field: target[field] for field in original_summary if field in target}
        if 'gatePassed' in target:
            historical['gatePassed'] = target['gatePassed']
        target_reclassified = False
        for outcome in outcomes:
            if outcome['status'] != 'killed':
                # Non-kills must never carry assertion credit from input data.
                outcome.pop('killEvidence', None)
                continue
            filename = outcome.get('log')
            if not isinstance(filename, str) or Path(filename).name != filename:
                raise ValueError(f'Invalid mutation log filename in {name}')
            path = (report_path.parent / filename).resolve(strict=True)
            if path.parent != report_path.parent or not path.is_file():
                raise ValueError(f'Mutation log escapes report directory: {filename}')
            raw_log = path.read_bytes()
            output = raw_log.decode('utf-8')
            status = runner.classify(outcome['exitCode'], output)
            if status != 'killed' and not (reclassify_deadlines and status == 'timeout'):
                raise ValueError(f'{name}/{outcome["id"]}: saved kill classifies as {status}')
            if status == 'timeout':
                outcome['historicalStatus'] = outcome['status']
                outcome['status'] = status
                outcome.pop('killEvidence', None)
                target_reclassified = True
                reclassified += 1
            else:
                outcome['killEvidence'] = runner.kill_evidence(status, output)
            outcome['logSha256'] = hashlib.sha256(raw_log).hexdigest()
        summary = runner.summarize(outcomes)
        if target_reclassified:
            target['historicalSummary'] = historical
        target.update(summary)
        if 'gate' in report and 'gatePassed' in target:
            target['gatePassed'] = bool(target['gatePassed'] and
                                       runner.passes_assertion_gate(summary, report['gate']['threshold']))
    if 'gate' in report:
        report['historicalGate'] = dict(report['gate'])
        report['gate']['passed'] = bool(report['gate'].get('passed') and report.get('complete') and
                                      all(t.get('gatePassed') for t in report['targets'].values()))
    report['killEvidenceVersion'] = 1
    report['scoreDefinition'] = 'Completed test detection, including caught test errors'
    report['killEvidenceAudit'] = {
        'sourceReport': str(report_path),
        'sourceReportSha256': hashlib.sha256(original).hexdigest(),
        'auditorSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'classifierSha256': hashlib.sha256(Path(runner.__file__).read_bytes()).hexdigest(),
        'reclassifiedDeadlines': reclassified,
    }
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--reclassify-deadlines', action='store_true',
                        help='Correct historical kill-to-timeout classifications in a new report')
    args = parser.parse_args()
    report = audit(args.report, reclassify_deadlines=args.reclassify_deadlines)
    # Exclusive creation preserves the original campaign and previous audits.
    with args.output.open('x') as output:
        json.dump(report, output, indent=2)
        output.write('\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
