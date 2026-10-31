#!/usr/bin/env python3
"""Isolated ffi-test producer-view lifetime diagnostic; never parity acceptance."""
from contextlib import ExitStack, contextmanager
import argparse
import difflib
try:
    import fcntl
except ImportError:
    fcntl = None
import hashlib
import json
import os
from pathlib import Path
import socket
import ssl
import stat
import subprocess
import tarfile
import threading
import urllib.error
import urllib.parse
import urllib.request
import uuid

try:
    from .run_wamp_serializer_campaign import group_alive, stop_process_group
except ImportError:
    from run_wamp_serializer_campaign import group_alive, stop_process_group

ROOT = Path(__file__).resolve().parent.parent
KIND = "isolated_native_ppt_view_lifetime_diagnostic_never_acceptance"
BUFFER = "packages/connectanum_client/lib/native_buffers.dart"
TRANSPORT = "packages/connectanum_client/lib/src/transport/native/native_transports_io.dart"
SESSION = "packages/connectanum_client/lib/src/protocol/session.dart"
WORKER = "packages/connectanum_bench/tool/wamp_client_main.dart"
RUNNER = "packages/connectanum_bench/lib/src/wamp_workload_runner.dart"
FORCED = "PROTOTYPE_FORCED_PRODUCER_VIEW"
PUBLIC_FORCED = "PUBLIC_LEASE_FORCED_BYTE_VIEW"
LEGACY_PREPARATION = "tool/fixtures/native_ppt_legacy_preparation_100c.dart.txt"
LEGACY_PREPARATION_SHA256 = "93cbb02d913d868c580149ef6c461a09d5f34a035722d31a1d6e1f62fcd57d29"
COUNTERS = ("owned_allocations", "owned_handles", "external_byte_owners", "write_receipts")


MEMORY_PROBE = r'''
typedef _ViewProbeCountN = view_probe_ffi.UintPtr Function();
typedef _ViewProbeCountD = int Function();
Future<void> captureViewProbe(String path, WampScenario scenario) async {
  final library = view_probe_ffi.DynamicLibrary.open(path);
  final counters = <String, _ViewProbeCountD>{
    for (final entry in const <String, String>{
      'owned_allocations': 'ct_test_owned_buffer_live_allocations',
      'owned_handles': 'ct_test_owned_buffer_live_handles',
      'external_byte_owners': 'ct_test_external_byte_buffer_live_owners',
      'write_receipts': 'ct_test_write_receipt_live_handles',
    }.entries)
      entry.key: library.lookupFunction<_ViewProbeCountN, _ViewProbeCountD>(entry.value),
  };
  Map<String, Object?> snapshot() => {
    'pid': pid, 'rss_bytes': ProcessInfo.currentRss,
    for (final entry in counters.entries) entry.key: entry.value(),
  };
  final before = snapshot();
  final service = (await view_probe_dev.Service.getInfo()).serverUri;
  if (service == null) throw StateError('View probe requires a VM service');
  final isolate = view_probe_dev.Service.getIsolateId(view_probe_isolate.Isolate.current)!;
  final http = HttpClient();
  final after = <Object?>[];
  try {
    for (var round = 0; round < 3; round++) {
      final uri = service.resolve('getAllocationProfile').replace(queryParameters: {
        'isolateId': isolate, 'gc': 'true',
      });
      final response = await (await http.getUrl(uri)).close();
      final result = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      if (result.containsKey('error')) throw StateError('$result');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      after.add({'counts': snapshot(), 'memory_usage': result['result']?['memoryUsage']});
    }
  } finally {
    http.close(force: true);
  }
  final record = jsonEncode({
    'kind': 'forced_gc_ffi_test_diagnostic_never_acceptance',
    'codec': scenario.serializer.name,
    'construction': scenario.payloadConstruction.wireName,
    'iterations': scenario.iterations, 'body_bytes': scenario.payloadBytes,
    'before_gc': before, 'after_gc': after,
  });
  File(Platform.environment['CONNECTANUM_VIEW_PROBE_OUTPUT']!).writeAsStringSync(
    record + String.fromCharCode(10), mode: FileMode.append,
  );
}
'''


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError("diagnostic source pattern changed; refusing a partial patch")
    return source.replace(old, new, 1)


def mark_buffer_source(buffer, marker):
    # Insert at the first declaration, after every library directive. Native
    # buffers may gain additional parts; a declaration between parts is invalid.
    anchor = "/// Native integration output from `ct_external_buffer_register`."
    return replace_once(
        buffer, anchor,
        f"const nativePptViewProbeMarker = '{marker}';\n\n" + anchor,
    )


def patch_sources(buffer, transport, marker):
    buffer = mark_buffer_source(buffer, marker)
    buffer = replace_once(buffer, """    _handle.check();
    final bytes = this.bytes;
    NativeOwnedBuffer._pptViews[bytes] = _pptViewIdentity;""", """    _handle.check();
    if (encoding == LazyPayloadEncoding.flatbuffers) {
      return LazyMessagePayload.deferred(
        encoding: encoding,
        loader: () => throw StateError('PROTOTYPE_FORCED_PRODUCER_VIEW'),
        anchor: (prototypeNativeBuffer: this),
      );
    }
    final bytes = this.bytes;
    NativeOwnedBuffer._pptViews[bytes] = _pptViewIdentity;""")
    fast = replace_once(transport, "    while (seen.add(current)) {", """    while (seen.add(current)) {
      if (flatBuffersOnly &&
          current.encoding == LazyPayloadEncoding.flatbuffers &&
          owner is ({NativeOwnedBuffer prototypeNativeBuffer}) &&
          !owner.prototypeNativeBuffer.isDisposed) {
        return (buffer: owner.prototypeNativeBuffer, bytes: Uint8List(0));
      }""")
    return buffer, fast


def instrument_worker(original):
    original = replace_once(original, "import 'dart:io';", """import 'dart:io';
import 'dart:developer' as view_probe_dev;
import 'dart:ffi' as view_probe_ffi;
import 'dart:isolate' as view_probe_isolate;
import 'package:connectanum_client/native_buffers.dart' as view_probe_source;""")
    original = replace_once(original, "Future<void> main(List<String> args) async {", """Future<void> main(List<String> args) async {
  stderr.writeln('PROTOTYPE_SOURCE_MARKER=' + view_probe_source.nativePptViewProbeMarker);""")
    # Carry the library path into the private per-request frame without adding
    # instrumentation parameters to the production worker.
    original = replace_once(original,
                            "      await _handleRequest(trimmed, runner, nativeRuntime);",
                            "      await _handleRequest(trimmed, runner, nativeRuntime, nativeLibraryPath);")
    original = replace_once(original,
                            "  NativeClientRuntime nativeRuntime,\n) async {",
                            "  NativeClientRuntime nativeRuntime,\n  String nativeLibraryPath,\n) async {")
    original = replace_once(original,
                            "  final fileMetrics = nativeRuntime.fileSegmentMetricsSnapshot()",
                            "  await captureViewProbe(nativeLibraryPath, scenario);\n"
                            "  final fileMetrics = nativeRuntime.fileSegmentMetricsSnapshot()")
    return original + MEMORY_PROBE


def patch_session(original):
    return replace_once(original, """    Uint8List? packedPayload;
    if (options?.pptScheme != null && options?.pptScheme != 'wamp') {""", """    if (options?.pptScheme != null &&
        options?.pptScheme != 'wamp' &&
        options?.pptSerializer == 'flatbuffers' &&
        payload.encoding == LazyPayloadEncoding.flatbuffers &&
        payload.storageOwner is ({Object prototypeNativeBuffer})) {
      message.restoreLazyPayload(payload);
      return;
    }
    Uint8List? packedPayload;
    if (options?.pptScheme != null && options?.pptScheme != 'wamp') {""")


def preparation_span(runner):
    start_marker = "  _PreparedBenchPayload _prepareTypedBenchPayload("
    end_marker = "  Object _buildTypedBenchmarkValue("
    if runner.count(start_marker) != 1 or runner.count(end_marker) != 1:
        raise ValueError("diagnostic benchmark preparation boundary changed")
    start, end = runner.index(start_marker), runner.index(end_marker)
    if end <= start:
        raise ValueError("diagnostic benchmark preparation order changed")
    return start, end


def require_public_preparation(runner):
    start, end = preparation_span(runner)
    preparation = runner[start:end]
    for pattern in ("owner.leaseFlatBuffersPptPayload()", "owner.leasePptPayload(",
                    "final leasedOwner = lease.nativeOwnerFor(payload);",
                    "producer.dispose();", "owner = leasedOwner;", "lease: lease,"):
        if preparation.count(pattern) != 1:
            raise ValueError("diagnostic requires the public benchmark lease path")


def legacy_runner_source(runner):
    # Preserve the historical producer-view controls after the real benchmark
    # adopts leases. This fixture is the unchanged 100c7624 method, not a new
    # benchmark case or an alternative acceptance workload.
    require_public_preparation(runner)
    fixture = ROOT / LEGACY_PREPARATION
    if digest(fixture) != LEGACY_PREPARATION_SHA256:
        raise ValueError("frozen legacy preparation fixture changed")
    start, end = preparation_span(runner)
    return runner[:start] + fixture.read_text() + runner[end:]


def patch_public_lease(buffer, runner, marker):
    # The production benchmark now owns/disposes real leases itself. Guard the
    # source getter only; don't replace legacy helpers or rewrite its ownership.
    require_public_preparation(runner)
    buffer = mark_buffer_source(buffer, marker)
    buffer = replace_once(buffer, "  Uint8List get bytes => _bytes ??= _owner.bytes;",
                          "  Uint8List get bytes => throw StateError('PUBLIC_LEASE_FORCED_BYTE_VIEW');")
    return buffer, runner

@contextmanager
def resource_lease(path):
    if fcntl is None:
        raise ValueError("diagnostic process groups and leases require POSIX")
    path.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
    parent = path.parent.lstat()
    if not stat.S_ISDIR(parent.st_mode) or parent.st_uid != os.getuid() or parent.st_mode & 0o077:
        raise ValueError("resource directory must be private, user-owned and not a symlink")
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
    try:
        info, named = os.fstat(fd), path.lstat()
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077
                or (info.st_dev, info.st_ino) != (named.st_dev, named.st_ino)):
            raise ValueError("resource lock identity or permissions are invalid")
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield
    finally:
        os.close(fd)


def verify_package_roots(shadow):
    configuration = shadow / ".dart_tool/package_config.json"
    packages = json.loads(configuration.read_text())["packages"]
    for name in ("connectanum_core", "connectanum_client", "connectanum_bench"):
        entry = next(item for item in packages if item["name"] == name)
        uri = urllib.parse.urlparse(urllib.parse.urljoin(configuration.as_uri(), entry["rootUri"]))
        if uri.scheme != "file" or uri.netloc not in ("", "localhost"):
            raise ValueError(f"{name} does not resolve to a local source package")
        resolved = Path(urllib.parse.unquote(uri.path)).resolve()
        if resolved != (shadow / "packages" / name).resolve():
            raise ValueError(f"{name} resolves outside the private source workspace")


def snapshot(root):
    names = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
    files = {name: digest(root / name) for name in names
             if name and (root / name).is_file() and not (root / name).is_symlink()}
    files["pubspec.lock"] = digest(root / "pubspec.lock")
    return files


def validate_observations(rows, reports, *, immediate_cleanup=True):
    if len(reports) != 6 or len(rows) != 12:
        raise ValueError("incomplete six-case inventory or warmup/workload snapshots")
    expected = {(construction, size) for construction in ("native_buffer", "pre_encoded_span")
                for size in (0, 65536, 1048576)}
    if {(r["scenario"]["payload_construction"], r["scenario"]["payload_bytes"])
            for r in reports} != expected:
        raise ValueError("duplicate or missing construction/body case")
    pids = set()
    for index, report in enumerate(reports):
        scenario = report["scenario"]
        if len(report["report"]["samples"]) < 1000:
            raise ValueError("wire validation did not complete 1,000 operations")
        for phase, observed in enumerate(rows[2 * index:2 * index + 2]):
            if (observed["kind"] != "forced_gc_ffi_test_diagnostic_never_acceptance"
                    or observed["codec"] != "flatbuffers"
                    or observed["construction"] != scenario["payload_construction"]
                    or observed["iterations"] != (1 if phase == 0 else 1000)
                    or observed["body_bytes"] != (min(1024, scenario["payload_bytes"])
                                                   if phase == 0 else scenario["payload_bytes"])):
                raise ValueError("snapshot attribution disagrees with the actual workload")
            before = observed["before_gc"]
            if type(before["pid"]) is not int or before["pid"] <= 0:
                raise ValueError("invalid observed process identity")
            pids.add(before["pid"])
            if len(observed["after_gc"]) != 3:
                raise ValueError("missing forced-GC round")
            for round_index, counts in enumerate([before, *(item["counts"] for item in observed["after_gc"])]):
                if counts["pid"] != before["pid"]:
                    raise ValueError("GC observation changed process identity")
                if any(type(counts[key]) is not int or counts[key] < 0
                       or ((immediate_cleanup or round_index > 0) and counts[key] != 0)
                       for key in COUNTERS):
                    raise ValueError("an unexported producer allocation or handle remains live")
    if len(pids) != 1:
        raise ValueError("client worker restarted during the diagnostic")
    return pids.pop()


def validate_control(reports, failures):
    if (reports or len(failures) != 1 or type(failures[0]["status"]) is not int
            or not 400 <= failures[0]["status"] <= 599 or FORCED not in failures[0]["body"]):
        raise ValueError("negative control did not exercise the throwing producer-view loader")


def run_phase(root, shadow, out, library, dart, marker, control, *, baseline=False):
    out.mkdir()
    worker = shadow / "out" / out.name / "worker.dart"
    worker.parent.mkdir(parents=True)
    worker.write_text(instrument_worker((shadow / WORKER).read_text()))
    config = json.loads((shadow / "native/bench/bench_router.json").read_text())
    ports = []
    # Keep every reservation live until the whole listener set is selected:
    # the OS can immediately reuse a released ephemeral port for the next bind.
    with ExitStack() as reservations:
        for listener in config["router"]["listeners"]:
            sock = reservations.enter_context(socket.socket())
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
            if port in ports:
                raise ValueError("ephemeral listener port collision")
            ports.append(port)
            listener["endpoint"] = f"127.0.0.1:{port}"
            if "http3" in listener["protocols"]:
                listener["protocols"].remove("http3")
                listener["http"].pop("http3", None)
    configuration = out / "router.json"
    configuration.write_text(json.dumps(config, indent=2) + "\n")
    command = [dart, "--enable-vm-service=0", "run", "packages/connectanum_bench/tool/bench_main.dart",
               "--router-config", str(configuration), "--native-lib", str(library),
               "--wamp-worker", str(worker)]
    files = [shadow / BUFFER, shadow / TRANSPORT, shadow / SESSION, shadow / RUNNER, shadow / "pubspec.lock",
             shadow / ".dart_tool/package_config.json", worker, library, configuration]
    inputs = {str(path): digest(path) for path in files}
    (out / "inputs.json").write_text(json.dumps({"kind": KIND, "command": command,
                                                "inputs": inputs}, indent=2) + "\n")
    env = {**os.environ, "CONNECTANUM_SKIP_NATIVE_BUILD": "1",
           "CONNECTANUM_BENCH_WAMP_REUSE_WORKER": "1", "CONNECTANUM_BENCH_WAMP_VM_METRICS": "1",
           "CONNECTANUM_NATIVE_LIB": str(library),
           "CONNECTANUM_VIEW_PROBE_OUTPUT": str(out / "memory-observations.jsonl")}
    process = subprocess.Popen(command, cwd=shadow, env=env, text=True, stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
    ready = threading.Event()
    reader_errors = []
    def read():
        try:
            with (out / "server.log").open("w") as log:
                for line in process.stdout:
                    log.write(line)
                    log.flush()
                    if line.strip().endswith("READY"):
                        ready.set()
        except Exception as error:
            reader_errors.append(f"{type(error).__name__}: {error}")
    reader = threading.Thread(target=read, daemon=True)
    reports, failures = [], []
    stopped = False
    try:
        reader.start()
        if not ready.wait(60):
            raise RuntimeError("diagnostic server did not become ready")
        cases = [("native_buffer", 65536)] if control else [
            (construction, size) for construction in ("native_buffer", "pre_encoded_span")
            for size in (0, 65536, 1048576)]
        context = ssl.create_default_context(cafile=str(shadow / "native/bench/bench_tls.crt"))
        for construction, size in cases:
            scenario = dict(transport="rawsocket", serializer="flatbuffers", peer_serializer="flatbuffers",
                            client_impl="native", secure_transport=False, mode="rpc", uri="bench.rpc.echo",
                            iterations=1000, minimum_duration_ms=1000, concurrency=1, payload_bytes=size,
                            payload_construction=construction, ppt_scheme="x_connectanum_bench_typed",
                            ppt_serializer="flatbuffers")
            request = urllib.request.Request(f"https://localhost:{ports[0]}/bench/wamp",
                                             data=json.dumps(scenario).encode(),
                                             headers={"content-type": "application/json"})
            try:
                with urllib.request.urlopen(request, context=context, timeout=180) as response:
                    report = json.load(response)
            except urllib.error.HTTPError as error:
                failure = {"status": error.code, "body": error.read().decode(errors="replace")}
                failures.append(failure)
                (out / "failures.json").write_text(json.dumps(failures, indent=2) + "\n")
                if control and FORCED in failure["body"]:
                    break
                raise
            reports.append({"scenario": scenario, "report": report})
            with (out / "reports.jsonl").open("a") as stream:
                stream.write(json.dumps(reports[-1]) + "\n")
            print(json.dumps({"phase": out.name, "rows": len(reports), "body_bytes": size}), flush=True)
    finally:
        try:
            process.stdin.write("stop\n")
            process.stdin.flush()
            process.wait(timeout=30)
        except (OSError, subprocess.TimeoutExpired):
            stop_process_group(process)
        finally:
            if group_alive(process.pid):
                stop_process_group(process)
            stopped = not group_alive(process.pid)
            if reader.ident is not None:
                reader.join(timeout=5)
            unchanged = all(digest(Path(path)) == value for path, value in inputs.items())
            result = {"kind": KIND, "rows": len(reports), "failures": len(failures),
                      "process_exit": process.returncode, "process_group_stopped": stopped,
                      "reader_stopped": not reader.is_alive(), "reader_errors": reader_errors,
                      "inputs_unchanged": unchanged}
            (out / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    if process.returncode != 0 or not stopped or reader.is_alive() or reader_errors or not unchanged:
        raise RuntimeError("owned-process cleanup or source/library invariance failed")
    if "PROTOTYPE_SOURCE_MARKER=" + marker not in (out / "server.log").read_text():
        raise ValueError("the worker did not attest the private source marker")
    if control:
        validate_control(reports, failures)
        result["negative_control_observed"] = True
    else:
        observations = [json.loads(line) for line in (out / "memory-observations.jsonl").read_text().splitlines()]
        result["client_pid"] = validate_observations(observations, reports, immediate_cleanup=not baseline)
        result["before_gc_owned_allocations"] = [row["before_gc"]["owned_allocations"]
                                                   for row in observations]
        if baseline and not any(result["before_gc_owned_allocations"]):
            raise ValueError("baseline did not reproduce producer allocations awaiting GC")
    (out / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def run(args, root=ROOT):
    root, output, library = root.resolve(), args.output.resolve(), args.native_lib.resolve()
    if output.exists() or output == root or output in root.parents or not library.is_file():
        raise ValueError("requires a new output directory and an existing ffi-test library")
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=root, text=True).strip():
        raise ValueError("diagnostic requires a clean source checkout")
    if not (root / "pubspec.lock").is_file():
        raise ValueError("run bin/bootstrap before this diagnostic")
    with resource_lease(args.resource_lock):
        output.mkdir(parents=True)
        before = snapshot(root)
        library_hash = digest(library)
        head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
        shadow = output / "source"
        shadow.mkdir()
        archive = output / "source.tar"
        with archive.open("wb") as stream:
            subprocess.run(["git", "archive", "--format=tar", "HEAD"], cwd=root, stdout=stream, check=True)
        with tarfile.open(archive) as stream:
            stream.extractall(shadow, filter="data")
        (shadow / "pubspec.lock").write_bytes((root / "pubspec.lock").read_bytes())
        marker = "native-view-" + uuid.uuid4().hex
        original_buffer, original_transport = (shadow / BUFFER).read_text(), (shadow / TRANSPORT).read_text()
        original_session = (shadow / SESSION).read_text()
        original_runner = (shadow / RUNNER).read_text()
        direct_session = patch_session(original_session)
        legacy_runner = legacy_runner_source(original_runner)
        public_buffer, public_runner = patch_public_lease(original_buffer, original_runner, marker)
        buffer, fast = patch_sources(original_buffer, original_transport, marker)
        (shadow / BUFFER).write_text(buffer)
        patch = "".join(difflib.unified_diff(original_buffer.splitlines(True), buffer.splitlines(True),
                                            fromfile="a/" + BUFFER, tofile="b/" + BUFFER))
        patch += "".join(difflib.unified_diff(original_transport.splitlines(True), fast.splitlines(True),
                                             fromfile="a/" + TRANSPORT, tofile="b/" + TRANSPORT))
        patch += "".join(difflib.unified_diff(original_session.splitlines(True), direct_session.splitlines(True),
                                             fromfile="a/" + SESSION, tofile="b/" + SESSION))
        legacy_patch = "".join(difflib.unified_diff(original_runner.splitlines(True), legacy_runner.splitlines(True),
                                                   fromfile="a/" + RUNNER, tofile="b/" + RUNNER))
        (output / "legacy-preparation.patch").write_text(legacy_patch)
        (output / "private-source.patch").write_text(patch + legacy_patch)
        public_patch = "".join(difflib.unified_diff(original_buffer.splitlines(True), public_buffer.splitlines(True),
                                                   fromfile="a/" + BUFFER, tofile="b/" + BUFFER))
        public_patch += "".join(difflib.unified_diff(original_runner.splitlines(True), public_runner.splitlines(True),
                                                    fromfile="a/" + RUNNER, tofile="b/" + RUNNER))
        (output / "public-lease-probe.patch").write_text(public_patch)
        inputs = {"kind": KIND, "head": head, "source_inputs": before,
                  "library_sha256": library_hash, "archive_sha256": digest(archive),
                  "legacy_preparation": {"path": LEGACY_PREPARATION,
                                         "sha256": LEGACY_PREPARATION_SHA256,
                                         "source_head": "100c762449f9eab94c60bc3702eabc10b5c5d9ab"},
                  "dart_version": subprocess.check_output([args.dart, "--version"], text=True).strip(),
                  "limitations": ["ffi-test counters and forced GC, never performance acceptance",
                                  "private live-producer prototype and separate public-API diagnostic",
                                  "controlled input only; no adversarial provenance guarantee",
                                  "original 48 primary cases are unchanged"]}
        (output / "inputs.json").write_text(json.dumps(inputs, indent=2) + "\n")
        with (output / "pub-get.log").open("w") as log:
            subprocess.run([args.dart, "pub", "get", "--enforce-lockfile"], cwd=shadow,
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        verify_package_roots(shadow)
        results = []
        for name, control, baseline, public in (("negative-control", True, False, False),
                                                ("existing-api-baseline", False, True, False),
                                                ("direct-native", False, False, False),
                                                ("public-native-lease", False, False, True)):
            (shadow / BUFFER).write_text(public_buffer if public else (
                mark_buffer_source(original_buffer, marker) if baseline else buffer))
            (shadow / TRANSPORT).write_text(original_transport if control or baseline or public else fast)
            (shadow / SESSION).write_text(original_session if control or baseline or public else direct_session)
            (shadow / RUNNER).write_text(public_runner if public else legacy_runner)
            results.append(run_phase(root, shadow, output / name, library, args.dart, marker, control,
                                     baseline=baseline))
        if snapshot(root) != before or digest(library) != library_hash:
            raise ValueError("original source, dependency lock or native library changed")
        result = {"kind": KIND, "head": head, "status": "diagnostic_complete_not_acceptance",
                  "root_source_unchanged": True, "native_library_unchanged": True, "phases": results}
        (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result), flush=True)
        return 0


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--native-lib", required=True, type=Path)
    parser.add_argument("--resource-lock", required=True, type=Path,
                        help="Use the shared machine lease locally, or a private runner lock in hosted CI")
    parser.add_argument("--dart", default="dart")
    return parser.parse_args(argv)


if __name__ == "__main__":
    raise SystemExit(run(parse_args()))
