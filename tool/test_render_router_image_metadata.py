import sys
import tempfile
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parent))

import render_router_image_metadata as metadata


SHA = "0123456789abcdef0123456789abcdef01234567"


class RouterImageMetadataTest(unittest.TestCase):
    def test_stable_tag_push_expands_version_tags(self) -> None:
        result = metadata.resolve_router_image_metadata(
            owner="Konsultaner",
            repository="konsultaner/connectanum-dart",
            sha=SHA,
            ref_type="tag",
            ref_name="v1.2.3",
            event_name="push",
            dry_run="false",
        )

        self.assertTrue(result.publish)
        self.assertEqual(result.mode, "publish")
        self.assertEqual(result.provenance, "mode=max")
        self.assertEqual(result.sbom, "true")
        self.assertEqual(
            result.tags,
            (
                "ghcr.io/konsultaner/connectanum-router:1.2.3",
                "ghcr.io/konsultaner/connectanum-router:1.2",
                "ghcr.io/konsultaner/connectanum-router:1",
                "ghcr.io/konsultaner/connectanum-router:latest",
            ),
        )
        self.assertIn("org.opencontainers.image.version=1.2.3", result.labels)

    def test_prerelease_tag_push_only_uses_exact_version(self) -> None:
        result = metadata.resolve_router_image_metadata(
            owner="konsultaner",
            repository="konsultaner/connectanum-dart",
            sha=SHA,
            ref_type="tag",
            ref_name="v1.2.3-rc.1",
            event_name="push",
            dry_run="false",
        )

        self.assertEqual(
            result.tags,
            ("ghcr.io/konsultaner/connectanum-router:1.2.3-rc.1",),
        )

    def test_manual_dry_run_defaults_to_sha_tag_and_cacheonly_output(self) -> None:
        result = metadata.resolve_router_image_metadata(
            owner="konsultaner",
            repository="konsultaner/connectanum-dart",
            sha=SHA,
            ref_type="branch",
            ref_name="add-router",
            event_name="workflow_dispatch",
            dry_run="true",
        )

        self.assertFalse(result.publish)
        self.assertEqual(result.outputs, "type=cacheonly")
        self.assertEqual(result.provenance, "false")
        self.assertEqual(result.sbom, "false")
        self.assertEqual(
            result.tags,
            ("ghcr.io/konsultaner/connectanum-router:sha-0123456789ab",),
        )

    def test_manual_publish_requires_exact_tag_approval(self) -> None:
        with self.assertRaisesRegex(
            metadata.RouterImageMetadataError,
            "requires publish_approval",
        ):
            metadata.resolve_router_image_metadata(
                owner="konsultaner",
                repository="konsultaner/connectanum-dart",
                sha=SHA,
                ref_type="branch",
                ref_name="add-router",
                event_name="workflow_dispatch",
                input_image_tag="validation-abc1234",
                dry_run="false",
                publish_approval="wrong-tag",
            )

    def test_manual_publish_accepts_exact_tag_approval(self) -> None:
        result = metadata.resolve_router_image_metadata(
            owner="konsultaner",
            repository="konsultaner/connectanum-dart",
            sha=SHA,
            ref_type="branch",
            ref_name="add-router",
            event_name="workflow_dispatch",
            input_image_tag="validation-abc1234",
            dry_run="false",
            publish_approval="validation-abc1234",
        )

        self.assertTrue(result.publish)
        self.assertEqual(result.outputs, "")
        self.assertEqual(result.provenance, "mode=max")
        self.assertEqual(result.sbom, "true")

    def test_rejects_publish_of_dry_run_tag(self) -> None:
        with self.assertRaisesRegex(
            metadata.RouterImageMetadataError,
            "Dry-run image tags must only be used",
        ):
            metadata.resolve_router_image_metadata(
                owner="konsultaner",
                repository="konsultaner/connectanum-dart",
                sha=SHA,
                ref_type="branch",
                ref_name="add-router",
                event_name="workflow_dispatch",
                input_image_tag="dry-run-abc1234",
                dry_run="false",
                publish_approval="dry-run-abc1234",
            )

    def test_rejects_invalid_docker_tag(self) -> None:
        with self.assertRaisesRegex(
            metadata.RouterImageMetadataError,
            "Image tags must be",
        ):
            metadata.resolve_router_image_metadata(
                owner="konsultaner",
                repository="konsultaner/connectanum-dart",
                sha=SHA,
                ref_type="branch",
                ref_name="add-router",
                event_name="workflow_dispatch",
                input_image_tag="not/a/tag",
                dry_run="true",
            )

    def test_cli_writes_github_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output_path = Path(directory) / "github-output.txt"
            summary_path = Path(directory) / "summary.md"

            exit_code = metadata.main(
                [
                    "--owner",
                    "konsultaner",
                    "--repository",
                    "konsultaner/connectanum-dart",
                    "--sha",
                    SHA,
                    "--ref-type",
                    "branch",
                    "--ref-name",
                    "add-router",
                    "--event-name",
                    "workflow_dispatch",
                    "--dry-run",
                    "true",
                    "--github-output",
                    str(output_path),
                    "--summary",
                    str(summary_path),
                ]
            )

            self.assertEqual(exit_code, 0)
            output = output_path.read_text(encoding="utf-8")
            self.assertIn("push=false", output)
            self.assertIn("outputs=type=cacheonly", output)
            self.assertIn("provenance=false", output)
            self.assertIn("sbom=false", output)
            self.assertIn("tags<<EOF", output)
            summary = summary_path.read_text()
            self.assertIn("Router Image Metadata", summary)
            self.assertIn("Provenance: `false`", summary)
            self.assertIn("SBOM: `false`", summary)


if __name__ == "__main__":
    unittest.main()
