#!/usr/bin/env python3
"""Build an exact-source shadow for logical MQTT copy-request diagnostics.

This module never edits the checked-out runtime. Counters describe explicit
constructor/copy requests, not physical heap allocation, RSS or timed parity.
"""
import argparse
import difflib
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile
from urllib.parse import unquote, urljoin, urlparse

ROOT = Path(__file__).resolve().parents[1]
SOURCE = "ad48d679b24a371cca37ad9397a64b261008f57c"
ARCHIVE_SHA256 = "a20349a557931235c5a1ca7f3a299a31bb3a0fc4812d15f4d3e2c5cfbcc8a0ad"
FRAME = "packages/connectanum_core/lib/src/mqtt/frame_codec.dart"
NATIVE = "packages/connectanum_router/lib/src/native/runtime.dart"
BROKER = "packages/connectanum_router/benchmark/mqtt_native_router_server.dart"
COUNTER = "packages/connectanum_core/lib/src/mqtt/dart_copy_census.dart"
SOURCE_HASHES = {
    FRAME: "f37aeecbcdd290ff036060544a760d440e98c25540a4bb48437d3a8c1252e53d",
    NATIVE: "473d213d7e69aaba0ed86ca7692f569db3e0395c1ec8adadca9921a8284e1939",
    BROKER: "ed3273aeac8bfc35372a83dd2bde66ec21b13f953f2e18c5774bcf20d5c5f62c",
}
LOCKS = {
    "pubspec.lock": "4c719ebf08ce4d65571d5c4b25f9ec16567405ab99c8ee298143acadfa2691b8",
    "native/transport/Cargo.lock": "0cb8ef90485ccae06b2981d023ea44d46c6309ba46a1186dffab581169f9f0c3",
    "native/bench/Cargo.lock": "ea60fd1c65bd64f04a65ff9c1410348ef2d22450c7d63e4556149f7b6f1c0189",
}

# Preallocated at explicit startup. Actual capture totals are far below Smi and
# Uint64 limits. No method receives a payload or performs I/O.
COUNTER_SOURCE = """import 'dart:typed_data';

final class MqttDartCopyCensus {
  static final Uint64List _values = Uint64List(14);
  static const _names = [
    'native_poll_copy_requests', 'native_poll_copy_bytes',
    'body_constructor_requests', 'body_constructor_requested_bytes',
    'zero_body_constructor_requests',
    'growth_constructor_requests', 'growth_constructor_requested_bytes',
    'nonempty_growth_copy_requests', 'growth_copy_bytes',
    'nonempty_body_copy_requests', 'body_copy_bytes',
    'frames_completed', 'completed_body_bytes', 'nonempty_frames_completed',
  ];
  static void initialize() => _values.fillRange(0, _values.length, 0);
  static void pollCopied(int size) { _values[0]++; _values[1] += size; }
  static void bodyConstructed(int size) {
    _values[2]++; _values[3] += size;
    if (size == 0) _values[4]++;
  }
  static void growthConstructed(int size) {
    _values[5]++; _values[6] += size;
  }
  static void growthCopied(int size) {
    if (size == 0) return;
    _values[7]++; _values[8] += size;
  }
  static void bodyCopied(int size) {
    if (size == 0) return;
    _values[9]++; _values[10] += size;
  }
  static void frameCompleted(int size) {
    _values[11]++; _values[12] += size;
    if (size > 0) _values[13]++;
  }
  static Map<String, Object> snapshot() => {
    'diagnostic_only': true,
    'kind': 'mqtt_dart_logical_copy_requests',
    'scope': 'whole broker lifetime; requests, not heap allocations/RSS/timing',
    'counts': {for (var i = 0; i < _names.length; i++) _names[i]: _values[i]},
  };
}
"""
IMPORT = ("import 'package:connectanum_core/src/mqtt/dart_copy_census.dart' "
          "as copyCensus;\n")
CLASS = "copyCensus.MqttDartCopyCensus"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError("Expected exactly one guarded instrumentation site")
    return text.replace(old, new, 1)


def instrument(sources):
    """Only the three exact source bodies and one new passive counter module."""
    if set(sources) != set(SOURCE_HASHES):
        raise ValueError("Wrong instrumentation source inventory")
    for name, wanted in SOURCE_HASHES.items():
        if sha(sources[name]) != wanted:
            raise ValueError("Frozen source mismatch: " + name)
    frame = sources[FRAME].decode()
    frame = replace_once(frame, "import 'dart:typed_data';\n",
                         "import 'dart:typed_data';\n"
                         "import 'dart_copy_census.dart' as copyCensus;\n")
    old = """            body = Uint8List(
              remainingLength < capacity ? remainingLength : capacity,
            );"""
    frame = replace_once(frame, old, old + "\n            " + CLASS +
                         ".bodyConstructed(body.length);")
    old = "        final next = Uint8List(capacity);\n"
    frame = replace_once(frame, old, old + "        " + CLASS +
                         ".growthConstructed(capacity);\n")
    old = "        next.setRange(0, bodyEnd, body);\n"
    frame = replace_once(frame, old, old + "        " + CLASS +
                         ".growthCopied(bodyEnd);\n")
    old = "      currentBody.setRange(bodyEnd, bodyEnd + count, input, offset);\n"
    frame = replace_once(frame, old, old + "      " + CLASS +
                         ".bodyCopied(count);\n")
    old = "        first = -1;\n"
    frame = replace_once(frame, old, "        " + CLASS +
                         ".frameCompleted(remainingLength);\n" + old)
    native = sources[NATIVE].decode()
    native = replace_once(native, "import 'dart:typed_data';\n",
                          "import 'dart:typed_data';\n" + IMPORT)
    old = """    if (result == 0) return null;
    return Uint8List.fromList(buffer.asTypedList(result));
  }

  @override
  void sendMqttChunk"""
    new = """    if (result == 0) return null;
    final copied = Uint8List.fromList(buffer.asTypedList(result));
    """ + CLASS + """.pollCopied(result);
    return copied;
  }

  @override
  void sendMqttChunk"""
    native = replace_once(native, old, new)
    broker = sources[BROKER].decode()
    broker = replace_once(broker, "import 'dart:io';\n",
                          "import 'dart:io';\nimport 'dart:convert';\n" + IMPORT)
    old = "  final port = int.parse(args[0]);\n"
    new = old + """  final censusOutput =
      Platform.environment['CONNECTANUM_MQTT_DART_COPY_CENSUS_OUTPUT'];
  if (censusOutput == null || censusOutput.isEmpty) {
    throw StateError('Fresh copy census output is required');
  }
  final censusFile = File(censusOutput)..createSync(exclusive: true);
  """ + CLASS + """.initialize();
"""
    broker = replace_once(broker, old, new)
    old = "  runtime.dispose();\n"
    new = old + """  censusFile.writeAsStringSync(
    jsonEncode(""" + CLASS + """.snapshot()) + '\\n', flush: true);
"""
    broker = replace_once(broker, old, new)
    return {FRAME: frame.encode(), NATIVE: native.encode(),
            BROKER: broker.encode(), COUNTER: COUNTER_SOURCE.encode()}


def validated_members(packed):
    members = packed.getmembers()
    for member in members:
        name = Path(member.name)
        if (not name.parts or name.is_absolute() or ".." in name.parts or
                not (member.isfile() or member.isdir())):
            raise ValueError("Unsafe source archive member")
    return members


def unpack(archive, destination):
    """Reject links/special entries and path escape before writing any member."""
    with tarfile.open(fileobj=io.BytesIO(archive)) as packed:
        members = validated_members(packed)
        for member in members:
            path = destination / member.name
            if member.isdir():
                path.mkdir(parents=True, exist_ok=True)
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(packed.extractfile(member).read())
                path.chmod(member.mode & 0o777)


def prepare(output, lock_root, *, original=False):
    if output.exists():
        raise ValueError("Refusing to overwrite a shadow/evidence directory")
    archive = subprocess.check_output(
        ["git", "archive", "--format=tar", SOURCE], cwd=ROOT)
    if sha(archive) != ARCHIVE_SHA256:
        raise ValueError("Frozen source archive digest changed")
    locks = {}
    for name, wanted in LOCKS.items():
        data = (lock_root / name).read_bytes()
        if sha(data) != wanted:
            raise ValueError("Frozen resolved lock mismatch: " + name)
        locks[name] = data
    output.mkdir(parents=True)
    (output / "original-source.tar").write_bytes(archive)
    shadow = output / "source"
    shadow.mkdir()
    unpack(archive, shadow)
    before = {n: (shadow / n).read_bytes() for n in SOURCE_HASHES}
    if (shadow / COUNTER).exists():
        raise ValueError("Unexpected counter in original archive")
    edits = {} if original else instrument(before)
    diff = []
    for name, data in edits.items():
        prior = before.get(name, b"")
        diff.extend(difflib.unified_diff(
            prior.decode().splitlines(True), data.decode().splitlines(True),
            fromfile="a/" + name, tofile="b/" + name))
        (shadow / name).write_bytes(data)
    for name, data in locks.items():
        path = shadow / name
        if path.exists() and path.read_bytes() != data:
            raise ValueError("Archive/receipt lock mismatch")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    (output / "instrumentation.diff").write_text("".join(diff))
    manifest = {
        "diagnostic_only": True, "original_control": original, "source": SOURCE,
        "source_archive_sha256": ARCHIVE_SHA256,
        "generator_sha256": sha(Path(__file__).read_bytes()),
        "original_targets": SOURCE_HASHES,
        "instrumented_targets": {n: sha(data) for n, data in edits.items()},
        "locks": LOCKS, "capture_ready": False,
        "scope": "Shadow instrumentation only; no frozen runtime edit or acceptance.",
    }
    (output / "shadow-manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n")
    return shadow


def verify_shadow(output):
    manifest = json.loads((output / "shadow-manifest.json").read_text())
    if (manifest["source"] != SOURCE or manifest["locks"] != LOCKS or
            manifest["source_archive_sha256"] != ARCHIVE_SHA256 or
            manifest["generator_sha256"] != sha(Path(__file__).read_bytes()) or
            manifest["capture_ready"] is not False or
            type(manifest["original_control"]) is not bool):
        raise ValueError("Shadow provenance changed")
    archive = (output / "original-source.tar").read_bytes()
    if sha(archive) != ARCHIVE_SHA256:
        raise ValueError("Retained original source archive changed")
    original = manifest["original_control"]
    source = output / "source"
    with tarfile.open(fileobj=io.BytesIO(archive)) as packed:
        members = validated_members(packed)
        targets = {n: packed.extractfile(n).read() for n in SOURCE_HASHES}
        expected = {} if original else instrument(targets)
        allowed = {m.name for m in members if m.isfile()}
        for member in members:
            if not member.isfile():
                continue
            want = expected.get(member.name, packed.extractfile(member).read())
            if (source / member.name).read_bytes() != want:
                raise ValueError("Shadow source changed: " + member.name)
    allowed.update(LOCKS)
    if expected:
        allowed.add(COUNTER)
    for path in source.rglob("*"):
        name = path.relative_to(source).as_posix()
        if path.is_symlink():
            raise ValueError("Unexpected shadow symlink")
        parts = path.relative_to(source).parts
        workspace_ref = (
            len(parts) == 5 and parts[0] == "packages" and
            parts[2:] == (".dart_tool", "pub", "workspace_ref.json") and
            ("packages/" + parts[1] + "/pubspec.yaml") in allowed
        )
        if path.is_file() and workspace_ref:
            # Standard workspace metadata emitted by dart pub get. Never let
            # this generated reference redirect resolution outside the shadow.
            data = json.loads(path.read_text())
            if (data != {"workspaceRoot": "../../../.."} or
                    (path.parent / data["workspaceRoot"]).resolve() != source.resolve()):
                raise ValueError("Workspace reference escaped shadow")
            continue
        if path.is_file() and name not in allowed and not name.startswith(".dart_tool/"):
            raise ValueError("Unexpected shadow source/input: " + name)
    if expected:
        if (output / "source" / COUNTER).read_bytes() != expected[COUNTER]:
            raise ValueError("Counter implementation changed")
    if manifest["instrumented_targets"] != {n: sha(d) for n, d in expected.items()}:
        raise ValueError("Shadow target inventory changed")
    for name, wanted in LOCKS.items():
        if sha((output / "source" / name).read_bytes()) != wanted:
            raise ValueError("Shadow lock changed")
    return manifest


def verify_workspace_packages(shadow):
    """Pub may fetch dependencies, but internal package URIs must use this shadow."""
    config = shadow / ".dart_tool/package_config.json"
    packages = json.loads(config.read_text())["packages"]
    wanted = {}
    for pubspec in [shadow / "pubspec.yaml", *sorted(shadow.glob("packages/*/pubspec.yaml"))]:
        name = re.search(r"^name:\s*(\w+)\s*$", pubspec.read_text(), re.MULTILINE)
        if not name:
            raise ValueError("Cannot identify workspace package")
        wanted[name[1]] = pubspec.parent.resolve()
    observed = set()
    for package in packages:
        name = package["name"]
        if name not in wanted:
            continue
        uri = urlparse(urljoin(config.resolve().as_uri(), package["rootUri"]))
        if (uri.scheme != "file" or uri.netloc not in ("", "localhost") or
                Path(unquote(uri.path)).resolve() != wanted[name] or
                package.get("packageUri", "lib/") != "lib/"):
            raise ValueError("Workspace package escaped shadow: " + name)
        if name in observed:
            raise ValueError("Duplicate workspace package")
        observed.add(name)
    if observed != set(wanted):
        raise ValueError("Incomplete shadow workspace package map")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--lock-root", default=ROOT, type=Path)
    parser.add_argument("--original-control", action="store_true")
    args = parser.parse_args()
    prepare(args.output, args.lock_root, original=args.original_control)
    verify_shadow(args.output)


if __name__ == "__main__":
    main()
