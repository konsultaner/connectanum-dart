from pathlib import Path
import os
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from native_ffi_coverage import collect, coverage_environment, input_hashes, run_step, verify_inputs


class NativeFfiCoverageTests(unittest.TestCase):
    def test_environment_is_parsed_without_shell_evaluation(self):
        env = coverage_environment(
            "LLVM_PROFILE_FILE='/tmp/a b/%p-%m.profraw'\n"
            "RUSTC_WRAPPER='/tmp/$(touch must-not-exist)'\n"
            "CARGO_LLVM_COV=1\n", {"KEEP": "value"})
        self.assertEqual(env["LLVM_PROFILE_FILE"], "/tmp/a b/%p-%m.profraw")
        self.assertEqual(env["RUSTC_WRAPPER"], "/tmp/$(touch must-not-exist)")
        self.assertEqual(env["KEEP"], "value")

    def test_malformed_or_incomplete_environment_fails_closed(self):
        for value in ("", "export BAD=x", "A=x y", "=value", "A='unterminated",
                      "LLVM_PROFILE_FILE=a\nLLVM_PROFILE_FILE=b\n"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                coverage_environment(value, {})

    def test_input_changes_additions_and_removal_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            source = repo / "packages/client/test/example.dart"
            source.parent.mkdir(parents=True)
            source.write_text("first")
            before = input_hashes(repo)
            self.assertIn("packages/client/test/example.dart", before)
            verify_inputs(repo, before)
            source.write_text("second")
            with self.assertRaisesRegex(ValueError, "inputs changed"):
                verify_inputs(repo, before)
            source.write_text("first")
            added = source.with_name("added.dart")
            added.write_text("new")
            with self.assertRaisesRegex(ValueError, "inputs changed"):
                verify_inputs(repo, before)
            added.unlink()
            source.unlink()
            with self.assertRaisesRegex(ValueError, "inputs changed"):
                verify_inputs(repo, before)

    def test_command_failure_and_timeout_are_not_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.assertRaises(subprocess.CalledProcessError) as failure:
                run_step([sys.executable, "-c", "print('failure evidence'); exit(19)"],
                         root, os.environ, root / "failure.log")
            self.assertEqual(failure.exception.returncode, 19)
            self.assertIn("failure evidence", (root / "failure.log").read_text())
            with self.assertRaises(subprocess.TimeoutExpired):
                run_step([sys.executable, "-c", "import time; time.sleep(60)"],
                         root, os.environ, root / "timeout.log", timeout=0.1)

    def test_successful_parent_cannot_leave_profiling_children_running(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            command = [sys.executable, "-c",
                       "import subprocess, sys; subprocess.Popen([sys.executable, '-c', "
                       "'import time; time.sleep(2)'])"]
            with self.assertRaisesRegex(RuntimeError, "surviving child"):
                run_step(command, root, os.environ, root / "orphan.log")

    def test_failed_collection_preserves_incomplete_evidence(self):
        for outcome in ("build-failure", "test-failure", "no-profiles", "empty-profile", "changed-library"):
            with self.subTest(outcome=outcome), tempfile.TemporaryDirectory() as tmp:
                repo = Path(tmp)
                output = repo / "output"
                target = output / "target"
                suffix = "dylib" if os.uname().sysname == "Darwin" else "so"
                library = target / f"debug/libct_ffi.{suffix}"

                def execute(command, cwd, env, log):
                    log.write_text("fixture failure-path evidence")
                    if command[0] == "cargo":
                        if outcome == "build-failure":
                            raise subprocess.CalledProcessError(17, command)
                        library.parent.mkdir(parents=True)
                        library.write_bytes(b"fixture; never exported as coverage")
                    elif outcome == "test-failure":
                        raise subprocess.CalledProcessError(19, command)
                    elif outcome == "empty-profile":
                        Path(env["LLVM_PROFILE_FILE"].replace("%p-%m", "1-2")).touch()
                    elif outcome == "changed-library":
                        Path(env["LLVM_PROFILE_FILE"].replace("%p-%m", "1-2")).write_bytes(b"profile")
                        library.write_bytes(b"changed library")

                shown = (f"CARGO_LLVM_COV_TARGET_DIR='{target}'\n"
                         "LLVM_PROFILE_FILE=ignored\nRUSTC_WRAPPER=wrapper\nCARGO_LLVM_COV=1\n")
                with patch("native_ffi_coverage.input_hashes", return_value={}), \
                        patch("native_ffi_coverage.snapshot", return_value={}), \
                        patch("native_ffi_coverage.subprocess.check_output", return_value=shown), \
                        patch("native_ffi_coverage.run_step", side_effect=execute), \
                        patch("native_ffi_coverage.suites", return_value=[("probe", "", [], {})]):
                    with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                        collect(repo, output, repo / "analyzer")
                result = json.loads((output / "collection.json").read_text())
                self.assertFalse(result["complete"])
                self.assertFalse((output / "production.summary.json").exists())
                self.assertTrue((output / "build.log").exists())
                if outcome.endswith("failure"):
                    self.assertFalse(result["steps"][-1]["complete"])
                    self.assertEqual(result["steps"][-1]["exitCode"],
                                     17 if outcome == "build-failure" else 19)

    def test_existing_output_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)
            evidence = output / "collection.json"
            evidence.write_text("previous evidence")
            with self.assertRaises(FileExistsError):
                collect(output, output, output / "analyzer")
            self.assertEqual(evidence.read_text(), "previous evidence")

    def test_ignored_dependency_and_build_configuration_is_still_pinned(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            (repo / ".gitignore").write_text("*\n")
            for name in ("pubspec.lock", "pubspec_overrides.yaml", ".dart_tool/package_config.json",
                         "packages/client/pubspec.lock", "packages/client/pubspec_overrides.yaml",
                         "native/transport/.cargo/config.toml"):
                path = repo / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("initial")
                before = input_hashes(repo)
                self.assertIn(name, before)
                path.write_text("changed")
                with self.assertRaisesRegex(ValueError, "inputs changed"):
                    verify_inputs(repo, before)

    @unittest.skipUnless(os.environ.get("CONNECTANUM_TEST_LLVM_COVERAGE") == "1",
                         "requires cargo-llvm-cov, llvm-tools-preview and Dart")
    def test_real_dart_calls_emit_native_counters_and_keep_uncalled_branch(self):
        self.assertIsNotNone(shutil.which("dart"), "Dart is required, not a skipped runtime")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            (root / "src").mkdir()
            (root / "Cargo.toml").write_text(
                '[package]\nname="ffi-coverage-fixture"\nversion="0.0.0"\n'
                'edition="2021"\n[lib]\ncrate-type=["cdylib"]\n')
            source = root / "src/lib.rs"
            source.write_text('''#[no_mangle]
pub extern "C" fn answer(value: u32) -> u32 {
    if value == 7 {
        42
    } else {
        99
    }
}
''')
            base = dict(os.environ, CARGO_TARGET_DIR=str(root / "target"),
                        CARGO_LLVM_COV_TARGET_DIR=str(root / "target"))
            shown = subprocess.check_output(["cargo", "llvm-cov", "show-env"],
                                            cwd=root, env=base, text=True)
            env = coverage_environment(shown, base)
            run_step(["cargo", "build", "--quiet"], root, env, root / "build.log", timeout=120)
            suffix = "dylib" if os.uname().sysname == "Darwin" else "so"
            library = root / f"target/debug/libffi_coverage_fixture.{suffix}"
            probe = root / "probe.dart"
            probe.write_text('''import 'dart:ffi';
void main(List<String> args) {
  final library = DynamicLibrary.open(args.single);
  final answer = library.lookupFunction<Uint32 Function(Uint32), int Function(int)>('answer');
  if (answer(7) != 42) throw StateError('incorrect FFI result');
}
''')
            profiles = root / "profiles"
            profiles.mkdir()
            env["LLVM_PROFILE_FILE"] = str(profiles / "%p-%m.profraw")
            run_step(["dart", str(probe), str(library)], root, env, root / "dart.log", timeout=60)
            raw_profiles = list(profiles.glob("*.profraw"))
            self.assertTrue(raw_profiles, "successful Dart execution alone is not coverage")
            self.assertTrue(all(path.stat().st_size > 0 for path in raw_profiles))
            # cargo-llvm-cov discovers profiles in its target directory.
            for path in raw_profiles:
                shutil.copy2(path, root / "target" / path.name)
            lcov = subprocess.check_output(["cargo", "llvm-cov", "report", "--lcov"],
                                           cwd=root, env=env, text=True, timeout=60)
            record = next(part for part in lcov.split("end_of_record")
                          if f"SF:{source}" in part)
            lines = {int(line[3:].split(",")[0]): int(line.split(",")[1])
                     for line in record.splitlines() if line.startswith("DA:")}
            self.assertGreater(lines[4], 0, "Dart must hit the true branch in Rust")
            self.assertEqual(lines[6], 0, "uncalled Rust branch must remain uncovered")


if __name__ == "__main__":
    unittest.main()
