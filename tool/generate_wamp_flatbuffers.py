#!/usr/bin/env python3
"""Regenerate pinned WAMP bindings and compiler-produced interoperability fixtures."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from wamp_flatbuffers_validation_schema import validation_schema, rust_validation_schema

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = Path("schemas/wamp_flatbuffers")
DART = Path("packages/connectanum_core/lib/src/serializer/flatbuffers/generated")
RUST = Path("native/transport/ct_core/src/wamp/flatbuffers_generated.rs")
RUST_SCHEMA = RUST.with_name("flatbuffers_schema.rs")
FIXTURES = SCHEMA / "fixtures"
DART_FIXTURES = Path("packages/connectanum_core/test/serializer/flatbuffers_fixture_data.dart")
ORDER = ("types", "roles", "auth", "session", "pubsub", "rpc", "wamp")
EXTENSION = (
    "    msg: AnyMessage (required);\n\n"
    "    // Optional CBOR options/details metadata; requires negotiated support.\n"
    "    metadata: [ubyte];"
)


def verify_inputs(root):
    manifest = json.loads((root / SCHEMA / "manifest.json").read_text())
    for name, expected in manifest["upstream"]["sha256"].items():
        actual = hashlib.sha256((root / SCHEMA / "upstream" / name).read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError(f"Pinned upstream input changed: {name}")
    return manifest


def combined_schema(root, extensions=True):
    result = "// Derived from pinned upstream schemas; regenerate with tool/generate_wamp_flatbuffers.py.\n"
    for name in ORDER:
        source = (root / SCHEMA / "upstream" / f"{name}.fbs").read_text()
        source = "\n".join(line for line in source.splitlines() if not line.startswith("include ")) + "\n"
        if name == "session" and extensions:
            # Authentication method names are protocol control strings, not
            # members of CHALLENGE.extra. Append after every upstream slot.
            original = "table Challenge\n{"
            start = source.index(original)
            end = source.index("\n}", start)
            source = (source[:end] +
                      "\n\n    // Custom method name; requires negotiated metadata capability.\n"
                      "    method_name: string;" + source[end:])
        if name == "wamp" and extensions:
            if source.count("    msg: AnyMessage (required);") != 1:
                raise ValueError("Upstream Message layout changed")
            source = source.replace("    msg: AnyMessage (required);", EXTENSION)
            # Existing Connectanum sessions support HEARTBEAT (WAMP ID 7).
            # Append its union alternative; never renumber upstream members.
            source = source.replace("    Yield\n", "    Yield,\n    Heartbeat\n")
            source += (
                "\n// Connectanum HEARTBEAT extension (requires metadata capability).\n"
                "table Heartbeat {\n"
                "    ping: uint64;\n    incoming: uint64;\n    outgoing: uint64;\n"
                "    // Bits 1/2/4 distinguish absent controls from explicit zero.\n"
                "    presence: ubyte = 7;\n}\n"
            )
        result += source
    return result


def compiler_version(flatc):
    return subprocess.check_output([flatc, "--version"], text=True).strip()


def run(args):
    subprocess.run([str(arg) for arg in args], check=True)


def generate(root, flatc, output):
    manifest = verify_inputs(root)
    wanted = f'flatc version {manifest["flatc"]}'
    actual = compiler_version(flatc)
    if actual != wanted:
        raise ValueError(f"Expected {wanted}; found {actual}")
    schema = output / SCHEMA / "wamp.fbs"
    schema.parent.mkdir(parents=True)
    schema.write_text(combined_schema(root))
    dart = output / DART
    rust = output / RUST.parent
    dart.mkdir(parents=True)
    rust.mkdir(parents=True)
    license = (root / SCHEMA / "upstream/LICENSE").read_bytes()
    (dart / "UPSTREAM_LICENSE").write_bytes(license)
    rust_license = RUST.with_name("flatbuffers_UPSTREAM_LICENSE")
    (output / rust_license).write_bytes(license)
    run([flatc, "--dart", "--gen-all", "-o", dart, schema])
    (dart / "validation_schema.dart").write_text(validation_schema(schema.read_text()))
    (output / RUST_SCHEMA).write_text(rust_validation_schema(schema.read_text()))
    run(["rustfmt", "--edition", "2021", output / RUST_SCHEMA])
    for path in dart.glob("*.dart"):
        source = path.read_text()
        source = source.replace(
            "// ignore_for_file: ",
            "// ignore_for_file: unnecessary_non_null_assertion, unnecessary_brace_in_string_interps, unnecessary_library_name, ",
            1,
        )
        source = source.replace(
            "import 'package:flat_buffers/flat_buffers.dart' as fb;",
            "import 'package:flat_buffers/flat_buffers.dart' as fb;\n"
            "import '../runtime.dart' as wamp_runtime;",
        )
        source = source.replace("fb.BufferContext.fromBytes(bytes)", "wamp_runtime.bufferContext(bytes)")
        source = source.replace("fb.Uint64Reader()", "wamp_runtime.WampUint64Reader()")
        source = source.replace("fb.Uint64ListReader()", "fb.ListReader<int>(wamp_runtime.WampUint64Reader())")
        source = source.replace("fb.Builder(", "wamp_runtime.WampFlatBufferBuilder(")
        path.write_text(source)
    run(["dart", "format", "--language-version", manifest["dart_format_language"],
         "--output=write", dart])
    run([flatc, "--rust", "--gen-all", "-o", rust, schema])
    (rust / "wamp_generated.rs").rename(output / RUST)
    # flatc 25.9.23 emits unqualified Result in a namespace containing WAMP's
    # Result table. Qualify only generated function return types.
    rust_source = (output / RUST).read_text().replace(
        "-> Result<", "-> ::core::result::Result<"
    )
    rust_source = rust_source.replace("Result<Message, ", "Result<Message<'_>, ")
    rust_source = rust_source.replace("-> Message {", "-> Message<'_> {")
    (output / RUST).write_text(rust_source)
    run(["rustfmt", "--edition", "2021", output / RUST])
    # flatc's compatibility check must accept the append-only root field.
    run([flatc, "--conform", root / SCHEMA / "upstream/wamp.fbs",
         "--schema", "-b", "-o", output / "conform", schema])
    cases = json.loads((root / SCHEMA / "fixtures.json").read_text())
    target = output / FIXTURES
    target.mkdir(parents=True)
    json_source = output / "json"
    json_source.mkdir()
    for case in cases:
        source = json_source / (case["name"] + ".json")
        source.write_text(json.dumps(case["wire"]))
        run([flatc, "--binary", "--strict-json", "-o", target, schema, source])
    import base64
    fixture_data = [
        dict(case, base64=base64.b64encode((target / (case["name"] + ".bin")).read_bytes()).decode())
        for case in cases
    ]
    helper = output / DART_FIXTURES
    helper.parent.mkdir(parents=True, exist_ok=True)
    helper.write_text(
        "// Generated by tool/generate_wamp_flatbuffers.py; do not edit.\n"
        "const flatBuffersFixtureJson = r'''\n" + json.dumps(fixture_data, indent=2) + "\n''';\n"
    )
    run(["dart", "format", "--language-version", manifest["dart_format_language"],
         "--output=write", helper])
    generated = [SCHEMA / "wamp.fbs", RUST, RUST_SCHEMA, DART_FIXTURES,
                 DART / "UPSTREAM_LICENSE", rust_license]
    generated += [path.relative_to(output) for path in sorted(dart.glob("*.dart"))]
    generated += [path.relative_to(output) for path in sorted(target.glob("*.bin"))]
    return generated


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flatc", default=os.environ.get("FLATC", "flatc"))
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--verify-inputs-only", action="store_true")
    args = parser.parse_args()
    try:
        verify_inputs(ROOT)
        if args.verify_inputs_only:
            print("Pinned upstream schema checksums verified.")
            return 0
        with tempfile.TemporaryDirectory(prefix="connectanum-flatbuffers-") as directory:
            output = Path(directory)
            generated = generate(ROOT, args.flatc, output)
            stale = []
            for relative in generated:
                expected = (output / relative).read_bytes()
                target = ROOT / relative
                if args.check:
                    if not target.exists() or target.read_bytes() != expected:
                        stale.append(str(relative))
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(expected)
            if stale:
                raise ValueError("Stale generated artifacts: " + ", ".join(stale))
            print(f'{"Verified" if args.check else "Generated"} {len(generated)} FlatBuffers artifacts.')
            return 0
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
