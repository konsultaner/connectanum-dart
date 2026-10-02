"""Collect Rust production coverage from Dart callers, separately from Cargo tests."""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess

from native_coverage import REPO, ROOTS, digest, filter_lcov, snapshot


def coverage_environment(output: str, base: dict[str, str]) -> dict[str, str]:
    values = {}
    for line in output.splitlines():
        key, separator, raw = line.partition("=")
        if not separator or not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", key) or key in values:
            raise ValueError("Invalid cargo-llvm-cov environment")
        words = shlex.split(raw)
        if len(words) != 1:
            raise ValueError("Invalid cargo-llvm-cov environment value")
        values[key] = words[0]
    if not all(values.get(key) for key in ("LLVM_PROFILE_FILE", "RUSTC_WRAPPER", "CARGO_LLVM_COV")):
        raise ValueError("Incomplete cargo-llvm-cov environment")
    return {**base, **values}


def input_hashes(repo: Path) -> dict[str, str]:
    listed = subprocess.check_output([
        "git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--",
        "packages", "tool", "bin", "pubspec.yaml", "pubspec.lock", "dart_test.yaml",
        "analysis_options.yaml", ".cargo", "native/transport/.cargo",
    ], cwd=repo).decode().split("\0")
    paths = set(listed) - {""}
    # Pub lock/override files and resolved package maps are often ignored by
    # Git, but still determine which code the Dart process executes.
    directories = [repo, *sorted((repo / "packages").glob("*")),
                   repo / "native/transport", *sorted((repo / "native/transport").glob("ct_*"))]
    for directory in directories:
        for name in ("pubspec.yaml", "pubspec.lock", "pubspec_overrides.yaml",
                     ".dart_tool/package_config.json", ".cargo/config", ".cargo/config.toml"):
            path = directory / name
            if path.exists():
                paths.add(path.relative_to(repo).as_posix())
    result = {}
    for name in sorted(paths):
        path = repo / name
        if path.is_symlink():
            raise ValueError(f"Unsupported coverage input symlink: {name}")
        if path.is_file():
            result[name] = digest(path)
    return result


def verify_inputs(repo: Path, expected: dict[str, str]) -> None:
    if input_hashes(repo) != expected:
        raise ValueError("Dart FFI coverage inputs changed during collection")


def run_step(command, cwd, env, log, timeout=900):
    with log.open("x") as output:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            status = process.wait(timeout=timeout)
        except BaseException:
            # Dart tests may spawn router/worker children. Do not leave them
            # collecting profiles after a failed or cancelled parent step.
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                pass
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
            raise
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            surviving_child = False
        else:
            surviving_child = True
            # The parent is reaped. Remaining processes must not keep writing
            # counters after the step's profile snapshot.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    if status:
        raise subprocess.CalledProcessError(status, command)
    if surviving_child:
        raise RuntimeError("Coverage command left a surviving child process")


def suites():
    # Legacy-ABI builds, executables and other platform variants need their own
    # instrumented artifacts; these groups measure the current ffi-test library.
    client = "packages/connectanum_client"
    router = "packages/connectanum_router"
    result = []
    for name in ("external_byte_buffer", "e2ee_provider", "resource_restart",
                 "native_transports", "runtime_file_segment"):
        result.append((f"client-{name}", client, [f"test/transport/native/{name}_test.dart"], {}))
    for name, path in (
        ("socket", "socket/socket_transport_test.dart"),
        ("websocket", "websocket/websocket_transport_io_test.dart"),
    ):
        result.append((f"client-{name}", client, [f"test/transport/{path}"], {}))
    for name in ("native_runtime", "message_lifetime", "metadata_projection"):
        result.append((f"router-{name}", router, [f"test/native/{name}_test.dart"], {}))
    for name in ("router_runtime", "authorization_integration", "meta_discovery_authorization",
                 "publish_ack", "router_integration_cancel", "router_integration_websocket"):
        result.append((f"router-{name}", router, [f"test/{name}_test.dart"], {}))
    result.append(("router-ffi-test-mode", router, ["test/native/ffi_test_mode_test.dart"], {}))
    result.append(("router-integration", router, ["test/router_integration_native_test.dart",
                  "test/router_worker_session_test.dart", "--exclude-tags", "zero_copy_publish"], {}))
    result.append(("router-zero-copy", router, ["test/router_integration_native_test.dart",
                  "test/router_worker_session_test.dart", "--tags", "zero_copy_publish"],
                   {"CONNECTANUM_FORWARD_NATIVE_PUBLISH": "1"}))
    result.append(("router-remote-auth", router, ["test/remote_auth_integration_test.dart"], {}))
    return result


def collect(repo: Path, output: Path, analyzer: Path):
    repo, output, analyzer = repo.resolve(), output.resolve(), analyzer.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report_path = output / "collection.json"
    report = {"schemaVersion": 1, "complete": False, "runtime": "native-dart-ffi",
              "profile": "dev", "features": ["ffi-test"], "steps": [],
              "limitations": ["Current ffi-test artifact only; not legacy ABI or other platforms.",
                              "Dart line coverage and Cargo unit-test coverage are separate."]}

    def save():
        report_path.write_text(json.dumps(report, indent=2) + "\n")

    def execute(label, command, env, cwd=repo):
        entry = {"name": label, "command": command, "cwd": str(cwd), "complete": False}
        report["steps"].append(entry)
        save()
        print(f"Native FFI coverage: {label}", flush=True)
        try:
            run_step(command, cwd, env, output / f"{label}.log")
        except BaseException as error:
            entry["errorType"] = type(error).__name__
            if isinstance(error, subprocess.CalledProcessError):
                entry["exitCode"] = error.returncode
            save()
            raise
        entry["exitCode"] = 0
        entry["complete"] = True
        save()

    save()
    report["inputHashes"] = input_hashes(repo)
    scope = snapshot(repo, ROOTS, analyzer)
    scope_path = output / "source-scopes.json"
    scope_path.write_text(json.dumps(scope, indent=2) + "\n")
    target = output / "target"
    base = dict(os.environ, CARGO_TARGET_DIR=str(target), CARGO_LLVM_COV_TARGET_DIR=str(target))
    manifest = str(repo / "native/transport/Cargo.toml")
    shown = subprocess.check_output(["cargo", "llvm-cov", "show-env", "--manifest-path", manifest],
                                    cwd=repo, env=base, text=True)
    env = coverage_environment(shown, base)
    report["instrumentation"] = coverage_environment(shown, {})
    if (Path(env["CARGO_LLVM_COV_TARGET_DIR"]).resolve() != target
            or Path(env["CARGO_TARGET_DIR"]).resolve() != target):
        raise ValueError("Coverage target escaped the fresh output directory")
    execute("build", ["cargo", "build", "--manifest-path", manifest, "--locked",
                      "-p", "ct_ffi", "--features", "ffi-test"], env)
    suffix = "dylib" if os.uname().sysname == "Darwin" else "so"
    library = target / f"debug/libct_ffi.{suffix}"
    if not library.is_file():
        raise ValueError("Instrumented FFI library was not produced")
    library_hash = digest(library)
    report["library"] = {"path": str(library), "sha256": library_hash}
    for label, package, arguments, extra in suites():
        profiles = output / "profiles" / label
        profiles.mkdir(parents=True)
        step_env = dict(env, **extra, CONNECTANUM_NATIVE_LIB=str(library),
                        CONNECTANUM_SKIP_NATIVE_BUILD="1",
                        LLVM_PROFILE_FILE=str(profiles / "%p-%m.profraw"))
        execute(label, ["dart", "test", "-p", "vm", "--concurrency=1", *arguments],
                step_env, repo / package)
        raw = sorted(profiles.glob("*.profraw"))
        if not raw or any(path.stat().st_size == 0 for path in raw):
            raise ValueError(f"No nonempty native profiles from {label}; tests alone are not coverage")
        report["steps"][-1]["profiles"] = {str(path.relative_to(output)): digest(path) for path in raw}
        for path in raw:
            shutil.copy2(path, target / f"{label}-{path.name}")
        if digest(library) != library_hash:
            raise ValueError("Instrumented FFI library changed during collection")
        verify_inputs(repo, report["inputHashes"])
        save()
    execute("export", ["cargo", "llvm-cov", "report", "--manifest-path", manifest,
                       "--locked", "--lcov", "--output-path", str(output / "lcov.info")], env)
    if digest(library) != library_hash:
        raise ValueError("Instrumented FFI library changed during export")
    if snapshot(repo, ROOTS, analyzer) != scope:
        raise ValueError("Rust coverage sources changed during collection")
    verify_inputs(repo, report["inputHashes"])
    filtered, summary = filter_lcov(repo, scope, (output / "lcov.info").read_text())
    if any(summary["components"][name]["hit"] == 0 for name in ROOTS):
        raise ValueError("Dart calls did not measure both Rust components")
    summary["scopeSha256"] = digest(scope_path)
    (output / "production.info").write_text(filtered)
    (output / "production.summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    report["complete"] = True
    save()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--analyzer", type=Path, required=True)
    args = parser.parse_args()
    collect(REPO, args.output.resolve(), args.analyzer.resolve())


if __name__ == "__main__":
    main()
