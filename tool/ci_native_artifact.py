#!/usr/bin/env python3
"""Same-run ffi-test reuse with explicit source, toolchain and binary identity."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identity():
    files = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', 'native/transport'],
                                    cwd=ROOT).decode().split('\0')
    return {
        'schemaVersion': 1,
        'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'rustc': subprocess.check_output(['rustc', '-Vv'], text=True).strip(),
        'cargo': subprocess.check_output(['cargo', '-V'], text=True).strip(),
        'system': platform.system(), 'machine': platform.machine(),
        'profile': 'release', 'features': ['ffi-test'],
        'rustflags': os.environ.get('RUSTFLAGS', ''),
        'encodedRustflags': os.environ.get('CARGO_ENCODED_RUSTFLAGS', ''),
        'buildTarget': os.environ.get('CARGO_BUILD_TARGET', ''),
        'profileOverrides': {name: value for name, value in sorted(os.environ.items())
                             if name.startswith('CARGO_PROFILE_RELEASE_')},
        'sourceHashes': {name: sha256(ROOT / name) for name in sorted(files) if name},
    }


def record(directory, library):
    directory.mkdir(parents=True, exist_ok=False)
    shutil.copy2(library, directory / 'libct_ffi.so')
    shutil.copy2(ROOT / 'native/transport/Cargo.lock', directory / 'Cargo.lock')
    manifest = {**identity(), 'librarySha256': sha256(directory / 'libct_ffi.so'),
                'cargoLockSha256': sha256(directory / 'Cargo.lock')}
    (directory / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


def verify(directory, *, prepare=False):
    manifest = json.loads((directory / 'manifest.json').read_text())
    expected = {**identity(), 'librarySha256': sha256(directory / 'libct_ffi.so'),
                'cargoLockSha256': sha256(directory / 'Cargo.lock')}
    if manifest != expected:
        raise ValueError('Shared ffi-test library source, build mode or digest does not match')
    lock = ROOT / 'native/transport/Cargo.lock'
    if lock.exists() and sha256(lock) != expected['cargoLockSha256']:
        raise ValueError('Resolved native dependency lock differs from the build artifact')
    if not lock.exists():
        if not prepare:
            raise ValueError('Prepare the shared native dependency lock before reuse')
        shutil.copy2(directory / 'Cargo.lock', lock)
    if prepare:
        # Benchmarks deliberately clear CONNECTANUM_NATIVE_LIB and discover the
        # canonical test-enabled build. Preserve that process isolation contract.
        name = {'Linux': 'libct_ffi.so', 'Darwin': 'libct_ffi.dylib',
                'Windows': 'ct_ffi.dll'}[expected['system']]
        destination = ROOT / 'native/transport/target/ffi-test/release' / name
        if not destination.is_file() or sha256(destination) != expected['librarySha256']:
            destination.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=destination.parent,
                    prefix=f'.{name}.', delete=False) as handle:
                staged = Path(handle.name)
            try:
                shutil.copy2(directory / 'libct_ffi.so', staged)
                if sha256(staged) != expected['librarySha256']:
                    raise ValueError('Prepared native library digest differs from the artifact')
                staged.replace(destination)
            finally:
                staged.unlink(missing_ok=True)
        return destination.resolve()
    return (directory / 'libct_ffi.so').resolve()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('record', 'verify', 'prepare'))
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--library', type=Path)
    args = parser.parse_args()
    if args.mode == 'record':
        if args.library is None:
            parser.error('--library is required when recording')
        record(args.directory, args.library)
    else:
        print(verify(args.directory, prepare=args.mode == 'prepare'))


if __name__ == '__main__':
    main()
