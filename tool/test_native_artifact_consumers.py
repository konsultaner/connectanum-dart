#!/usr/bin/env python3
"""Failure controls for packaged production-library consumer evidence."""

from __future__ import annotations

import io
import ctypes
import json
from pathlib import Path
import sys
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

import check_native_artifact_consumers as consumers


def profile_log(*, skipped=False, unfinished=False, done=True, error=False):
    events = [
        {"type": "testStart", "test": {"id": 1}},
        {"type": "testDone", "testID": 1, "hidden": True,
         "skipped": False, "result": "success"},
        {"type": "testStart", "test": {"id": 2}},
        {"type": "testDone", "testID": 2, "hidden": False,
         "skipped": skipped, "result": "success"},
    ]
    if unfinished:
        events.append({"type": "testStart", "test": {"id": 3}})
    if error:
        events.append({"type": "error", "testID": 2, "error": "late failure"})
    if done:
        events.append({"type": "done", "success": True})
    return "Running build hooks..." + "\n".join(json.dumps(event) for event in events)


class ProfileEvidenceTest(unittest.TestCase):
    def test_hidden_loader_is_not_a_public_case(self):
        self.assertEqual(consumers.profile_results(profile_log(), 1)["passed_cases"], 1)

    def test_zero_exit_and_success_summary_do_not_allow_skipped_cases(self):
        with self.assertRaises(ValueError):
            consumers.profile_results(profile_log(skipped=True), 1)

    def test_unfinished_started_case_fails_even_with_expected_completed_count(self):
        with self.assertRaises(ValueError):
            consumers.profile_results(profile_log(unfinished=True), 1)

    def test_truncated_output_and_omitted_expected_case_fail(self):
        for log, expected in ((profile_log(done=False), 1), (profile_log(), 2)):
            with self.subTest(expected=expected), self.assertRaises(ValueError):
                consumers.profile_results(log, expected)

    def test_error_is_not_overridden_by_success_summary(self):
        with self.assertRaises(ValueError):
            consumers.profile_results(profile_log(error=True), 1)


class RustlsAbiEvidenceTest(unittest.TestCase):
    def check(self, behavior="valid"):
        class SnapshotCall:
            def __call__(self, pointer):
                if pointer is None:
                    return 0 if behavior == "wrong-null" else -4
                if behavior == "failed-write":
                    return -4
                if behavior != "no-write":
                    ctypes.memset(pointer, 0, 56 if behavior == "overwrite-tail" else 48)
                if behavior == "overwrite-head":
                    ctypes.memset(ctypes.cast(pointer, ctypes.c_void_p).value - 8, 0, 8)
                return 0

        library = SimpleNamespace(ct_rustls_copy_metrics_snapshot=SnapshotCall())
        with mock.patch.object(consumers.ctypes, "CDLL", return_value=library):
            return consumers.audit_rustls_snapshot_abi(Path("packaged-library"))

    def test_snapshot_checks_layout_null_and_surrounding_guards(self):
        result = self.check()
        self.assertEqual(result["bytes"], 48)
        self.assertEqual(result["alignment"], 8)
        self.assertEqual(result["null_result"], -4)
        self.assertTrue(result["head_tail_unchanged"])
        self.assertEqual(len(result["initial_counters"]), 6)
        self.assertEqual(set(result["initial_counters"].values()), {0})

    def test_missing_snapshot_export_is_rejected(self):
        old_library = SimpleNamespace(ct_transport_copy_metrics_snapshot=object(),
                                      ct_transport_copy_metrics_snapshot_v2=object())
        with mock.patch.object(consumers.ctypes, "CDLL", return_value=old_library):
            with self.assertRaises(AttributeError):
                consumers.audit_production_library(Path("old-library"))

    def test_null_success_is_rejected(self):
        with self.assertRaises(ValueError):
            self.check("wrong-null")

    def test_failed_or_omitted_snapshot_write_is_rejected(self):
        for behavior in ("failed-write", "no-write"):
            with self.subTest(behavior=behavior), self.assertRaises(ValueError):
                self.check(behavior)

    def test_surrounding_guard_overwrite_is_rejected(self):
        for behavior in ("overwrite-head", "overwrite-tail"):
            with self.subTest(behavior=behavior), self.assertRaises(ValueError):
                self.check(behavior)


class BundleEvidenceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="native bundle with spaces ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.stem = "ct-ffi-test-host"
        self.library = {"linux": "libct_ffi.so", "darwin": "libct_ffi.dylib",
                        "win32": "ct_ffi.dll"}[sys.platform]
        self.archive = self.root / f"{self.stem}.tar.gz"
        self.checksum = self.root / f"{self.stem}.tar.gz.sha256"
        self.manifest_path = self.root / "manifest.json"
        self.commit = "1" * 40
        self.manifest = {"schema_version": 1, "artifact": self.stem,
                         "library_file": self.library, "git_commit": self.commit}
        self.manifest_path.write_text(json.dumps(self.manifest), encoding="utf-8")
        self.output = self.root / "output"
        self.output.mkdir()

    def bundle(self, *, embedded_commit=None, symlink=False):
        embedded = {**self.manifest, "git_commit": embedded_commit or self.commit}
        with tarfile.open(self.archive, "w:gz") as bundle:
            for name, contents in (("manifest.json", json.dumps(embedded).encode()),
                                   (self.library, b"fixture library bytes")):
                member = tarfile.TarInfo(f"{self.stem}/{name}")
                member.size = len(contents)
                if symlink and name == self.library:
                    member.type = tarfile.SYMTYPE
                    member.linkname = "../../../unexpected-library"
                    member.size = 0
                bundle.addfile(member, io.BytesIO(contents) if member.isfile() else None)
        self.checksum.write_text(f"{consumers.sha256(self.archive)}  {self.archive.name}\n")

    def unpack(self, commit=None):
        return consumers.unpack_library(self.archive, self.checksum, self.manifest_path,
                                        commit or self.commit, self.output)

    def test_space_containing_paths_preserve_exact_library_bytes(self):
        self.bundle()
        manifest, library = self.unpack()
        self.assertEqual(manifest, self.manifest)
        self.assertEqual(library.read_bytes(), b"fixture library bytes")
        self.assertTrue(library.is_absolute())

    def test_changed_archive_is_rejected_before_library_extraction(self):
        self.bundle()
        with self.archive.open("ab") as archive:
            archive.write(b"changed archive")
        with self.assertRaisesRegex(ValueError, "checksum"):
            self.unpack()
        self.assertEqual(list(self.output.iterdir()), [])

    def test_wrong_source_or_divergent_embedded_manifest_is_rejected(self):
        self.bundle()
        with self.assertRaisesRegex(ValueError, "source commit"):
            self.unpack("2" * 40)
        self.bundle(embedded_commit="2" * 40)
        with self.assertRaisesRegex(ValueError, "manifests differ"):
            self.unpack()
        self.assertEqual(list(self.output.iterdir()), [])

    def test_library_symlink_cannot_select_a_fallback_binary(self):
        self.bundle(symlink=True)
        with self.assertRaisesRegex(ValueError, "regular file"):
            self.unpack()
        self.assertEqual(list(self.output.iterdir()), [])


class DartLauncherEvidenceTest(unittest.TestCase):
    def run_consumer(self, launcher, platform="win32", executable_exists=True):
        with tempfile.TemporaryDirectory(prefix="consumer launcher with spaces ") as temporary:
            output = Path(temporary)
            library = output / "packaged-library"
            library.write_bytes(b"controlled library")
            commands = []

            def run(command, **kwargs):
                commands.append((command, kwargs))
                return SimpleNamespace(returncode=0, stdout="controlled profile output")

            arguments = ["consumer", "--archive", str(library), "--checksum", str(library),
                         "--manifest", str(library), "--expected-commit", "1" * 40,
                         "--output-dir", str(output)]
            with mock.patch.object(consumers.sys, "argv", arguments), \
                 mock.patch.object(consumers.sys, "platform", platform), \
                 mock.patch.object(consumers.shutil, "which", return_value=launcher), \
                 mock.patch.object(consumers, "unpack_library", return_value=({}, library)), \
                 mock.patch.object(consumers, "audit_production_library", return_value=18), \
                 mock.patch.object(consumers, "audit_rustls_snapshot_abi", return_value={}), \
                 mock.patch.object(consumers, "profile_results", return_value={}), \
                 mock.patch.object(consumers.Path, "is_file", return_value=executable_exists), \
                 mock.patch.object(consumers.subprocess, "run", side_effect=run), \
                 mock.patch("sys.stdout", new_callable=io.StringIO), \
                 mock.patch("sys.stderr", new_callable=io.StringIO):
                status = consumers.main()
            report = json.loads((output / "consumer-proof.json").read_text())
            return status, commands, report

    def test_windows_executable_suffix_and_wrappers_launch_all_profiles(self):
        for suffix in (".EXE", ".exe", ".BAT", ".cmd"):
            with self.subTest(suffix=suffix):
                status, commands, report = self.run_consumer("C:/Dart SDK/bin/dart" + suffix)
                self.assertEqual(status, 0)
                self.assertTrue(report["runtime_acceptance"])
                self.assertEqual(len(commands), len(consumers.PROFILES))
                for command, kwargs in commands:
                    self.assertEqual(command[0], "C:/Dart SDK/bin/dart.exe")
                    self.assertIn("--exclude-tags=ffi-owner-oracles", command)
                    self.assertEqual(kwargs["env"]["CONNECTANUM_SKIP_NATIVE_BUILD"], "true")
                    self.assertEqual(kwargs["env"]["CONNECTANUM_FORWARD_NATIVE_PUBLISH"], "1")

    def test_missing_dart_or_windows_executable_fails_before_starting_profiles(self):
        for launcher in (None, "C:/Dart SDK/bin/dart.EXE", "C:/Dart SDK/bin/dart.cmd"):
            with self.subTest(launcher=launcher):
                status, commands, report = self.run_consumer(launcher, executable_exists=False)
                self.assertEqual(status, 1)
                self.assertEqual(commands, [])
                self.assertFalse(report["runtime_acceptance"])
                self.assertIn("executable unavailable", report["error"])

    def test_posix_launcher_is_preserved(self):
        status, commands, report = self.run_consumer("/Dart SDK/bin/dart", platform="darwin")
        self.assertEqual(status, 0)
        self.assertTrue(report["runtime_acceptance"])
        self.assertEqual({command[0] for command, _ in commands}, {"/Dart SDK/bin/dart"})


if __name__ == "__main__":
    unittest.main()
