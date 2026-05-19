#!/usr/bin/env python3
"""Render human-readable GitHub Release notes for native ct_ffi bundles."""

from __future__ import annotations

import argparse
import os
import re
from pathlib import Path

from render_router_image_metadata import resolve_router_image_metadata


PLATFORMS = (
    ("Linux x64", "x86_64-unknown-linux-gnu"),
    ("Linux arm64", "aarch64-unknown-linux-gnu"),
    ("macOS arm64", "aarch64-apple-darwin"),
    ("macOS Intel", "x86_64-apple-darwin"),
    ("Windows x64", "x86_64-pc-windows-msvc"),
)

_PROJECT_PRERELEASE_RE = re.compile(r"^v\d+\.\d+\.\d+-.+")


def _release_summary(release_tag: str) -> str:
    if release_tag.startswith("ct-ffi-v"):
        return (
            "This release publishes the standalone native transport bundles "
            "used by the Connectanum router and native client transports."
        )
    if _PROJECT_PRERELEASE_RE.fullmatch(release_tag):
        return (
            "This release candidate publishes prebuilt native transport "
            "bundles for the Connectanum router and native client transports, "
            "and records the matching router container image tags for "
            "integration testing."
        )
    return (
        "This release publishes prebuilt native transport bundles for the "
        "Connectanum router and native client transports, and records the "
        "matching router container image tags for production deployments."
    )


def _release_stability(release_tag: str) -> str:
    if release_tag.startswith("ct-ffi-v"):
        return "standalone native bundle release"
    if _PROJECT_PRERELEASE_RE.fullmatch(release_tag):
        return "release candidate / prerelease"
    return "stable project release"


def _repo_url(server_url: str, repository: str) -> str:
    return f"{server_url.rstrip('/')}/{repository}"


def _router_image_section(
    *,
    release_tag: str,
    repository: str,
    commit_sha: str,
    owner: str,
) -> str:
    image = f"ghcr.io/{owner.strip().lower()}/connectanum-router"

    if not release_tag.startswith("v"):
        return f"""## Router container image

No router image tag is implied by this standalone native-bundle release.
Router images are released separately at `{image}`; confirm package availability
in the deployment guide before using one in production.
"""

    metadata = resolve_router_image_metadata(
        owner=owner,
        repository=repository,
        sha=commit_sha,
        ref_type="tag",
        ref_name=release_tag,
        event_name="push",
        dry_run="true",
    )
    tag_lines = "\n".join(f"- `{tag}`" for tag in metadata.tags)

    return f"""## Router container image

The matching router-image workflow publishes these tags for this project
release:

{tag_lines}

Use the exact `v*` tag or full semver tag for immutable deployments. Treat
minor, major, and `latest` tags as moving aliases when they are present.
Confirm package availability in the deployment guide before using an image in
production.
"""


def render_release_notes(
    *,
    release_tag: str,
    repository: str,
    server_url: str,
    commit_sha: str,
    workflow_ref: str,
    owner: str,
    generated_notes: str = "",
) -> str:
    repo_url = _repo_url(server_url, repository)
    workflow_identity = f"https://github.com/{workflow_ref}"
    platform_lines = "\n".join(
        f"- {name} (`{host_triple}`)" for name, host_triple in PLATFORMS
    )
    router_image_section = _router_image_section(
        release_tag=release_tag,
        repository=repository,
        commit_sha=commit_sha,
        owner=owner,
    )

    notes = f"""## What this release includes

{_release_summary(release_tag)}

## Release status

- Tag: `{release_tag}`
- Stability: {_release_stability(release_tag)}
- Commit: `{commit_sha}`

## Assets

- `ct-ffi-<host-triple>.tar.gz` - prebuilt native transport bundle for one platform
- `*.sha256` - checksum for the matching archive
- `*.manifest.json` - machine-readable build metadata
- `*.sigstore.json` - detached Sigstore verification bundle

## Current prebuilt platforms

{platform_lines}

## How to use the bundle

1. Let the Dart build hook fetch the matching bundle automatically:
   - `CONNECTANUM_NATIVE_RELEASE_TAG={release_tag} dart run connectanum_router --config path/to/router.yaml`
   - `CONNECTANUM_NATIVE_RELEASE_TAG={release_tag} dart test`
2. Or download the archive that matches your platform, extract it, and point
   `CONNECTANUM_NATIVE_LIB` at the included library.
3. From a source checkout, you can prefetch the current host bundle explicitly:
   - `dart packages/connectanum_router/tool/install_native.dart --tag {release_tag}`
   - `dart packages/connectanum_client/tool/install_native.dart --tag {release_tag}`

{router_image_section}

## Verification

- GitHub attestation:
  `gh attestation verify path/to/ct-ffi-<host-triple>.tar.gz -R {repository}`
- Detached Sigstore bundle:
  `cosign verify-blob path/to/ct-ffi-<host-triple>.tar.gz --bundle path/to/ct-ffi-<host-triple>.tar.gz.sigstore.json --certificate-identity {workflow_identity} --certificate-oidc-issuer https://token.actions.githubusercontent.com`

## Related links

- Repository README: {repo_url}/blob/{commit_sha}/README.md
- Deployment guide: {repo_url}/blob/{commit_sha}/docs/deployment.md
"""

    generated_notes = generated_notes.strip()
    if generated_notes:
        notes += f"\n## Changelog\n\n{generated_notes}\n"

    return notes


def _read_optional(path: str | None) -> str:
    if not path:
        return ""
    return Path(path).read_text(encoding="utf-8")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Render GitHub Release notes for native ct_ffi bundles.",
    )
    parser.add_argument("--release-tag", required=True)
    parser.add_argument(
        "--repository",
        default=os.environ.get("GITHUB_REPOSITORY", "konsultaner/connectanum-dart"),
    )
    parser.add_argument(
        "--server-url",
        default=os.environ.get("GITHUB_SERVER_URL", "https://github.com"),
    )
    parser.add_argument("--commit", default=os.environ.get("GITHUB_SHA", "HEAD"))
    parser.add_argument(
        "--workflow-ref",
        default=os.environ.get(
            "GITHUB_WORKFLOW_REF",
            "konsultaner/connectanum-dart/.github/workflows/native-artifacts.yml@refs/tags/unknown",
        ),
    )
    parser.add_argument(
        "--owner",
        default=os.environ.get("GITHUB_REPOSITORY_OWNER", "konsultaner"),
    )
    parser.add_argument("--generated-notes-file")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    print(
        render_release_notes(
            release_tag=args.release_tag,
            repository=args.repository,
            server_url=args.server_url,
            commit_sha=args.commit,
            workflow_ref=args.workflow_ref,
            owner=args.owner,
            generated_notes=_read_optional(args.generated_notes_file),
        ),
        end="",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
