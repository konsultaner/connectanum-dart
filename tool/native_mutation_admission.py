#!/usr/bin/env python3
"""Budget private caches before startup; runtime guards still enforce limits."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import stat
import tempfile

from native_mutation_resources import DiskLimits, add_arguments, available_bytes, gib_bytes


def filesystem_device(path):
    info = path.stat()
    if not stat.S_ISDIR(info.st_mode):
        raise NotADirectoryError(str(path))
    return info.st_dev


def plan_admission(scratch, evidence, limits, workers, evidence_bytes=1024 ** 3):
    if (not isinstance(limits, DiskLimits) or type(workers) is not int or workers < 1
            or type(evidence_bytes) is not int or evidence_bytes < 0):
        raise ValueError('Require disk limits, positive workers and nonnegative evidence allowance')
    cache_budget = workers * limits.max_cache_bytes
    filesystems = {}
    for role, location, budget in [('scratch', scratch, cache_budget),
                                   ('evidence', evidence, evidence_bytes)]:
        path = Path(location).resolve()
        device = filesystem_device(path)
        free = available_bytes(path)
        if type(free) is not int or free < 0:
            raise ValueError('Invalid available disk byte count')
        filesystem = filesystems.setdefault(device, {
            'device': device, 'roles': [], 'paths': [], 'availableBytes': free,
            'requiredBytes': limits.reserve_bytes})
        filesystem['roles'].append(role)
        filesystem['paths'].append(str(path))
        filesystem['availableBytes'] = min(filesystem['availableBytes'], free)
        filesystem['requiredBytes'] += budget
    observations = list(filesystems.values())
    for row in observations:
        row['admitted'] = row['availableBytes'] >= row['requiredBytes']
    return {'schemaVersion': 1, 'observationOnly': True,
            'utc': datetime.now(timezone.utc).isoformat(),
            'admitted': all(row['admitted'] for row in observations),
            'workers': workers, 'reserveBytes': limits.reserve_bytes,
            'perWorkerCacheBytes': limits.max_cache_bytes, 'cacheBudgetBytes': cache_budget,
            'evidenceAllowanceBytes': evidence_bytes, 'filesystems': observations,
            'caveats': ['This observation does not reserve disk or replace runtime guards',
                        'Evidence allowance and sampled limits cannot prevent brief overshoot',
                        'Distinct filesystem devices may still share underlying storage capacity']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scratch', type=Path, default=Path(tempfile.gettempdir()))
    parser.add_argument('--evidence', type=Path, required=True,
                        help='Existing directory on the evidence filesystem')
    parser.add_argument('--workers', type=int, default=4)
    parser.add_argument('--evidence-allowance-gib', type=gib_bytes, default=1024 ** 3)
    add_arguments(parser)
    args = parser.parse_args()
    try:
        report = plan_admission(args.scratch, args.evidence,
                                DiskLimits(args.disk_reserve_gib, args.max_cache_gib),
                                args.workers, args.evidence_allowance_gib)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(json.dumps(report, indent=2))
    return 0 if report['admitted'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
