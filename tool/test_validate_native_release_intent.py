import sys
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parent))

import validate_native_release_intent as intent


class NativeReleaseIntentTest(unittest.TestCase):
    def test_dry_run_tag_is_allowed_for_dry_run_preview(self) -> None:
        result = intent.validate_release_intent(
            release_tag="ct-ffi-v2026.04.28-dry-run.abc1234",
            event_name="workflow_dispatch",
            ref_type="branch",
            dry_run="true",
            prerelease="false",
        )

        self.assertEqual(result.release_kind, "native")
        self.assertEqual(result.publish_mode, "dry-run")

    def test_dry_run_tag_is_rejected_for_publish(self) -> None:
        with self.assertRaisesRegex(
            intent.ReleaseIntentError,
            "Dry-run release tags must only be used",
        ):
            intent.validate_release_intent(
                release_tag="ct-ffi-v2026.04.28-dry-run.abc1234",
                event_name="workflow_dispatch",
                ref_type="branch",
                dry_run="false",
                prerelease="true",
            )

    def test_validation_tag_publish_requires_prerelease(self) -> None:
        with self.assertRaisesRegex(
            intent.ReleaseIntentError,
            "Validation release tags must be published as prereleases",
        ):
            intent.validate_release_intent(
                release_tag="ct-ffi-v2026.04.28-validation.abc1234",
                event_name="workflow_dispatch",
                ref_type="branch",
                dry_run="false",
                prerelease="false",
            )

    def test_validation_tag_publish_accepts_prerelease(self) -> None:
        result = intent.validate_release_intent(
            release_tag="ct-ffi-v2026.04.28-validation.abc1234",
            event_name="workflow_dispatch",
            ref_type="branch",
            dry_run="false",
            prerelease="true",
        )

        self.assertEqual(result.publish_mode, "prerelease")

    def test_manual_stable_publish_requires_exact_approval(self) -> None:
        with self.assertRaisesRegex(
            intent.ReleaseIntentError,
            "Manual stable release publishing requires",
        ):
            intent.validate_release_intent(
                release_tag="ct-ffi-v2026.04.28",
                event_name="workflow_dispatch",
                ref_type="branch",
                dry_run="false",
                prerelease="false",
                stable_release_approval="wrong-tag",
            )

    def test_manual_stable_publish_accepts_exact_approval(self) -> None:
        result = intent.validate_release_intent(
            release_tag="ct-ffi-v2026.04.28",
            event_name="workflow_dispatch",
            ref_type="branch",
            dry_run="false",
            prerelease="false",
            stable_release_approval="ct-ffi-v2026.04.28",
        )

        self.assertEqual(result.publish_mode, "stable")

    def test_tag_push_stable_publish_does_not_require_manual_approval(self) -> None:
        result = intent.validate_release_intent(
            release_tag="v1.2.3",
            event_name="push",
            ref_type="tag",
            dry_run="false",
            prerelease="false",
        )

        self.assertEqual(result.release_kind, "project")
        self.assertEqual(result.publish_mode, "stable")

    def test_rejects_unexpected_tag_prefix(self) -> None:
        with self.assertRaisesRegex(intent.ReleaseIntentError, "ct-ffi-v or v"):
            intent.validate_release_intent(
                release_tag="release-2026.04.28",
                event_name="workflow_dispatch",
                ref_type="branch",
                dry_run="true",
                prerelease="false",
            )

    def test_rejects_invalid_boolean_values(self) -> None:
        with self.assertRaisesRegex(intent.ReleaseIntentError, "dry_run"):
            intent.validate_release_intent(
                release_tag="ct-ffi-v2026.04.28",
                event_name="workflow_dispatch",
                ref_type="branch",
                dry_run="yes",
                prerelease="false",
            )


if __name__ == "__main__":
    unittest.main()
