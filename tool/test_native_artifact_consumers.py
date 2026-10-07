#!/usr/bin/env python3
"""Failure controls for packaged production-library consumer evidence."""

from __future__ import annotations

import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

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


if __name__ == "__main__":
    unittest.main()
