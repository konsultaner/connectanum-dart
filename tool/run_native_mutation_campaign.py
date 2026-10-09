#!/usr/bin/env python3
"""Run isolated native batches concurrently and audit their exact inventory union."""

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
from dataclasses import asdict
import os
from pathlib import Path
import signal
import sys
import tempfile
import threading
import time

import native_coverage
import native_mutation_coordination as coordination
import native_mutation_batches
import native_mutation_resources as resources
import run_native_mutations as collector


def sample_indices(count, sample_count):
    if (type(count) is not int or type(sample_count) is not int
            or not 1 <= sample_count < count):
        raise ValueError('A timing pilot must select fewer positive batches than the full campaign')
    return [index * count // sample_count for index in range(sample_count)]


def write_json_atomic(path, value):
    temporary = path.with_name(f'.{path.name}.tmp')
    try:
        with temporary.open('x') as destination:
            json.dump(value, destination, indent=2)
            destination.write('\n')
            destination.flush()
            os.fsync(destination.fileno())
        os.replace(temporary, path)
        if os.name != 'nt':
            descriptor = os.open(path.parent, os.O_RDONLY)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
    finally:
        temporary.unlink(missing_ok=True)


def resume_batches(source, output, target, count, jobs, build_jobs, resource_limits):
    source = source.resolve()
    output = output.resolve()
    if source == output:
        raise ValueError('Resume requires a fresh output directory')
    manifest_path = source / 'campaign-manifest.json'
    try:
        manifest_bytes = manifest_path.read_bytes()
        manifest = json.loads(manifest_bytes)
    except (OSError, json.JSONDecodeError, TypeError) as error:
        raise ValueError('Resume campaign manifest is missing or invalid') from error
    if type(manifest) is not dict or manifest.get('complete') is not False:
        raise ValueError('Resume requires an incomplete campaign manifest')
    if manifest.get('timingOnly') is True or manifest.get('pilotComplete') is True:
        raise ValueError('Cannot resume a timing pilot')
    expected_limits = asdict(resource_limits) if resource_limits is not None else None
    if (manifest.get('target') != target or manifest.get('batchCount') != count
            or manifest.get('jobs') != jobs or manifest.get('cargoBuildJobs') != build_jobs
            or manifest.get('resourceLimits') != expected_limits
            or manifest.get('resourceSchemaVersion')
            != (resources.SCHEMA_VERSION if resource_limits is not None else None)):
        raise ValueError('Resume campaign configuration differs')
    records = manifest.get('batches')
    if type(records) is not list:
        raise ValueError('Resume campaign has invalid batch records')
    directories = []
    recorded_paths = {}
    seen = set()
    for record in records:
        if type(record) is not dict:
            raise ValueError('Resume campaign has invalid batch records')
        index = record.get('index')
        directory = record.get('directory')
        reused = record.get('reused')
        if (type(index) is not int or not 0 <= index < count or type(directory) is not str
                or not directory or type(reused) is not bool or index in seen):
            raise ValueError('Resume campaign has invalid or duplicate batch records')
        path = Path(directory)
        path = (source / path).resolve() if not path.is_absolute() else path.resolve()
        if not reused:
            exit_code = record.get('exitCode')
            if type(exit_code) is not int or exit_code not in (0, 1):
                raise ValueError('Resume campaign contains an incomplete batch record')
            if path != (source / f'batch-{index:04d}').resolve():
                raise ValueError('Resume campaign batch path differs from its index')
        directories.append(path)
        recorded_paths[index] = path
        seen.add(index)

    excluded_incomplete = []
    excluded_complete = []
    for path in sorted(source.glob('batch-*')):
        name = path.name.removeprefix('batch-')
        if (path.is_symlink() or not path.is_dir() or len(name) != 4 or not name.isdigit()
                or not 0 <= int(name) < count):
            raise ValueError('Resume campaign contains an invalid batch directory')
        index = int(name)
        if recorded_paths.get(index) == path.resolve():
            continue
        batch_manifest_path = path / 'run-manifest.json'
        try:
            batch_manifest = json.loads(batch_manifest_path.read_text())
        except (OSError, json.JSONDecodeError, TypeError):
            batch_manifest = None
        if type(batch_manifest) is dict and batch_manifest.get('complete') is True:
            excluded_complete.append(index)
        else:
            excluded_incomplete.append(index)
    try:
        if manifest_path.read_bytes() != manifest_bytes:
            raise ValueError('Resume campaign manifest changed during inspection')
    except OSError as error:
        raise ValueError('Resume campaign manifest changed during inspection') from error
    return directories, {
        'directory': str(source),
        'manifestSha256': hashlib.sha256(manifest_bytes).hexdigest(),
        'completedBatchIndexes': sorted(seen),
        'excludedIncompleteBatchIndexes': sorted(excluded_incomplete),
        'excludedUnrecordedCompleteBatchIndexes': sorted(excluded_complete),
        'pendingBatchIndexes': sorted(set(range(count)) - seen),
    }


def collect_campaign(root, output, analyzer, target, count, jobs=4, build_jobs=1, reuse=(),
                     *, sample_count=None, resource_limits=None, resume_from=None):
    if (target not in collector.WHOLE_COMPONENTS
            or any(type(value) is not int or value < 1 for value in (count, jobs, build_jobs))
            or jobs > min(count, 64)):
        raise ValueError('Require a whole component, positive limits, and jobs <= min(batches, 64)')
    selected = list(range(count)) if sample_count is None else sample_indices(count, sample_count)
    if sample_count is not None and reuse:
        raise ValueError('Timing pilots require fresh batches, not reused timing measurements')
    if sample_count is not None and resume_from is not None:
        raise ValueError('Cannot resume a timing pilot')
    if reuse and resume_from is not None:
        raise ValueError('Resume cannot be combined with manual reuse')
    resumed_from = None
    if resume_from is not None:
        reuse, resumed_from = resume_batches(
            resume_from, output, target, count, jobs, build_jobs, resource_limits)
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
    if resource_limits is not None:
        manifest['resourceLimits'] = asdict(resource_limits)
        manifest['resourceSchemaVersion'] = resources.SCHEMA_VERSION
    if resumed_from is not None:
        manifest['resumedFrom'] = resumed_from
    if sample_count is not None:
        manifest.update(timingOnly=True, sampledBatchIndexes=selected)
    manifest_path = output / 'campaign-manifest.json'

    def save():
        manifest['elapsedSeconds'] = time.monotonic() - started
        write_json_atomic(manifest_path, manifest)

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
                    or inspected['executionFingerprint'] != execution
                    or inspected.get('resourceLimits') != manifest.get('resourceLimits')
                    or inspected.get('resourceSchemaVersion') != manifest.get('resourceSchemaVersion')):
                raise ValueError('Reused batches differ from the pinned campaign')
            for path, report in zip(reuse, inspected['reports']):
                index = report['batch']['index']
                if index not in selected:
                    raise ValueError('Reused batch outside selected timing pilot')
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
                                         cancel_event=cancel, resource_limits=resource_limits)
                if type(code) is not int or code not in (0, 1):
                    raise RuntimeError(f'Unexpected batch exit: {code}')
                return {'index': index, 'directory': str(directory), 'reused': False,
                        'exitCode': code, 'workerSeconds': time.monotonic() - worker_started}
            except BaseException:
                # Signal peers before this pool thread can take a queued batch.
                cancel.set()
                raise
            finally:
                with lock:
                    active -= 1

        executor = ThreadPoolExecutor(max_workers=jobs)
        errors = []
        try:
            futures = {executor.submit(worker, index): index
                       for index in selected if index not in directories}
            for future in as_completed(futures):
                index = futures[future]
                try:
                    item = future.result()
                    if item['exitCode'] not in (0, 1):
                        raise RuntimeError(f"Unexpected batch exit: {item['exitCode']}")
                    directories[index] = Path(item['directory'])
                    manifest['batches'].append(item)
                except Exception as error:
                    cancel.set()
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
        manifest['batches'].sort(key=lambda item: item['index'])
        if sample_count is not None:
            inspected = native_mutation_batches.inspect_batches(
                root, [directories[index] for index in selected], analyzer)
            if (inspected['inventory'] != full or inspected['inputHashes'] != inputs
                    or inspected['toolHashes'] != tools
                    or inspected['executionFingerprint'] != execution
                    or inspected.get('resourceLimits') != manifest.get('resourceLimits')
                    or inspected.get('resourceSchemaVersion') != manifest.get('resourceSchemaVersion')):
                raise ValueError('Timing pilot differs from pinned campaign')
            pilot = {'timingOnly': True, 'wholeComponentComplete': False,
                     'generated': len(full), 'sampledBatchIndexes': selected,
                     'sampledMutants': sum(len(report['results']) for report in inspected['reports']),
                     'batches': inspected['batches']}
            with (output / 'pilot.json').open('x') as destination:
                json.dump(pilot, destination, indent=2)
                destination.write('\n')
            manifest.update(pilotComplete=True, pilotSha256=native_coverage.digest(output / 'pilot.json'))
            save()
            print(json.dumps(pilot))
            return 0
        report = native_mutation_batches.audit_batches(
            root, [directories[index] for index in range(count)], analyzer)
        if (report['inputHashes'] != inputs or report['toolHashes'] != tools
                or report['generated'] != len(full)
                or report.get('resourceLimits') != manifest.get('resourceLimits')
                or report.get('resourceSchemaVersion') != manifest.get('resourceSchemaVersion')):
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
    try:
        lease = coordination.acquire_resource_lease(exclusive=True)
    except coordination.ResourceLeaseError as error:
        print(error, file=sys.stderr)
        return 2
    with lease:
        return _run_main()


def _run_main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--analyzer', type=Path, required=True)
    parser.add_argument('--target', choices=sorted(collector.WHOLE_COMPONENTS), required=True)
    parser.add_argument('--batches', type=int, default=32)
    parser.add_argument('--jobs', type=int, default=4)
    parser.add_argument('--cargo-jobs', type=int,
                        help='Build threads per worker; defaults to CPU count divided by workers')
    parser.add_argument('--pilot-batches', type=int,
                        help='Measure evenly spaced batches only; never create a combined score')
    parser.add_argument('--reuse', type=Path, action='append', default=[],
                        help='Completed immutable batch directory; raw logs are reaudited before reuse')
    parser.add_argument('--resume-from', type=Path,
                        help='Incomplete campaign directory; resume into the required fresh output')
    resources.add_arguments(parser)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error('jobs must be positive')
    build_jobs = args.cargo_jobs if args.cargo_jobs is not None else max(1, (os.cpu_count() or 1) // args.jobs)

    def interrupt(_signum, _frame):
        raise KeyboardInterrupt

    previous = signal.signal(signal.SIGTERM, interrupt)
    try:
        return collect_campaign(native_coverage.REPO, args.output.resolve(), args.analyzer.resolve(),
                                args.target, args.batches, args.jobs, build_jobs, args.reuse,
                                sample_count=args.pilot_batches,
                                resource_limits=resources.DiskLimits(
                                    args.disk_reserve_gib, args.max_cache_gib),
                                resume_from=args.resume_from)
    except KeyboardInterrupt:
        return 130
    finally:
        signal.signal(signal.SIGTERM, previous)


if __name__ == '__main__':
    raise SystemExit(main())
