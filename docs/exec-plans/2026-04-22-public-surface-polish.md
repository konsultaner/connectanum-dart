# Exec Plan: public-surface-polish

Status: completed
Owner: Codex
Created: 2026-04-22
Last updated: 2026-04-22

## Goal

Make the project's public-facing artifacts read like a normal user-facing
project instead of an internal build setup: improve release titles/details, the
bundle README inside published native assets, and the top-level repository
README.

## Scope

- In scope:
  - Improve the human-facing title and default body text for GitHub Releases
    created by the native artifact workflow.
  - Rewrite the README embedded in the packaged native bundle so a downloader
    immediately sees what the archive is and how to use it.
  - Restructure the top-level `README.md` so it leads with what the project is,
    how to get started, and where to find releases/artifacts.
- Out of scope:
  - Renaming machine-consumed asset filenames or tag prefixes that current
    tooling depends on.
  - Rewriting package-level READMEs across the whole workspace.
  - Product/API changes unrelated to public presentation.

## Files Expected To Change

- `README.md`
- `.github/workflows/native-artifacts.yml`
- `bin/package-native-artifact`
- `docs/project_state.md`
- `docs/exec-plans/*.md`

## Preconditions

- `bin/test-fast` is green before changing the public-facing files.
- Existing asset filenames such as `ct-ffi-<host-triple>.tar.gz` stay stable so
  the install hooks and downloader paths keep working.

## Plan

1. Check in this active plan and point `docs/project_state.md` at it.
2. Improve the native release workflow's default release title/body text and
   rewrite the archive-internal README for clearer public consumption.
3. Restructure the top-level `README.md`, refresh project state, run
   `bin/verify`, and checkpoint the polish pass.

## Verification

- `bin/test-fast`
- `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/native-artifacts.yml'); puts 'yaml_ok'"`
- `ruby -e 'require "yaml"; wf = YAML.load_file(".github/workflows/native-artifacts.yml"); step = wf.fetch("jobs").values.flat_map { |job| job.fetch("steps", []) }.find { |s| s["name"] == "Create or update GitHub Release" }; abort("step not found") unless step; File.write("/tmp/connectanum-release-step.sh", step.fetch("run"));' && bash -n /tmp/connectanum-release-step.sh && echo shell_ok`
- `bin/verify`

## Decision Log

- 2026-04-22: Keep machine-oriented tag and asset names stable for automation,
  but present human-friendly titles/details in release metadata and docs.
- 2026-04-22: Keep maintainer/Codex workflow guidance in the repo README, but
  move it behind user-facing project and release information instead of leading
  with it.
- 2026-04-22: For `v*` project releases, keep a conventional changelog section
  on reruns by generating notes explicitly instead of relying on create-only
  `gh release --generate-notes` behavior.
