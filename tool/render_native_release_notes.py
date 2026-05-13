#!/usr/bin/env python3
"""Render human-readable GitHub Release notes for native ct_ffi bundles."""

from __future__ import annotations

import argparse
import os
from pathlib import Path


PLATFORMS = (
    ("Linux x64", "x86_64-unknown-linux-gnu"),
    ("Linux arm64", "aarch64-unknown-linux-gnu"),
    ("macOS arm64", "aarch64-apple-darwin"),
    ("macOS Intel", "x86_64-apple-darwin"),
    ("Windows x64", "x86_64-pc-windows-msvc"),
)


def _release_summary(release_tag: str) -> str:
    if release_tag.startswith("ct-ffi-v"):
        return (
            "This release publishes the standalone native transport bundles "
            "used by the Connectanum router and native client transports."
        )
    return (
        "This release publishes the current prebuilt native transport "
        "bundles for Connectanum."
    )


def _repo_url(server_url: str, repository: str) -> str:
    return f"{server_url.rstrip('/')}/{repository}"


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

    notes = f"""## What this release includes

{_release_summary(release_tag)}

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

## Verification

- GitHub attestation:
  `gh attestation verify path/to/ct-ffi-<host-triple>.tar.gz -R {repository}`
- Detached Sigstore bundle:
  `cosign verify-blob path/to/ct-ffi-<host-triple>.tar.gz --bundle path/to/ct-ffi-<host-triple>.tar.gz.sigstore.json --certificate-identity {workflow_identity} --certificate-oidc-issuer https://token.actions.githubusercontent.com`

## Related links

- Repository README: {repo_url}/blob/{commit_sha}/README.md
- Deployment guide: {repo_url}/blob/{commit_sha}/docs/deployment.md
- Router container image target: `ghcr.io/{owner.lower()}/connectanum-router`
  (released separately; confirm package availability in the deployment guide
  before using it in production)
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
