#!/usr/bin/env python3
"""Validate GitHub native release publication intent before mutation."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass


_RELEASE_TAG_RE = re.compile(r"^(?:ct-ffi-v|v)[0-9A-Za-z][0-9A-Za-z._+-]*$")


class ReleaseIntentError(ValueError):
    """Raised when a release request is unsafe or malformed."""


@dataclass(frozen=True)
class ReleaseIntent:
    release_tag: str
    release_kind: str
    publish_mode: str


def _parse_bool(value: str | bool, *, name: str) -> bool:
    if isinstance(value, bool):
        return value

    normalized = value.strip().lower()
    if normalized == "true":
        return True
    if normalized == "false":
        return False

    raise ReleaseIntentError(f"{name} must be either true or false, got {value!r}.")


def validate_release_intent(
    *,
    release_tag: str,
    event_name: str,
    ref_type: str,
    dry_run: str | bool,
    prerelease: str | bool,
    stable_release_approval: str = "",
) -> ReleaseIntent:
    tag = release_tag.strip()
    if not tag:
        raise ReleaseIntentError("Release tag is required.")

    if not _RELEASE_TAG_RE.fullmatch(tag):
        raise ReleaseIntentError(
            "Release tag must start with ct-ffi-v or v and contain only "
            "letters, numbers, dots, underscores, plus signs, or hyphens."
        )

    is_dry_run = _parse_bool(dry_run, name="dry_run")
    is_prerelease = _parse_bool(prerelease, name="prerelease")
    release_kind = "native" if tag.startswith("ct-ffi-v") else "project"
    normalized_event = event_name.strip()
    normalized_ref_type = ref_type.strip()
    approval = stable_release_approval.strip()

    if "-dry-run" in tag and not is_dry_run:
        raise ReleaseIntentError(
            "Dry-run release tags must only be used with dry_run=true. "
            "Use a non-dry-run tag before publishing."
        )

    if "-validation" in tag and not (is_dry_run or is_prerelease):
        raise ReleaseIntentError(
            "Validation release tags must be published as prereleases."
        )

    publish_mode = "dry-run"
    if not is_dry_run:
        publish_mode = "prerelease" if is_prerelease else "stable"

    if (
        normalized_event == "workflow_dispatch"
        and normalized_ref_type != "tag"
        and publish_mode == "stable"
        and approval != tag
    ):
        raise ReleaseIntentError(
            "Manual stable release publishing requires stable_release_approval "
            "to exactly match the release tag. Use dry_run=true for previews or "
            "prerelease=true for validation releases."
        )

    return ReleaseIntent(
        release_tag=tag,
        release_kind=release_kind,
        publish_mode=publish_mode,
    )


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate Connectanum GitHub Release publication intent.",
    )
    parser.add_argument("--release-tag", required=True)
    parser.add_argument("--event-name", default="")
    parser.add_argument("--ref-type", default="")
    parser.add_argument("--dry-run", default="false")
    parser.add_argument("--prerelease", default="false")
    parser.add_argument("--stable-release-approval", default="")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        intent = validate_release_intent(
            release_tag=args.release_tag,
            event_name=args.event_name,
            ref_type=args.ref_type,
            dry_run=args.dry_run,
            prerelease=args.prerelease,
            stable_release_approval=args.stable_release_approval,
        )
    except ReleaseIntentError as error:
        print(f"Release intent rejected: {error}", file=sys.stderr)
        return 1

    print(
        "Release intent accepted: "
        f"{intent.release_tag} ({intent.release_kind}, {intent.publish_mode})."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
