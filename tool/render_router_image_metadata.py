#!/usr/bin/env python3
"""Resolve and validate router container image metadata for GitHub Actions."""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path


_DOCKER_TAG_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$")
_STABLE_SEMVER_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")


class RouterImageMetadataError(ValueError):
    """Raised when router image metadata or publish intent is unsafe."""


@dataclass(frozen=True)
class RouterImageMetadata:
    image: str
    tags: tuple[str, ...]
    labels: tuple[str, ...]
    publish: bool
    outputs: str
    mode: str
    provenance: str
    sbom: str


def _parse_bool(value: str | bool, *, name: str) -> bool:
    if isinstance(value, bool):
        return value

    normalized = value.strip().lower()
    if normalized == "true":
        return True
    if normalized == "false":
        return False

    raise RouterImageMetadataError(
        f"{name} must be either true or false, got {value!r}."
    )


def _validate_docker_tag(tag: str) -> str:
    normalized = tag.strip()
    if not normalized:
        raise RouterImageMetadataError("Image tag is required.")
    if not _DOCKER_TAG_RE.fullmatch(normalized):
        raise RouterImageMetadataError(
            "Image tags must be 1-128 characters and contain only letters, "
            "numbers, underscores, dots, or hyphens."
        )
    return normalized


def _default_sha_tag(sha: str) -> str:
    cleaned = sha.strip()
    if len(cleaned) < 12:
        raise RouterImageMetadataError("GITHUB_SHA must contain at least 12 characters.")
    return f"sha-{cleaned[:12]}"


def _image_name(owner: str) -> str:
    normalized_owner = owner.strip().lower()
    if not normalized_owner:
        raise RouterImageMetadataError("Repository owner is required.")
    return f"ghcr.io/{normalized_owner}/connectanum-router"


def resolve_router_image_metadata(
    *,
    owner: str,
    repository: str,
    sha: str,
    ref_type: str,
    ref_name: str,
    event_name: str,
    input_image_tag: str = "",
    dry_run: str | bool = "false",
    publish_approval: str = "",
) -> RouterImageMetadata:
    image = _image_name(owner)
    repository = repository.strip()
    if not repository:
        raise RouterImageMetadataError("Repository is required.")

    labels = [
        f"org.opencontainers.image.source=https://github.com/{repository}",
        f"org.opencontainers.image.revision={sha.strip()}",
        "org.opencontainers.image.title=connectanum-router",
        "org.opencontainers.image.description=Multi-arch container image for the Connectanum router runner",
    ]
    tags: list[str] = []

    normalized_ref_type = ref_type.strip()
    normalized_ref_name = ref_name.strip()
    if normalized_ref_type == "tag" and normalized_ref_name.startswith("v"):
        version = _validate_docker_tag(normalized_ref_name[1:])
        tags.append(f"{image}:{version}")
        labels.append(f"org.opencontainers.image.version={version}")

        if _STABLE_SEMVER_RE.fullmatch(version):
            major_minor = version.rsplit(".", 1)[0]
            major = version.split(".", 1)[0]
            tags.extend(
                [
                    f"{image}:{major_minor}",
                    f"{image}:{major}",
                    f"{image}:latest",
                ]
            )
    else:
        explicit_tag = input_image_tag.strip()
        tag = _validate_docker_tag(explicit_tag or _default_sha_tag(sha))
        tags.append(f"{image}:{tag}")
        labels.append(f"org.opencontainers.image.version={tag}")

    is_dry_run = _parse_bool(dry_run, name="dry_run")
    publish = not is_dry_run
    primary_tag = tags[0].rsplit(":", 1)[1]
    mode = "dry-run" if is_dry_run else "publish"

    if "dry-run" in primary_tag and publish:
        raise RouterImageMetadataError(
            "Dry-run image tags must only be used with dry_run=true. "
            "Use a non-dry-run tag before publishing."
        )

    if event_name.strip() == "workflow_dispatch" and publish:
        approval = publish_approval.strip()
        if approval != primary_tag:
            raise RouterImageMetadataError(
                "Manual router image publishing requires publish_approval to "
                "exactly match the primary image tag. Use dry_run=true for "
                "validation builds."
            )

    return RouterImageMetadata(
        image=image,
        tags=tuple(tags),
        labels=tuple(labels),
        publish=publish,
        outputs="" if publish else "type=cacheonly",
        mode=mode,
        provenance="mode=max" if publish else "false",
        sbom="true" if publish else "false",
    )


def render_summary(metadata: RouterImageMetadata) -> str:
    tag_lines = "\n".join(f"- `{tag}`" for tag in metadata.tags)
    label_lines = "\n".join(f"- `{label}`" for label in metadata.labels)
    return f"""## Router Image Metadata

- Image: `{metadata.image}`
- Mode: `{metadata.mode}`
- Publish: `{str(metadata.publish).lower()}`
- Provenance: `{metadata.provenance}`
- SBOM: `{metadata.sbom}`

### Tags

{tag_lines}

### Labels

{label_lines}
"""


def _append_github_output(path: str, metadata: RouterImageMetadata) -> None:
    fields = {
        "image": metadata.image,
        "tags": "\n".join(metadata.tags),
        "labels": "\n".join(metadata.labels),
        "push": "true" if metadata.publish else "false",
        "outputs": metadata.outputs,
        "mode": metadata.mode,
        "provenance": metadata.provenance,
        "sbom": metadata.sbom,
    }

    with Path(path).open("a", encoding="utf-8") as output:
        for name, value in fields.items():
            if "\n" in value or name in {"tags", "labels"}:
                output.write(f"{name}<<EOF\n{value}\nEOF\n")
            else:
                output.write(f"{name}={value}\n")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Render and validate Connectanum router image metadata.",
    )
    parser.add_argument(
        "--owner",
        default=os.environ.get("GITHUB_REPOSITORY_OWNER", "konsultaner"),
    )
    parser.add_argument(
        "--repository",
        default=os.environ.get("GITHUB_REPOSITORY", "konsultaner/connectanum-dart"),
    )
    parser.add_argument("--sha", default=os.environ.get("GITHUB_SHA", "HEAD"))
    parser.add_argument("--ref-type", default=os.environ.get("GITHUB_REF_TYPE", ""))
    parser.add_argument("--ref-name", default=os.environ.get("GITHUB_REF_NAME", ""))
    parser.add_argument(
        "--event-name",
        default=os.environ.get("GITHUB_EVENT_NAME", ""),
    )
    parser.add_argument(
        "--input-image-tag",
        default=os.environ.get("INPUT_IMAGE_TAG", ""),
    )
    parser.add_argument("--dry-run", default=os.environ.get("INPUT_DRY_RUN", "false"))
    parser.add_argument(
        "--publish-approval",
        default=os.environ.get("INPUT_PUBLISH_APPROVAL", ""),
    )
    parser.add_argument("--github-output")
    parser.add_argument("--summary")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        metadata = resolve_router_image_metadata(
            owner=args.owner,
            repository=args.repository,
            sha=args.sha,
            ref_type=args.ref_type,
            ref_name=args.ref_name,
            event_name=args.event_name,
            input_image_tag=args.input_image_tag,
            dry_run=args.dry_run,
            publish_approval=args.publish_approval,
        )
    except RouterImageMetadataError as error:
        print(f"Router image metadata rejected: {error}", file=sys.stderr)
        return 1

    summary = render_summary(metadata)
    if args.github_output:
        _append_github_output(args.github_output, metadata)
    if args.summary:
        Path(args.summary).write_text(summary, encoding="utf-8")
    else:
        print(summary, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
