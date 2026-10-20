#!/usr/bin/env python3
"""Install a hash-pinned ObjectBox engine for adapter tests, never publication."""
from __future__ import annotations

import argparse
import hashlib
import io
import os
from pathlib import Path
import platform
import re
import tarfile
import tempfile
import urllib.request
import zipfile

VERSION = '5.3.2'
ROOT = Path(__file__).resolve().parents[1]
ASSETS = {
    ('Darwin', 'arm64'): ('objectbox-macos-universal.zip', '680c598573ede04b9762565d48d4e161ad286f786f159abb8da89353bfa1d0bc', 'libobjectbox.dylib'),
    ('Darwin', 'x86_64'): ('objectbox-macos-universal.zip', '680c598573ede04b9762565d48d4e161ad286f786f159abb8da89353bfa1d0bc', 'libobjectbox.dylib'),
    ('Linux', 'x86_64'): ('objectbox-linux-x64.tar.gz', '6dbb5450c36dd11ee9074f16ecc61e79b45ff43c2082934601f3166b39c8a613', 'libobjectbox.so'),
    ('Linux', 'aarch64'): ('objectbox-linux-aarch64.tar.gz', 'bdfbfbf4971057e11018ca6645697d8a40ebc7df56ccde63397cbb0e0609c0e8', 'libobjectbox.so'),
    ('Windows', 'amd64'): ('objectbox-windows-x64.zip', '57d7db013bbb46efe415307c9f3baf7564bdc40818ee1f1c42046f4241403d63', 'objectbox.dll'),
}


def engine_bytes(archive: bytes, archive_name: str, library_name: str) -> bytes:
    if archive_name.endswith('.zip'):
        with zipfile.ZipFile(io.BytesIO(archive)) as source:
            members = [m for m in source.infolist()
                       if not m.is_dir() and Path(m.filename).name == library_name]
            if len(members) != 1:
                raise ValueError('Expected one native ObjectBox library in the archive')
            return source.read(members[0])
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as source:
        members = [m for m in source.getmembers() if m.isfile()
                   and Path(m.name).name == library_name]
        if not members:
            versioned = re.compile(re.escape(library_name) + r'\.[0-9.]+')
            members = [m for m in source.getmembers() if m.isfile()
                       and versioned.fullmatch(Path(m.name).name)]
        if len(members) != 1:
            raise ValueError('Expected one native ObjectBox library in the archive')
        stream = source.extractfile(members[0])
        if stream is None:
            raise ValueError('Native library has no archive contents')
        return stream.read()


def install(destination: Path, cache: Path) -> Path:
    machine = platform.machine().lower()
    key = (platform.system(), machine)
    if key not in ASSETS:
        raise RuntimeError(f'ObjectBox test engine is not configured for {key}')
    name, expected, library_name = ASSETS[key]
    cache.mkdir(parents=True, exist_ok=True)
    archive_path = cache / name
    if archive_path.exists():
        archive = archive_path.read_bytes()
    else:
        url = f'https://github.com/objectbox/objectbox-c/releases/download/v{VERSION}/{name}'
        with urllib.request.urlopen(url, timeout=60) as response:
            archive = response.read()
    if hashlib.sha256(archive).hexdigest() != expected:
        raise ValueError('ObjectBox test archive SHA-256 mismatch; no library installed')
    archive_path.write_bytes(archive)
    library = engine_bytes(archive, name, library_name)
    if not library:
        raise ValueError('ObjectBox test engine is empty')
    destination.mkdir(parents=True, exist_ok=True)
    target = destination / library_name
    with tempfile.NamedTemporaryFile(dir=destination, delete=False) as temporary:
        temporary.write(library)
        temporary_path = Path(temporary.name)
    try:
        os.replace(temporary_path, target)
    finally:
        temporary_path.unlink(missing_ok=True)
    return target


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path,
                        default=ROOT / 'packages/connectanum_objectbox_adapter/lib')
    parser.add_argument('--cache', type=Path,
                        default=ROOT / 'out/objectbox-test-engine' / VERSION)
    args = parser.parse_args()
    path = install(args.destination.resolve(), args.cache.resolve())
    print(f'ObjectBox {VERSION} test engine: {path}')


if __name__ == '__main__':
    main()
