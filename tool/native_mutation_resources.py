#!/usr/bin/env python3
"""Observe private mutation resources and host contention without kill credit."""

import argparse
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import json
import hashlib
import math
import os
from pathlib import Path
import stat
import subprocess
import threading
import time


COMPANION_SCRIPTS = frozenset(('ollama_companion.py', 'llama_companion.py'))
COMPANION_ROLES = frozenset(('ask', 'debug', 'judge', 'review', 'summarize', 'tests'))
PROCESS_SNAPSHOT_ATTEMPTS = 3
PROCESS_SNAPSHOT_RETRY_SECONDS = .05
PROCESS_CONFIRMATION_SECONDS = .75
SCHEMA_VERSION = 3


@dataclass(frozen=True)
class DiskLimits:
    reserve_bytes: int
    max_cache_bytes: int
    interval_seconds: float = 5

    def __post_init__(self):
        if (any(type(value) is not int or value <= 0
                for value in (self.reserve_bytes, self.max_cache_bytes))
                or type(self.interval_seconds) not in (int, float)
                or not math.isfinite(self.interval_seconds) or self.interval_seconds <= 0):
            raise ValueError('Require positive finite disk limits and sampling interval')


def gib_bytes(value):
    try:
        number = float(value)
        if not math.isfinite(number) or number <= 0 or number * 1024 ** 3 < 1:
            raise ValueError()
        return int(number * 1024 ** 3)
    except (ValueError, OverflowError):
        raise argparse.ArgumentTypeError('Require positive finite GiB') from None


def add_arguments(parser):
    parser.add_argument('--disk-reserve-gib', type=gib_bytes, default=4 * 1024 ** 3,
                        help='Cancel all owned workers below this free-disk reserve (default 4)')
    parser.add_argument('--max-cache-gib', type=gib_bytes, default=3 * 1024 ** 3,
                        help='Cancel above this per-worker private cache limit (default 3)')


def available_bytes(path):
    disk = os.statvfs(path)
    return disk.f_bavail * disk.f_frsize


def parse_competing_processes(output, uid=None):
    """Return sanitized identities for active local companion requests."""
    expected_uid = os.getuid() if uid is None else uid
    detected = {}
    for line in output.splitlines():
        fields = line.split(maxsplit=4)
        if len(fields) != 5:
            continue
        pid, ppid, owner, state, command = fields
        try:
            pid, ppid, owner = int(pid), int(ppid), int(owner)
        except ValueError:
            continue
        if owner != expected_uid or pid <= 0 or ppid < 0 or not state or state[0] in ('Z', 'X'):
            continue
        arguments = command.split()
        if len(arguments) < 3:
            continue
        executable = Path(arguments[0]).name
        script = Path(arguments[1]).name
        role = arguments[2]
        if (not executable.lower().startswith(('python', 'pypy'))
                or script not in COMPANION_SCRIPTS or role not in COMPANION_ROLES):
            continue
        detected[pid] = {'pid': pid, 'ppid': ppid, 'state': state,
                         'executable': executable, 'script': script, 'role': role}
    return [detected[pid] for pid in sorted(detected)]


def _process_snapshot():
    for attempt in range(PROCESS_SNAPSHOT_ATTEMPTS):
        try:
            result = subprocess.run(
                ['ps', '-ww', '-axo', 'pid=,ppid=,uid=,state=,args='],
                capture_output=True, text=True, check=True, timeout=5,
            )
            break
        except subprocess.TimeoutExpired:
            if attempt + 1 == PROCESS_SNAPSHOT_ATTEMPTS:
                raise
            # A timed-out snapshot may be partial; retry the whole process table.
            time.sleep(PROCESS_SNAPSHOT_RETRY_SECONDS)
    return parse_competing_processes(result.stdout)


def competing_processes():
    initial = _process_snapshot()
    if not initial:
        return []

    # A companion rejected by the exclusive mutation lease can be briefly visible
    # before its process exits. Confirm the same process identity before cancelling.
    time.sleep(PROCESS_CONFIRMATION_SECONDS)
    confirmed = _process_snapshot()
    identity_fields = ('pid', 'ppid', 'executable', 'script', 'role')
    initial_identities = {
        tuple(process[field] for field in identity_fields) for process in initial
    }
    return [
        process for process in confirmed
        if tuple(process[field] for field in identity_fields) in initial_identities
    ]


def tree_usage(path, children=()):
    """Count regular-file bytes, deduplicating hard links; never follow links."""
    totals = {'logicalBytes': 0, 'allocatedBytes': 0, 'files': 0, 'skippedSymlinks': 0}
    seen = set()
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW

    def visit(descriptor):
        with os.scandir(descriptor) as entries:
            for entry in entries:
                try:
                    info = os.stat(entry.name, dir_fd=descriptor, follow_symlinks=False)
                    if stat.S_ISLNK(info.st_mode):
                        totals['skippedSymlinks'] += 1
                    elif stat.S_ISDIR(info.st_mode):
                        child = os.open(entry.name, flags, dir_fd=descriptor)
                        try:
                            visit(child)
                        finally:
                            os.close(child)
                    elif stat.S_ISREG(info.st_mode) and (info.st_dev, info.st_ino) not in seen:
                        seen.add((info.st_dev, info.st_ino))
                        totals['logicalBytes'] += info.st_size
                        totals['allocatedBytes'] += info.st_blocks * 512
                        totals['files'] += 1
                except FileNotFoundError:
                    # Cargo can remove an object between directory listing and stat.
                    continue

    try:
        descriptor = os.open(path, flags)
    except FileNotFoundError:
        return totals
    try:
        for name in children:
            if name in ('', '.', '..') or '/' in name:
                raise ValueError('Require direct owned-cache child names')
            try:
                child = os.open(name, flags, dir_fd=descriptor)
            except FileNotFoundError:
                return totals
            os.close(descriptor)
            descriptor = child
        visit(descriptor)
    finally:
        os.close(descriptor)
    return totals


def validate_evidence(directory, manifest):
    limits = manifest.get('resourceLimits')
    if limits is None:
        if any((directory / name).exists() for name in ('resources.jsonl', 'resource-summary.json')):
            raise ValueError('Resource evidence missing its policy')
        return
    policy = DiskLimits(**limits)
    documents = {}
    for key, name in [('resourceSummarySha256', 'resource-summary.json'),
                      ('resourceSamplesSha256', 'resources.jsonl')]:
        raw = (directory / name).read_bytes()
        if hashlib.sha256(raw).hexdigest() != manifest.get(key):
            raise ValueError('Resource evidence hash differs')
        documents[name] = raw
    summary = json.loads(documents['resource-summary.json'])
    rows = [json.loads(line) for line in documents['resources.jsonl'].splitlines()]
    version = summary.get('schemaVersion')
    if (type(version) is not int or version not in (1, 2, 3) or summary.get('withinLimits') is not True
            or summary.get('failure') is not None or summary.get('limits') != limits
            or type(summary.get('samples')) is not int
            or summary.get('samples') != len(rows) or len(rows) < 2):
        raise ValueError('Resource observation did not finish within limits')
    expected_version = manifest.get('resourceSchemaVersion')
    if ((expected_version is not None and expected_version != version)
            or (version == SCHEMA_VERSION and expected_version != SCHEMA_VERSION)):
        raise ValueError('Resource evidence schema differs from its manifest')
    if manifest.get('privateTemporaryDirectory') is not None and version < 2:
        raise ValueError('Private temporary observation requires resource schema 2 or later')
    elapsed = -1
    observed_competition = {}
    peak_competition = 0
    for row in rows:
        for value in (row['elapsedSeconds'], row['samplingSeconds']):
            if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
                raise ValueError('Invalid resource timing')
        if row['elapsedSeconds'] < elapsed:
            raise ValueError('Resource sampling order differs')
        elapsed = row['elapsedSeconds']
        values = [row['availableBytes'], *row['cache'].values()]
        temporary = row.get('temporary') if version >= 2 else {'logicalBytes': 0, 'allocatedBytes': 0}
        if not isinstance(temporary, dict) or not {'logicalBytes', 'allocatedBytes'} <= temporary.keys():
            raise ValueError('Missing private temporary resource observation')
        values.extend(temporary.values())
        if any(type(value) is not int or value < 0 for value in values):
            raise ValueError('Invalid resource byte count')
        if (row['availableBytes'] < policy.reserve_bytes
                or max(row['cache']['logicalBytes'] + temporary['logicalBytes'],
                       row['cache']['allocatedBytes'] + temporary['allocatedBytes'])
                > policy.max_cache_bytes):
            raise ValueError('Resource samples exceed limits')
        competition = row.get('competingProcesses') if version == 3 else []
        if not isinstance(competition, list):
            raise ValueError('Invalid competing-process evidence')
        for process in competition:
            if (not isinstance(process, dict)
                    or set(process) != {'pid', 'ppid', 'state', 'executable', 'script', 'role'}
                    or type(process['pid']) is not int or process['pid'] <= 0
                    or type(process['ppid']) is not int or process['ppid'] < 0
                    or not isinstance(process['state'], str) or not process['state']
                    or not isinstance(process['executable'], str) or not process['executable']
                    or '/' in process['executable']
                    or process['script'] not in COMPANION_SCRIPTS
                    or process['role'] not in COMPANION_ROLES):
                raise ValueError('Invalid competing-process evidence')
            observed_competition[(process['pid'], process['script'], process['role'])] = process
        peak_competition = max(peak_competition, len(competition))
    peaks = {
        'minimumAvailableBytes': min(row['availableBytes'] for row in rows),
        'peakCacheLogicalBytes': max(row['cache']['logicalBytes'] for row in rows),
        'peakCacheAllocatedBytes': max(row['cache']['allocatedBytes'] for row in rows),
    }
    if any(type(summary.get(key)) is not int or summary[key] != value for key, value in peaks.items()):
        raise ValueError('Resource summary differs from samples')
    if version >= 2:
        peaks = {
            'peakTemporaryLogicalBytes': max(row['temporary']['logicalBytes'] for row in rows),
            'peakTemporaryAllocatedBytes': max(row['temporary']['allocatedBytes'] for row in rows),
            'peakScratchLogicalBytes': max(row['cache']['logicalBytes'] + row['temporary']['logicalBytes'] for row in rows),
            'peakScratchAllocatedBytes': max(row['cache']['allocatedBytes'] + row['temporary']['allocatedBytes'] for row in rows),
        }
        if any(type(summary.get(key)) is not int or summary[key] != value for key, value in peaks.items()):
            raise ValueError('Temporary resource summary differs from samples')
    if version == 3:
        competition = [observed_competition[key] for key in sorted(observed_competition)]
        if (summary.get('competingProcesses') != competition
                or type(summary.get('peakCompetingProcesses')) is not int
                or summary['peakCompetingProcesses'] != peak_competition):
            raise ValueError('Competing-process summary differs from samples')
        if competition:
            raise ValueError('Resource samples contain competing local inference')


class DiskGuard:
    def __init__(self, work, output, cancel, limits):
        self.work, self.output = Path(work), Path(output)
        self.cancel, self.limits = cancel, limits
        self.stopped = threading.Event()
        self.failure = None
        self.summary = None
        self.stream = None
        self.thread = None
        self.started = time.monotonic()
        self.samples = 0
        self.minimum_free = None
        self.peak_logical = self.peak_allocated = 0
        self.peak_temporary_logical = self.peak_temporary_allocated = 0
        self.peak_scratch_logical = self.peak_scratch_allocated = 0
        self.peak_competing = 0
        self.competing = {}

    def fail(self, message):
        self.failure = self.failure or message
        self.cancel.set()

    def sample(self):
        try:
            started = time.monotonic()
            cache = tree_usage(self.work / 'target')
            incremental = tree_usage(self.work / 'target', ('debug', 'incremental'))
            temporary = tree_usage(self.work / 'tmp')
            competition = competing_processes()
            free = min(available_bytes(self.work), available_bytes(self.output))
            self.minimum_free = free if self.minimum_free is None else min(self.minimum_free, free)
            self.peak_logical = max(self.peak_logical, cache['logicalBytes'])
            self.peak_allocated = max(self.peak_allocated, cache['allocatedBytes'])
            scratch_logical = cache['logicalBytes'] + temporary['logicalBytes']
            scratch_allocated = cache['allocatedBytes'] + temporary['allocatedBytes']
            self.peak_temporary_logical = max(self.peak_temporary_logical, temporary['logicalBytes'])
            self.peak_temporary_allocated = max(self.peak_temporary_allocated, temporary['allocatedBytes'])
            self.peak_scratch_logical = max(self.peak_scratch_logical, scratch_logical)
            self.peak_scratch_allocated = max(self.peak_scratch_allocated, scratch_allocated)
            self.peak_competing = max(self.peak_competing, len(competition))
            for process in competition:
                self.competing[(process['pid'], process['script'], process['role'])] = process
            row = {'utc': datetime.now(timezone.utc).isoformat(),
                   'elapsedSeconds': time.monotonic() - self.started,
                   'availableBytes': free, 'cache': cache, 'incremental': incremental,
                   'temporary': temporary,
                   'competingProcesses': competition,
                   'samplingSeconds': time.monotonic() - started}
            self.stream.write(json.dumps(row) + '\n')
            self.stream.flush()
            self.samples += 1
            if free < self.limits.reserve_bytes:
                self.fail('Free disk below mutation reserve')
            if max(cache['logicalBytes'], cache['allocatedBytes']) > self.limits.max_cache_bytes:
                self.fail('Private mutation cache exceeded limit')
            if max(scratch_logical, scratch_allocated) > self.limits.max_cache_bytes:
                self.fail('Private mutation scratch exceeded limit')
            if competition:
                identities = ', '.join(
                    f"PID {item['pid']} {item['script']} {item['role']}" for item in competition)
                self.fail(f'competing local inference detected: {identities}')
        except Exception as error:
            self.fail(f'Mutation resource sampling failed: {type(error).__name__}: {error}')

    def observe(self):
        while not self.stopped.wait(self.limits.interval_seconds):
            self.sample()
            if self.failure:
                break

    def check(self):
        if self.cancel.is_set() and not self.failure:
            self.fail('Mutation resource observation cancelled')
        if self.failure:
            raise RuntimeError(self.failure)

    def __enter__(self):
        try:
            self.stream = (self.output / 'resources.jsonl').open('x')
            self.sample()
            self.check()
            self.thread = threading.Thread(target=self.observe, name='native-mutation-disk')
            self.thread.start()
            return self
        except BaseException:
            self.cancel.set()
            if self.stream is not None:
                self.finish()
            raise

    def finish(self):
        if self.summary is not None:
            return
        self.stopped.set()
        if self.thread is not None:
            self.thread.join()
        if self.stream is not None:
            self.sample()
            self.stream.close()
        if self.cancel.is_set() and not self.failure:
            self.fail('Mutation resource observation cancelled')
        competition = [self.competing[key] for key in sorted(self.competing)]
        self.summary = {'schemaVersion': SCHEMA_VERSION, 'limits': asdict(self.limits),
                        'workspace': str(self.work), 'samples': self.samples,
                        'minimumAvailableBytes': self.minimum_free,
                        'peakCacheLogicalBytes': self.peak_logical,
                        'peakCacheAllocatedBytes': self.peak_allocated,
                        'peakTemporaryLogicalBytes': self.peak_temporary_logical,
                        'peakTemporaryAllocatedBytes': self.peak_temporary_allocated,
                        'peakScratchLogicalBytes': self.peak_scratch_logical,
                        'peakScratchAllocatedBytes': self.peak_scratch_allocated,
                        'peakCompetingProcesses': self.peak_competing,
                        'competingProcesses': competition,
                        'failure': self.failure, 'withinLimits': self.failure is None,
                        'elapsedSeconds': time.monotonic() - self.started,
                        'limitations': ['Periodic samples may miss brief peaks or overshoot a limit',
                                        'File allocation excludes directory metadata; shared extents may overlap',
                                        'Host free disk includes unrelated activity']}
        temporary = self.output / 'resource-summary.tmp'
        temporary.write_text(json.dumps(self.summary, indent=2) + '\n')
        temporary.replace(self.output / 'resource-summary.json')

    def __exit__(self, kind, value, traceback):
        self.finish()
        if kind is None:
            self.check()
