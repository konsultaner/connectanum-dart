#!/usr/bin/env python3
"""Reclaim verified-unused build caches before a native mutation campaign."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import subprocess
import time


FIXED_CACHE = Path('native/bench/target')
STAGE_PATTERN = re.compile(
    r'\Aconnectanum-flatbuffers-[A-Za-z0-9_-]+-stage-[A-Za-z0-9_-]+\Z'
)
MINIMUM_STAGE_AGE_SECONDS = 60 * 60
CARGO_CACHE_SIGNATURE = 'Signature: 8a477f597d28d172789f06886806bc55'


def _absolute(path):
    return Path(os.path.abspath(os.fspath(path)))


def _sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 ** 2), b''):
            digest.update(chunk)
    return digest.hexdigest()


def _mode(path):
    return stat.S_IMODE(path.lstat().st_mode)


def _path_components(path, boundary):
    current = path
    while True:
        yield current
        if current == boundary:
            return
        if current.parent == current:
            raise ValueError(f'{path} is outside {boundary}')
        current = current.parent


def _require_plain_components(path, boundary):
    for component in _path_components(path, boundary):
        if component.is_symlink():
            raise ValueError(f'Cache path traverses symlink: {component}')
        if component.lstat().st_uid != os.getuid():
            raise ValueError(f'Cache path is not owned by the current user: {component}')


def _require_cargo_cache(path):
    marker = path / 'CACHEDIR.TAG'
    try:
        descriptor = os.open(
            marker,
            os.O_RDONLY | os.O_CLOEXEC | getattr(os, 'O_NOFOLLOW', 0),
        )
    except (FileNotFoundError, OSError) as error:
        raise ValueError(f'Missing Cargo cache tag: {marker}') from error
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
            raise ValueError(f'Cargo cache tag is not an owned regular file: {marker}')
        data = os.read(descriptor, 4096)
    finally:
        os.close(descriptor)
    first_line = data.decode('utf-8', errors='strict').splitlines()[0] if data else ''
    if first_line != CARGO_CACHE_SIGNATURE:
        raise ValueError(f'Invalid Cargo cache tag: {marker}')


def _directory_identity(path):
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode):
        raise ValueError(f'Cache identity is not a directory: {path}')
    return {
        'device': info.st_dev,
        'inode': info.st_ino,
        'owner': info.st_uid,
        'mode': stat.S_IMODE(info.st_mode),
    }


def _git_output(repo, *args):
    return subprocess.check_output(
        ['git', *args],
        cwd=repo,
        timeout=30,
    )


def tracked_inventory(repo):
    values = {}
    names = _git_output(repo, 'ls-files', '-z').decode().split('\0')
    for name in sorted(item for item in names if item):
        path = repo / name
        if path.is_symlink():
            values[name] = {
                'link': os.readlink(path),
                'mode': _mode(path),
            }
        elif path.is_file():
            values[name] = {
                'sha256': _sha256(path),
                'mode': _mode(path),
            }
        else:
            raise ValueError(f'Tracked path is not a regular file or symlink: {name}')
    if not values:
        raise ValueError('Missing tracked-file inventory')
    return values


def _inventory_entry(path):
    if path.is_symlink():
        return {'link': os.readlink(path), 'mode': _mode(path)}
    if path.is_file():
        return {'sha256': _sha256(path), 'mode': _mode(path)}
    if path.is_dir():
        return {'directoryMode': _mode(path)}
    raise ValueError(f'Unsupported protected filesystem entry: {path}')


def inventory_tree_excluding(root, excluded):
    root = _absolute(root)
    excluded = _absolute(excluded)
    values = {}

    def visit(directory):
        for entry in sorted(os.scandir(directory), key=lambda item: item.name):
            path = Path(entry.path)
            if path == excluded:
                continue
            relative = str(path.relative_to(root))
            values[relative] = _inventory_entry(path)
            if entry.is_dir(follow_symlinks=False):
                visit(path)

    visit(root)
    return values


def _tree_size(path):
    seen = set()

    def allocated(candidate):
        info = candidate.lstat()
        identity = (info.st_dev, info.st_ino)
        if identity in seen:
            return 0
        seen.add(identity)
        blocks = getattr(info, 'st_blocks', (info.st_size + 511) // 512)
        return blocks * 512

    total = allocated(path)
    for directory, names, files in os.walk(path, followlinks=False):
        for name in names:
            candidate = Path(directory) / name
            total += allocated(candidate)
        for name in files:
            candidate = Path(directory) / name
            total += allocated(candidate)
    return total


def _tracked_under(repo, cache):
    relative = str(cache.relative_to(repo))
    raw = _git_output(repo, 'ls-files', '-z', '--', relative).decode()
    return sorted(item for item in raw.split('\0') if item)


def validate_selected_caches(repo, temp_root, paths):
    repo = _absolute(repo)
    temp_root = _absolute(temp_root)
    selected = [_absolute(path) for path in paths]
    if len(set(selected)) != len(selected):
        raise ValueError('Duplicate cache path')

    fixed = repo / FIXED_CACHE
    validated = []
    for path in selected:
        if path == fixed:
            boundary = repo
            protected_root = repo
            kind = 'repository-cargo-target'
        elif (
            path.name == 'target'
            and path.parent.parent == temp_root
            and STAGE_PATTERN.fullmatch(path.parent.name)
        ):
            boundary = temp_root
            protected_root = path.parent
            kind = 'stale-flatbuffers-stage-target'
        else:
            raise ValueError(f'Cache path is outside the allowlist: {path}')

        if path.is_symlink():
            raise ValueError(f'Cache path is a symlink: {path}')
        if not path.is_dir():
            raise ValueError(f'Cache path is not a directory: {path}')
        _require_plain_components(path, boundary)
        _require_cargo_cache(path)
        if path.is_relative_to(repo):
            tracked = _tracked_under(repo, path)
            if tracked:
                raise ValueError(f'Generated cache contains tracked paths: {tracked}')
        validated.append(
            {
                'path': path,
                'kind': kind,
                'protectedRoot': protected_root,
                'identity': _directory_identity(path),
            }
        )
    return validated


def discover_caches(repo, temp_root, *, now=None):
    repo = _absolute(repo)
    temp_root = _absolute(temp_root)
    now = time.time() if now is None else now
    selected = []
    missing = []
    recent = []

    fixed = repo / FIXED_CACHE
    if fixed.exists() or fixed.is_symlink():
        selected.append(fixed)
    else:
        missing.append(str(FIXED_CACHE))

    if temp_root.is_symlink() or not temp_root.is_dir():
        raise ValueError(f'Temporary root is not a plain directory: {temp_root}')
    if temp_root.lstat().st_uid != os.getuid():
        raise ValueError(f'Temporary root is not owned by the current user: {temp_root}')
    for stage in sorted(temp_root.iterdir()):
        if not STAGE_PATTERN.fullmatch(stage.name):
            continue
        if stage.is_symlink() or not stage.is_dir():
            raise ValueError(f'FlatBuffers stage is not a plain directory: {stage}')
        cache = stage / 'target'
        if not (cache.exists() or cache.is_symlink()):
            continue
        age = now - stage.stat().st_mtime
        if age < MINIMUM_STAGE_AGE_SECONDS:
            recent.append({'path': str(cache), 'ageSeconds': age})
        else:
            selected.append(cache)
    return selected, missing, recent


def require_unused(root):
    root = _absolute(root)
    process_table = subprocess.check_output(
        ['ps', '-axo', 'pid=,command='],
        text=True,
        timeout=10,
    )
    for line in process_table.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) != 2:
            continue
        pid, command = parts
        if int(pid) == os.getpid():
            continue
        try:
            tokens = shlex.split(command)
        except ValueError:
            tokens = command.split()
        for token in tokens:
            token = token.split('=', 1)[-1] if '=' in token else token
            if not token.startswith('/'):
                continue
            candidate = _absolute(token)
            if candidate == root or candidate.is_relative_to(root):
                raise RuntimeError(f'Generated cache has a live command user: {pid}')

    result = subprocess.run(
        ['lsof', '-n', '-P', '-u', str(os.getuid()), '-Fpn'],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        raise RuntimeError(f'lsof failed while checking cache users: {result.returncode}')
    for line in result.stdout.splitlines():
        if not line.startswith('n/'):
            continue
        raw = line[1:].removesuffix(' (deleted)')
        candidate = _absolute(raw)
        if candidate == root or candidate.is_relative_to(root):
            raise RuntimeError('Generated cache has a live open-file/cwd user')


def _write_json_atomic(path, value):
    temporary = path.with_suffix(path.suffix + '.tmp')
    try:
        descriptor = os.open(
            temporary,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0),
            0o600,
        )
        with os.fdopen(descriptor, 'w') as destination:
            json.dump(value, destination, indent=2)
            destination.write('\n')
            destination.flush()
            os.fsync(destination.fileno())
        os.replace(temporary, path)
    finally:
        if temporary.exists() or temporary.is_symlink():
            temporary.unlink()


def _reserve_proof(path, value):
    descriptor = os.open(
        path,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0),
        0o600,
    )
    with os.fdopen(descriptor, 'w') as destination:
        json.dump(value, destination, indent=2)
        destination.write('\n')
        destination.flush()
        os.fsync(destination.fileno())


def clean_owned_caches(repo, temp_root, proof, *, now=None):
    repo = _absolute(repo)
    temp_root = _absolute(temp_root)
    proof = _absolute(proof)
    if proof.exists() or proof.is_symlink():
        raise FileExistsError(proof)
    paths, missing, recent = discover_caches(repo, temp_root, now=now)
    candidates = validate_selected_caches(repo, temp_root, paths)
    tracked_before = tracked_inventory(repo)
    stage_before = {}
    for candidate in candidates:
        if candidate['kind'] == 'stale-flatbuffers-stage-target':
            stage = candidate['protectedRoot']
            stage_before[str(stage)] = inventory_tree_excluding(stage, candidate['path'])

    available_before = shutil.disk_usage(repo).free
    report = {
        'schema': 1,
        'state': 'planned',
        'repo': str(repo),
        'temporaryRoot': str(temp_root),
        'availableBefore': available_before,
        'trackedHashes': tracked_before,
        'missing': missing,
        'recentStageCaches': recent,
        'cleaned': [],
    }
    proof.parent.mkdir(parents=True, exist_ok=True)
    _reserve_proof(proof, report)

    try:
        for candidate in candidates:
            path = candidate['path']
            protected_root = candidate['protectedRoot']
            inspect_root = protected_root if candidate['kind'].startswith('stale-') else path
            require_unused(inspect_root)
            size = _tree_size(path)
            _require_cargo_cache(path)
            if _directory_identity(path) != candidate['identity']:
                raise RuntimeError(f'Cache identity changed before cleanup: {path}')
            quarantine = path.with_name(f'.{path.name}.connectanum-cleanup-{os.getpid()}')
            if quarantine.exists() or quarantine.is_symlink():
                raise RuntimeError(f'Cleanup quarantine already exists: {quarantine}')
            path.rename(quarantine)
            try:
                if _directory_identity(quarantine) != candidate['identity']:
                    raise RuntimeError(f'Cache identity changed during quarantine: {path}')
                require_unused(quarantine)
            except BaseException:
                if not path.exists() and not path.is_symlink():
                    quarantine.rename(path)
                raise
            shutil.rmtree(quarantine)
            if candidate['kind'] == 'stale-flatbuffers-stage-target':
                expected = stage_before[str(protected_root)]
                if inventory_tree_excluding(protected_root, path) != expected:
                    raise RuntimeError(
                        f'Protected FlatBuffers stage content changed: {protected_root}'
                    )
            report['cleaned'].append(
                {
                    'path': str(path),
                    'kind': candidate['kind'],
                    'sourceIdentity': candidate['identity'],
                    'allocatedBytesBefore': size,
                }
            )

        tracked_after = tracked_inventory(repo)
        if tracked_after != tracked_before:
            raise RuntimeError('Tracked source/test/tool inventory changed during cleanup')
        available_after = shutil.disk_usage(repo).free
        report.update(
            state='completed',
            trackedHashesUnchanged=True,
            availableAfter=available_after,
            observedSharedFreeDelta=available_after - available_before,
        )
        _write_json_atomic(proof, report)
        return report
    except BaseException as error:
        report.update(
            state='failed',
            errorType=type(error).__name__,
            error=str(error),
            availableAfterFailure=shutil.disk_usage(repo).free,
        )
        _write_json_atomic(proof, report)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--temp-root', type=Path, required=True)
    parser.add_argument('--proof', type=Path, required=True)
    args = parser.parse_args()
    result = clean_owned_caches(args.repo, args.temp_root, args.proof)
    visible = {key: value for key, value in result.items() if key != 'trackedHashes'}
    print(json.dumps(visible, sort_keys=True))


if __name__ == '__main__':
    main()
