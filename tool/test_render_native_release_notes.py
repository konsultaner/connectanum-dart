import sys
import tempfile
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parent))

import render_native_release_notes as notes


class NativeReleaseNotesTest(unittest.TestCase):
    def test_ct_ffi_release_notes_are_platform_complete(self) -> None:
        rendered = notes.render_release_notes(
            release_tag="ct-ffi-v2026.04.28",
            repository="konsultaner/connectanum-dart",
            server_url="https://github.com",
            commit_sha="abc123",
            workflow_ref=(
                "konsultaner/connectanum-dart/.github/workflows/"
                "native-artifacts.yml@refs/tags/ct-ffi-v2026.04.28"
            ),
            owner="Konsultaner",
        )

        self.assertIn("standalone native transport bundles", rendered)
        self.assertIn("Windows x64 (`x86_64-pc-windows-msvc`)", rendered)
        self.assertIn(
            "CONNECTANUM_NATIVE_RELEASE_TAG=ct-ffi-v2026.04.28 dart run "
            "connectanum_router --config path/to/router.yaml",
            rendered,
        )
        self.assertIn(
            "dart packages/connectanum_router/tool/install_native.dart --tag "
            "ct-ffi-v2026.04.28",
            rendered,
        )
        self.assertIn(
            "gh attestation verify path/to/ct-ffi-<host-triple>.tar.gz",
            rendered,
        )
        self.assertIn("ghcr.io/konsultaner/connectanum-router", rendered)
        self.assertNotIn("## Changelog", rendered)

    def test_project_release_notes_append_generated_changelog(self) -> None:
        rendered = notes.render_release_notes(
            release_tag="v1.2.3",
            repository="example/connectanum-dart",
            server_url="https://github.example",
            commit_sha="def456",
            workflow_ref=(
                "example/connectanum-dart/.github/workflows/"
                "native-artifacts.yml@refs/tags/v1.2.3"
            ),
            owner="Example",
            generated_notes="* Fix release publishing",
        )

        self.assertIn("current prebuilt native transport bundles", rendered)
        self.assertIn("https://github.example/example/connectanum-dart", rendered)
        self.assertIn("## Changelog", rendered)
        self.assertIn("* Fix release publishing", rendered)

    def test_cli_renders_generated_notes_file(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            generated = Path(temp_dir) / "generated.md"
            generated.write_text("* Generated entry\n", encoding="utf-8")

            rendered = notes.render_release_notes(
                release_tag="v1.0.0",
                repository="example/repo",
                server_url="https://github.com",
                commit_sha="123",
                workflow_ref=(
                    "example/repo/.github/workflows/"
                    "native-artifacts.yml@refs/tags/v1.0.0"
                ),
                owner="Example",
                generated_notes=generated.read_text(encoding="utf-8"),
            )

        self.assertIn("## Changelog", rendered)
        self.assertIn("* Generated entry", rendered)


if __name__ == "__main__":
    unittest.main()
