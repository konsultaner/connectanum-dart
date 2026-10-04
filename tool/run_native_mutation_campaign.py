#!/usr/bin/env python3
"""Run isolated native batches concurrently and audit their exact inventory union."""

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
from pathlib import Path
import signal
import tempfile
import threading
import time

import native_coverage
import native_mutation_batches
import run_native_mutations as collector


def collect_campaign(root, output, analyzer, target, count, jobs=4, build_jobs=1, reuse=()):
    if (target not in collector.WHOLE_COMPONENTS
            or any(type(value) is not int or value < 1 for value in (count, jobs, build_jobs))
            or jobs > min(count, 64)):
        raise ValueError('Require a whole component, positive limits, and jobs <= min(batches, 64)')
    started = time.monotonic()
    output.mkdir(parents=True, exist_ok=False)
    scope = native_coverage.snapshot(root, native_coverage.ROOTS, analyzer)
    inputs = {**scope['inputHashes'], **{
        name: native_coverage.digest(root / name) for name in collector.FIXTURES}}
    tool_root = Path(collector.__file__).resolve().parent
    tools = {name: native_coverage.digest(tool_root / name) for name in collector.TOOL_INPUTS}
    execution = collector.execution_fingerprint()
    manifest = {'complete': False, 'target': target, 'batchCount': count,
                'jobs': jobs, 'cargoBuildJobs': build_jobs, 'inputHashes': inputs,
                'toolHashes': tools, 'executionFingerprint': execution,
                'batches': [], 'maxConcurrentWorkers': 0}
    manifest_path = output / 'campaign-manifest.json'

    def save():
        manifest['elapsedSeconds'] = time.monotonic() - started
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')

    save()
    with tempfile.TemporaryDirectory(prefix='connectanum-native-campaign-') as temporary:
        frozen = Path(temporary)
        collector.copy_inputs(root, frozen, inputs)
        partition = collector.prepare_inventory(frozen, output, scope, target)
        full = partition['production']
        collector.select_batch(full, 0, count)
        manifest['generated'] = len(full)
        manifest['inventorySha256'] = native_coverage.digest(output / 'filtered-inventory.json')
        directories = {}
        if reuse:
            inspected = native_mutation_batches.inspect_batches(root, list(reuse), analyzer)
            if (inspected['target'] != target or inspected['inventory'] != full
                    or inspected['inputHashes'] != inputs or inspected['toolHashes'] != tools
                    or inspected['executionFingerprint'] != execution):
                raise ValueError('Reused batches differ from the pinned campaign')
            for path, report in zip(reuse, inspected['reports']):
                index = report['batch']['index']
                if report['batch']['count'] != count or index in directories:
                    raise ValueError('Duplicate or differently partitioned reused batch')
                directories[index] = path.resolve()
                manifest['batches'].append({'index': index, 'directory': str(path.resolve()),
                                            'reused': True, 'workerSeconds': 0})
        save()
        cancel = threading.Event()
        lock = threading.Lock()
        active = 0

        def worker(index):
            nonlocal active
            if cancel.is_set():
                raise RuntimeError('Native batch cancelled before startup')
            directory = output / f'batch-{index:04d}'
            worker_started = time.monotonic()
            with lock:
                active += 1
                manifest['maxConcurrentWorkers'] = max(manifest['maxConcurrentWorkers'], active)
            try:
                code = collector.collect(frozen, directory, analyzer, target,
                                         batch=(index, count), build_jobs=build_jobs,
                                         cancel_event=cancel)
                return {'index': index, 'directory': str(directory), 'reused': False,
                        'exitCode': code, 'workerSeconds': time.monotonic() - worker_started}
            finally:
                with lock:
                    active -= 1

        executor = ThreadPoolExecutor(max_workers=jobs)
        errors = []
        try:
            futures = {executor.submit(worker, index): index
                       for index in range(count) if index not in directories}
            for future in as_completed(futures):
                index = futures[future]
                try:
                    item = future.result()
                    if item['exitCode'] not in (0, 1):
                        raise RuntimeError(f"Unexpected batch exit: {item['exitCode']}")
                    directories[index] = Path(item['directory'])
                    manifest['batches'].append(item)
                except Exception as error:
                    errors.append({'index': index, 'error': str(error)})
                    manifest['errors'] = errors
                save()
        finally:
            # Workers own separate cargo process groups. Cooperatively stop each
            # owner before deleting the frozen inputs or returning from main.
            cancel.set()
            executor.shutdown(wait=True, cancel_futures=True)
            save()
        if errors:
            raise RuntimeError(f'Incomplete native batches: {errors}')
        collector.verify_inputs(root, inputs)
        collector.verify_inputs(tool_root, tools)
        if collector.execution_fingerprint() != execution:
            raise ValueError('Campaign execution configuration changed')
        if native_coverage.snapshot(root, native_coverage.ROOTS, analyzer) != scope:
            raise ValueError('Campaign source inventory changed')
        if native_coverage.digest(output / 'filtered-inventory.json') != manifest['inventorySha256']:
            raise ValueError('Pinned campaign inventory changed')
        report = native_mutation_batches.audit_batches(
            root, [directories[index] for index in range(count)], analyzer)
        if (report['inputHashes'] != inputs or report['toolHashes'] != tools
                or report['generated'] != len(full)):
            raise ValueError('Combined evidence differs from pinned campaign')
        with (output / 'combined.json').open('x') as destination:
            json.dump(report, destination, indent=2)
            destination.write('\n')
        manifest.update(complete=True, gatePassed=report['evidenceClean']
                        and report['adjustedCandidateScore'] >= 95)
        manifest['batches'].sort(key=lambda item: item['index'])
        save()
        print(json.dumps({key: manifest[key] for key in
                          ('complete', 'generated', 'elapsedSeconds', 'maxConcurrentWorkers', 'gatePassed')}))
        return 0 if manifest['gatePassed'] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--analyzer', type=Path, required=True)
    parser.add_argument('--target', choices=sorted(collector.WHOLE_COMPONENTS), required=True)
    parser.add_argument('--batches', type=int, default=32)
    parser.add_argument('--jobs', type=int, default=4)
    parser.add_argument('--cargo-jobs', type=int,
                        help='Build threads per worker; defaults to CPU count divided by workers')
    parser.add_argument('--reuse', type=Path, action='append', default=[],
                        help='Completed immutable batch directory; raw logs are reaudited before reuse')
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error('jobs must be positive')
    build_jobs = args.cargo_jobs if args.cargo_jobs is not None else max(1, (os.cpu_count() or 1) // args.jobs)

    def interrupt(_signum, _frame):
        raise KeyboardInterrupt

    previous = signal.signal(signal.SIGTERM, interrupt)
    try:
        return collect_campaign(native_coverage.REPO, args.output.resolve(), args.analyzer.resolve(),
                                args.target, args.batches, args.jobs, build_jobs, args.reuse)
    except KeyboardInterrupt:
        return 130
    finally:
        signal.signal(signal.SIGTERM, previous)


if __name__ == '__main__':
    raise SystemExit(main())
