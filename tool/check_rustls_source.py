#!/usr/bin/env python3
"""Verify the pinned Rustls observer sources and restored upstream test fixtures."""

import hashlib
import json
from pathlib import Path


def check(root: Path) -> list[str]:
    manifest = json.loads((root / "rustls-source-manifest.json").read_text())
    failures = []
    expected = manifest["files"]
    for name, entry in expected.items():
        path = root / name
        if path.is_symlink() or not path.is_file():
            failures.append(f"missing or non-regular source: {name}")
        elif hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
            failures.append(f"source digest mismatch: {name}")
    actual = set()
    for directory in ("rustls", "test-ca", "fuzz"):
        for path in (root / directory).rglob("*"):
            relative = path.relative_to(root)
            if relative.parts[:2] == ("rustls", "target"):
                continue
            if relative == Path("rustls/Cargo.lock"):
                continue
            if path.is_file() or path.is_symlink():
                actual.add(relative.as_posix())
    failures.extend(f"unexpected source: {name}" for name in sorted(actual - expected.keys()))
    patched = sorted(
        name for name, entry in expected.items()
        if entry["upstream_sha256"] is not None
        and entry["sha256"] != entry["upstream_sha256"]
    )
    if patched != manifest["modified_upstream_files"]:
        failures.append("modified upstream file list disagrees with digests")
    return failures


def main() -> int:
    root = Path(__file__).resolve().parent.parent / "native/transport/vendor"
    failures = check(root)
    if failures:
        print("\n".join(failures))
        return 1
    print("Pinned Rustls sources, observer and upstream fixtures verified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
