#!/usr/bin/env python3
"""Regenerate the benchmark's pinned typed FlatBuffers fixture."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "schemas/bench_payload/workload_payload.fbs"
MANIFEST = ROOT / "schemas/wamp_flatbuffers/manifest.json"
GENERATED = (
    ROOT
    / "packages/connectanum_bench/lib/src/bench_payload/generated/"
    / "workload_payload_connectanum.bench_generated.dart"
)
PROJECT_IGNORES = (
    "// ignore_for_file: unnecessary_non_null_assertion, "
    "unnecessary_brace_in_string_interps, unnecessary_library_name, "
    "unused_import, unused_field, unused_element, unused_local_variable, "
    "constant_identifier_names"
)


def project_lint_header(source):
    lines = source.splitlines(keepends=True)
    for index, line in enumerate(lines):
        if line.startswith("// ignore_for_file: "):
            lines[index] = PROJECT_IGNORES + "\n"
            return "".join(lines)
    raise ValueError("flatc output is missing its Dart lint directive")


def generate(flatc):
    manifest = json.loads(MANIFEST.read_text())
    expected = f'flatc version {manifest["flatc"]}'
    actual = subprocess.check_output([flatc, "--version"], text=True).strip()
    if actual != expected:
        raise ValueError(f"Expected {expected}; found {actual}")

    with tempfile.TemporaryDirectory(prefix="connectanum-bench-flatc-") as directory:
        generated = Path(directory) / GENERATED.name
        subprocess.run(
            [flatc, "--dart", "--gen-all", "-o", directory, SCHEMA],
            check=True,
        )
        generated.write_text(project_lint_header(generated.read_text()))
        subprocess.run(
            [
                "dart",
                "format",
                "--language-version",
                manifest["dart_format_language"],
                "--output=write",
                generated,
            ],
            check=True,
        )
        return generated.read_bytes()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flatc", default=os.environ.get("FLATC", "flatc"))
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        expected = generate(args.flatc)
        if args.check:
            if not GENERATED.exists() or GENERATED.read_bytes() != expected:
                raise ValueError(f"Generated benchmark binding is stale: {GENERATED}")
            print("Pinned benchmark FlatBuffers binding is current.")
        else:
            GENERATED.parent.mkdir(parents=True, exist_ok=True)
            GENERATED.write_bytes(expected)
            print(f"Generated {GENERATED.relative_to(ROOT)}")
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
