#!/usr/bin/env python3
"""Verify the pinned TLS observer sources and restored upstream test fixtures."""

import hashlib
import json
from pathlib import Path


def check(
    root: Path,
    manifest_name: str = "rustls-source-manifest.json",
    directories: tuple[str, ...] = ("rustls", "test-ca", "fuzz"),
    ignored_files: tuple[str, ...] = ("rustls/Cargo.lock",),
) -> list[str]:
    manifest = json.loads((root / manifest_name).read_text())
    failures = []
    expected = manifest["files"]
    for name, entry in expected.items():
        path = root / name
        if path.is_symlink() or not path.is_file() or any(
            (root / parent).is_symlink() for parent in Path(name).parents
            if parent != Path(".")
        ):
            failures.append(f"missing or non-regular source: {name}")
        elif hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
            failures.append(f"source digest mismatch: {name}")
    actual = set()
    for directory in directories:
        for path in (root / directory).rglob("*"):
            relative = path.relative_to(root)
            if relative.parts[:2] == (directory, "target"):
                continue
            if relative.as_posix() in ignored_files:
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
    failures.extend(check(root, "tokio-rustls-source-manifest.json", ("tokio-rustls",), ()))
    if failures:
        print("\n".join(failures))
        return 1
    print("Pinned Rustls/Tokio-Rustls sources, observers and upstream fixtures verified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
