import io
import json
from pathlib import Path
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import mqtt_dart_copy_probe as probe


class GeneratorGuards(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sources = {n: (probe.ROOT / n).read_bytes() for n in probe.SOURCE_HASHES}

    def setUp(self):
        # Unit archive/extraction checks must also run in shallow normal-CI
        # checkouts. Actual full-source/Dart controls separately require the
        # unmodified real AD48 archive and never use this synthetic fixture.
        fixture = {**self.sources, "sentinel.txt": b"unchanged",
                   **{name: (probe.ROOT / name).read_bytes() for name in [
                       "pubspec.yaml", "packages/connectanum_core/pubspec.yaml",
                       "packages/connectanum_router/pubspec.yaml"]}}
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode="w") as archive:
            for name, value in fixture.items():
                member = tarfile.TarInfo(name)
                member.size = len(value)
                archive.addfile(member, io.BytesIO(value))
        encoded = data.getvalue()
        self.archive_mock = patch.object(
            probe, "subprocess",
            SimpleNamespace(check_output=lambda *args, **kwargs: encoded))
        self.digest_mock = patch.object(probe, "ARCHIVE_SHA256", probe.sha(encoded))
        self.archive_mock.start()
        self.digest_mock.start()
        self.addCleanup(self.archive_mock.stop)
        self.addCleanup(self.digest_mock.stop)

    def test_only_exact_targets_and_counter_are_changed(self):
        result = probe.instrument(self.sources)
        self.assertEqual(set(result), {*probe.SOURCE_HASHES, probe.COUNTER})
        self.assertTrue(all(result[n] != self.sources[n] for n in self.sources))
        self.assertIn(b"Uint8List.fromList(buffer.asTypedList(result))", result[probe.NATIVE])
        self.assertIn(b"next.setRange(0, bodyEnd, body)", result[probe.FRAME])
        self.assertIn(b"currentBody.setRange(bodyEnd, bodyEnd + count, input, offset)",
                      result[probe.FRAME])

    def test_changed_source_rejected(self):
        for name in self.sources:
            changed = {**self.sources, name: self.sources[name] + b"\n"}
            with self.subTest(name=name), self.assertRaises(ValueError):
                probe.instrument(changed)

    def test_wrong_source_inventory_rejected(self):
        for changed in [
            {**self.sources, "unexpected.dart": b""},
            {k: v for k, v in self.sources.items() if k != probe.FRAME},
        ]:
            with self.assertRaises(ValueError):
                probe.instrument(changed)

    def test_replacement_must_be_unique(self):
        for text in ["absent", "needle needle"]:
            with self.assertRaises(ValueError):
                probe.replace_once(text, "needle", "changed")

    def test_archive_rejects_escape_and_links_before_writes(self):
        for name, link in [("../escape", False), ("/escape", False), ("link", True)]:
            with tempfile.TemporaryDirectory() as temp:
                data = io.BytesIO()
                with tarfile.open(fileobj=data, mode="w") as tar:
                    safe = tarfile.TarInfo("first")
                    safe.size = 1
                    tar.addfile(safe, io.BytesIO(b"x"))
                    bad = tarfile.TarInfo(name)
                    if link:
                        bad.type = tarfile.SYMTYPE
                        bad.linkname = "../escape"
                    tar.addfile(bad)
                with self.assertRaises(ValueError):
                    probe.unpack(data.getvalue(), Path(temp))
                self.assertFalse(list(Path(temp).iterdir()))

    def test_prepare_and_verify_both_controls(self):
        for original in [False, True]:
            with tempfile.TemporaryDirectory() as temp:
                output = Path(temp) / "probe"
                source = probe.prepare(output, probe.ROOT, original=original)
                manifest = probe.verify_shadow(output)
                self.assertEqual(manifest["original_control"], original)
                self.assertEqual((source / probe.COUNTER).exists(), not original)
                for name in probe.LOCKS:
                    self.assertEqual(probe.sha((source / name).read_bytes()),
                                     probe.LOCKS[name])
                with self.assertRaises(ValueError):
                    probe.prepare(output, probe.ROOT, original=original)

    def test_mutation_and_extra_source_fail_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "probe"
            source = probe.prepare(output, probe.ROOT)
            for name in [probe.FRAME, probe.NATIVE, probe.BROKER, probe.COUNTER,
                         "pubspec.lock"]:
                path = source / name
                prior = path.read_bytes()
                path.write_bytes(prior + b"\n")
                with self.subTest(name=name), self.assertRaises(ValueError):
                    probe.verify_shadow(output)
                path.write_bytes(prior)
            added = source / "unexpected.dart"
            added.write_text("void main() {}")
            with self.assertRaises(ValueError):
                probe.verify_shadow(output)
            added.unlink()
            (source / "unexpected-link").symlink_to(source / probe.FRAME)
            with self.assertRaises(ValueError):
                probe.verify_shadow(output)

    def test_readiness_is_never_granted_by_generator(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "probe"
            probe.prepare(output, probe.ROOT)
            path = output / "shadow-manifest.json"
            manifest = json.loads(path.read_text())
            self.assertIs(manifest["capture_ready"], False)
            manifest["capture_ready"] = True
            path.write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):
                probe.verify_shadow(output)

    def test_wrong_lock_rejected_before_output_creation(self):
        with tempfile.TemporaryDirectory() as temp:
            lock_root = Path(temp) / "locks"
            for name in probe.LOCKS:
                path = lock_root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((probe.ROOT / name).read_bytes())
            (lock_root / "pubspec.lock").write_text("wrong")
            output = Path(temp) / "probe"
            with self.assertRaises(ValueError):
                probe.prepare(output, lock_root)
            self.assertFalse(output.exists())

    def test_generated_workspace_reference_is_exact_and_contained(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "probe"
            source = probe.prepare(output, probe.ROOT)
            ref = source / "packages/connectanum_core/.dart_tool/pub/workspace_ref.json"
            ref.parent.mkdir(parents=True)
            ref.write_text(json.dumps({"workspaceRoot": "../../../.."}))
            probe.verify_shadow(output)
            for value in [{"workspaceRoot": "/tmp"}, {"workspaceRoot": "../../../..", "extra": 1}]:
                ref.write_text(json.dumps(value))
                with self.assertRaises(ValueError):
                    probe.verify_shadow(output)

    def test_workspace_package_uris_cannot_borrow_original_sources(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "probe"
            source = probe.prepare(output, probe.ROOT)
            config = source / ".dart_tool/package_config.json"
            config.parent.mkdir()
            entries = [
                {"name": "connectanum_workspace", "rootUri": "../", "packageUri": "lib/"},
                {"name": "connectanum_core", "rootUri": "../packages/connectanum_core", "packageUri": "lib/"},
                {"name": "connectanum_router", "rootUri": "../packages/connectanum_router", "packageUri": "lib/"},
            ]
            config.write_text(json.dumps({"packages": entries}))
            probe.verify_workspace_packages(source)
            entries[1]["rootUri"] = (probe.ROOT / "packages/connectanum_core").as_uri()
            config.write_text(json.dumps({"packages": entries}))
            with self.assertRaises(ValueError):
                probe.verify_workspace_packages(source)


if __name__ == "__main__":
    unittest.main()
