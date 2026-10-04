#!/usr/bin/env python3
"""Estimate native campaign cost from audited production pilots, never score them."""

import argparse
from collections import Counter
import json
import math
from pathlib import Path

import native_coverage
import native_mutation_batches
import native_mutations


def seconds(value):
    if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
        raise ValueError('Require finite nonnegative timing evidence')
    return value


def summarize(inventory, runs, *, elapsed, jobs, full_batches):
    if (not inventory or not runs or type(jobs) is not int or jobs < 1
            or type(full_batches) is not int or not 1 <= full_batches <= len(inventory)
            or seconds(elapsed) <= 0):
        raise ValueError('Require a nonempty timed pilot and positive resource limits')
    full = set(map(native_mutations.identity, inventory))
    if len(full) != len(inventory):
        raise ValueError('Duplicate production inventory')
    seen, sampled, durations = set(), [], []
    build = test = baseline = restored = work = overhead = 0
    for run in runs:
        run_time = seconds(run['elapsedSeconds'])
        restored_time = seconds(run['restoredSeconds'])
        run_mutation = run_baseline = 0
        baselines = 0
        for outcome in run['outcomes']:
            phases = outcome['phase_results']
            if [item['phase'] for item in phases] not in (['Build'], ['Build', 'Test']):
                raise ValueError('Unknown phase sequence in timing evidence')
            phase_times = {item['phase']: seconds(item.get('duration')) for item in phases}
            total = sum(phase_times.values())
            if outcome['scenario'] == 'Baseline':
                baselines += 1
                run_baseline += total
            else:
                mutant = outcome['scenario']['Mutant']
                identity = native_mutations.identity(mutant)
                if identity in seen or identity not in full:
                    raise ValueError('Duplicate or unknown sampled mutant')
                seen.add(identity)
                sampled.append(mutant)
                durations.append(total)
                run_mutation += total
                build += phase_times['Build']
                test += phase_times.get('Test', 0)
        if baselines != 1 or run_time + 1 < run_baseline + run_mutation + restored_time:
            raise ValueError('Missing baseline or inconsistent wall/phase timings')
        baseline += run_baseline
        restored += restored_time
        work += run_time
        overhead += max(0, run_time - run_mutation)
    if not sampled or work <= 0:
        raise ValueError('No measured mutation work')
    # Include cold builds, inventory/setup and restored baselines once per full
    # batch. Derive concurrency from measured wall time, not configured CPUs.
    effective = min(jobs, full_batches, work / elapsed)
    serial = (sum(durations) / len(sampled) * len(inventory)
              + overhead / len(runs) * full_batches)
    by_file = Counter(item['file'] for item in inventory)
    measured = Counter(item['file'] for item in sampled)
    ordered = sorted(durations)
    return {'timingOnly': True, 'wholeComponentComplete': False,
            'estimateNotMeasuredFullRun': True, 'generated': len(inventory),
            'sampledMutants': len(sampled), 'measuredElapsedSeconds': elapsed,
            'configuredWorkers': jobs, 'effectiveParallelism': effective,
            'mutationBuildSeconds': build, 'mutationTestSeconds': test,
            'baselineSeconds': baseline, 'restoredSeconds': restored,
            'meanMutationSeconds': sum(durations) / len(sampled),
            'p50MutationSeconds': ordered[math.ceil(len(ordered) * .5) - 1],
            'p95MutationSeconds': ordered[math.ceil(len(ordered) * .95) - 1],
            'meanBatchOverheadSeconds': overhead / len(runs),
            'estimatedFullBatchCount': full_batches,
            'estimatedFullSerialWorkSeconds': serial,
            'estimatedFullWallSeconds': serial / effective,
            'files': {name: {'generated': count, 'sampled': measured[name]}
                      for name, count in sorted(by_file.items())},
            'unmeasuredFiles': sorted(set(by_file) - set(measured)),
            'caveats': ['Deterministic sample, not a statistical confidence interval',
                        'Unseen failures/timeouts and shared-host contention may change runtime',
                        'Native scope only; Dart/browser targets are not estimated']}


def analyze(root, directory, analyzer, full_batches=32):
    manifest = json.loads((directory / 'campaign-manifest.json').read_text())
    pilot_path = directory / 'pilot.json'
    if (manifest.get('complete') or not manifest.get('pilotComplete')
            or native_coverage.digest(pilot_path) != manifest['pilotSha256']
            or any(item['reused'] for item in manifest['batches'])):
        raise ValueError('Require a completed fresh timing pilot, not cached or partial work')
    pilot = json.loads(pilot_path.read_text())
    paths = [Path(item['directory']) for item in manifest['batches']]
    inspected = native_mutation_batches.inspect_batches(root, paths, analyzer)
    if (inspected['inputHashes'] != manifest['inputHashes']
            or inspected['toolHashes'] != manifest['toolHashes']
            or inspected['executionFingerprint'] != manifest['executionFingerprint']
            or inspected['target'] != manifest['target']
            or inspected['batches'] != pilot['batches']):
        raise ValueError('Timing pilot provenance changed')
    runs, evidence = [], []
    for path in paths:
        batch = json.loads((path / 'run-manifest.json').read_text())
        raw = path / 'mutants.out/outcomes.json'
        runs.append({**batch, 'outcomes': json.loads(raw.read_text())['outcomes']})
        evidence.append({'directory': str(path), 'outcomesSha256': native_coverage.digest(raw)})
    result = summarize(inspected['inventory'], runs, elapsed=manifest['elapsedSeconds'],
                       jobs=manifest['jobs'], full_batches=full_batches)
    result.update(target=inspected['target'], inputHashes=inspected['inputHashes'],
                  toolHashes=inspected['toolHashes'],
                  executionFingerprint=inspected['executionFingerprint'],
                  batches=inspected['batches'], timingEvidence=evidence,
                  pilotManifestSha256=native_coverage.digest(directory / 'campaign-manifest.json'),
                  profilerSha256=native_coverage.digest(Path(__file__)),
                  baselineTests=inspected['reports'][0]['baselineTests'],
                  sampleResults=[item for report in inspected['reports'] for item in report['results']],
                  sampleEvidenceClean=all(report['evidenceClean'] for report in inspected['reports']))
    if result['sampledMutants'] != pilot['sampledMutants']:
        raise ValueError('Timing sample inventory differs from audited pilot')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pilot', type=Path)
    parser.add_argument('--analyzer', type=Path, required=True)
    parser.add_argument('--full-batches', type=int, default=32)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = analyze(native_coverage.REPO, args.pilot.resolve(), args.analyzer.resolve(), args.full_batches)
    with args.output.open('x') as destination:
        json.dump(result, destination, indent=2)
        destination.write('\n')
    print(json.dumps({key: result[key] for key in
                      ('target', 'generated', 'sampledMutants', 'measuredElapsedSeconds',
                       'estimatedFullWallSeconds', 'mutationBuildSeconds', 'mutationTestSeconds')}))


if __name__ == '__main__':
    main()
