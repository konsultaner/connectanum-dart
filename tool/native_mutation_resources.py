#!/usr/bin/env python3
"""Observe only private mutation caches; exhaustion cancels, never earns kills."""

import argparse
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import json
import hashlib
import math
import os
from pathlib import Path
import stat
import threading
import time


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
    if (summary.get('schemaVersion') != 1 or summary.get('withinLimits') is not True
            or summary.get('failure') is not None or summary.get('limits') != limits
            or summary.get('samples') != len(rows) or len(rows) < 2):
        raise ValueError('Resource observation did not finish within limits')
    elapsed = -1
    for row in rows:
        for value in (row['elapsedSeconds'], row['samplingSeconds']):
            if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
                raise ValueError('Invalid resource timing')
        if row['elapsedSeconds'] < elapsed:
            raise ValueError('Resource sampling order differs')
        elapsed = row['elapsedSeconds']
        values = [row['availableBytes'], *row['cache'].values()]
        if any(type(value) is not int or value < 0 for value in values):
            raise ValueError('Invalid resource byte count')
        if (row['availableBytes'] < policy.reserve_bytes
                or max(row['cache']['logicalBytes'], row['cache']['allocatedBytes'])
                > policy.max_cache_bytes):
            raise ValueError('Resource samples exceed limits')
    if (summary['minimumAvailableBytes'] != min(row['availableBytes'] for row in rows)
            or summary['peakCacheLogicalBytes'] != max(row['cache']['logicalBytes'] for row in rows)
            or summary['peakCacheAllocatedBytes'] != max(row['cache']['allocatedBytes'] for row in rows)):
        raise ValueError('Resource summary differs from samples')


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

    def fail(self, message):
        self.failure = self.failure or message
        self.cancel.set()

    def sample(self):
        try:
            started = time.monotonic()
            cache = tree_usage(self.work / 'target')
            incremental = tree_usage(self.work / 'target', ('debug', 'incremental'))
            free = min(available_bytes(self.work), available_bytes(self.output))
            self.minimum_free = free if self.minimum_free is None else min(self.minimum_free, free)
            self.peak_logical = max(self.peak_logical, cache['logicalBytes'])
            self.peak_allocated = max(self.peak_allocated, cache['allocatedBytes'])
            row = {'utc': datetime.now(timezone.utc).isoformat(),
                   'elapsedSeconds': time.monotonic() - self.started,
                   'availableBytes': free, 'cache': cache, 'incremental': incremental,
                   'samplingSeconds': time.monotonic() - started}
            self.stream.write(json.dumps(row) + '\n')
            self.stream.flush()
            self.samples += 1
            if free < self.limits.reserve_bytes:
                self.fail('Free disk below mutation reserve')
            if max(cache['logicalBytes'], cache['allocatedBytes']) > self.limits.max_cache_bytes:
                self.fail('Private mutation cache exceeded limit')
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
        self.summary = {'schemaVersion': 1, 'limits': asdict(self.limits),
                        'workspace': str(self.work), 'samples': self.samples,
                        'minimumAvailableBytes': self.minimum_free,
                        'peakCacheLogicalBytes': self.peak_logical,
                        'peakCacheAllocatedBytes': self.peak_allocated,
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
