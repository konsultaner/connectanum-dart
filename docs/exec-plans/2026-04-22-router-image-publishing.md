# Exec Plan: router-image-publishing

Status: superseded
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-28

Superseded note: the 2026-04-28 GitHub deployment-chain audit found that this
workflow is staged on `add-router` but is not visible from GitHub's default
branch yet, and `ghcr.io/konsultaner/connectanum-router` is not currently a
visible GHCR package. Use
`docs/exec-plans/2026-04-28-github-deployment-chain-readiness.md` as the active
source of truth for router image promotion and validation.

## Goal

Publish multi-arch container images for the router runner so the checked-in
deployment manifests can point at a real hosted image path for both
`linux/amd64` and `linux/arm64`.

## Scope

- In scope:
  - Add a GitHub Actions workflow that builds and publishes the router image to
    GHCR for `linux/amd64` and `linux/arm64`.
  - Add a `.dockerignore` so Docker builds do not ship the repo's local caches,
    build outputs, or VCS metadata as context.
  - Update the Docker/Kubernetes/deployment docs to describe the image publish
    flow and the default GHCR image name/tag contract.
- Out of scope:
  - kTLS benchmarks or transport changes.
  - A separate Helm chart/operator.
  - Windows containers.

## Files Expected To Change

- `.github/workflows/router-image.yml`
- `.dockerignore`
- `deploy/k8s/connectanum-router.yaml`
- `README.md`
- `docs/deployment.md`
- `docs/project_state.md`
- `docs/exec-plans/*.md`
- `ROADMAP_NEXT.md`

## Preconditions

- `bin/test-fast` is green before the workflow/doc changes.
- The existing Dockerfile under `deploy/docker/Dockerfile` remains the build
  source for the published image.
- GHCR publishing can use the repository `GITHUB_TOKEN`; no extra registry
  secret is required.

## Plan

1. Check in this active plan and point `docs/project_state.md` at it.
2. Add a `router-image` workflow that uses Docker Buildx to publish
   `linux/amd64` and `linux/arm64` images to GHCR on `v*` tags and manual
   dispatch, and add a `.dockerignore` for the repo-wide build context.
3. Refresh the deployment templates/docs/state around the published image path,
   run `bin/verify`, and checkpoint the milestone.

## Verification

- `bin/test-fast`
- `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/router-image.yml'); puts 'yaml_ok'"`
- `bin/verify`

## Decision Log

- 2026-04-22: Publish the router image to `ghcr.io/<owner>/connectanum-router`
  rather than overloading the monorepo package name, because the image is a
  deployable router artifact rather than a source bundle.
- 2026-04-22: Keep the first workflow tag contract simple: `v*` tags publish
  versioned and `latest` tags, while manual dispatch can publish an explicit
  one-off tag for validation.

## Handoff

- The branch contains a dedicated `Router Image` workflow that builds
  `ghcr.io/konsultaner/connectanum-router` for `linux/amd64` and `linux/arm64`
  using Docker Buildx, but the workflow still needs default-branch promotion
  and hosted GHCR validation before public docs can call it published.
- Stable `v<major>.<minor>.<patch>` tags publish `<version>`, `<major>.<minor>`,
  `<major>`, and `latest`; prerelease tags publish only the explicit version;
  manual workflow dispatch now defaults to dry-run validation and requires
  explicit tag approval before publishing.
- The repo now has a `.dockerignore` tuned for this monorepo so Docker builds
  do not upload local caches, build outputs, or unrelated docs/deployment files
  as context.
- The Kubernetes manifest and deployment docs now keep the intended GHCR image
  path staged behind a `replace-me` tag until a hosted package is validated.
- Verification that passed for this milestone:
  - `bin/test-fast`
  - `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/router-image.yml'); puts 'yaml_ok'"`
  - local shell validation of the workflow tag-resolution step for stable tag,
    prerelease tag, and manual override cases
  - `bin/verify`
