#!/usr/bin/env python3
"""Guard public artifacts against local downstream references."""

from __future__ import annotations

import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence


REPO_ROOT = Path(__file__).resolve().parents[1]

PUBLIC_ROOT_FILES = {
    "AGENTS.md",
    "README.md",
    "ROADMAP.md",
    "ROADMAP_NEXT.md",
    "STRUCTURE.md",
}
PUBLIC_PREFIXES = (
    ".github/workflows/",
    "docs/",
)
PUBLIC_PACKAGE_SUFFIXES = (
    "/README.md",
    "/CHANGELOG.md",
    "/pubspec.yaml",
)
PUBLIC_PACKAGE_MARKERS = (
    "/example/",
)
PUBLIC_PACKAGE_DART_MARKERS = (
    "/bin/",
    "/lib/",
)
PUBLIC_RELEASE_TEMPLATE_FILES = {
    "bin/audit-github-deployment-chain",
    "bin/common.sh",
    "bin/dart-package-publish-dry-run",
    "tool/render_native_release_notes.py",
    "tool/render_router_image_metadata.py",
}

LOCAL_PATH_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "macOS absolute user path",
        re.compile(r"/Users/[^\s`'\"<>)]+"),
    ),
    (
        "Linux absolute project/workspace path",
        re.compile(
            r"/home/[^/\s]+/(?:Projects|projects|workspace|workspaces|src)/"
            r"[^\s`'\"<>)]+"
        ),
    ),
    (
        "Windows absolute user path",
        re.compile(r"[A-Za-z]:\\Users\\[^\s`'\"<>]+"),
    ),
)


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    column: int
    kind: str
    match: str


def _git_ls_files(repo_root: Path) -> list[str]:
    result = subprocess.run(
        ["git", "ls-files"],
        cwd=repo_root,
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    return [line for line in result.stdout.splitlines() if line]


def is_public_artifact(path: str) -> bool:
    if path in PUBLIC_ROOT_FILES or path in PUBLIC_RELEASE_TEMPLATE_FILES:
        return True
    if path.startswith(PUBLIC_PREFIXES):
        return True
    if not path.startswith("packages/"):
        return False
    return (
        path.endswith(PUBLIC_PACKAGE_SUFFIXES)
        or any(marker in path for marker in PUBLIC_PACKAGE_MARKERS)
        or (
            path.endswith(".dart")
            and any(marker in path for marker in PUBLIC_PACKAGE_DART_MARKERS)
        )
    )


def _line_column(text: str, offset: int) -> tuple[int, int]:
    line = text.count("\n", 0, offset) + 1
    line_start = text.rfind("\n", 0, offset) + 1
    return line, offset - line_start + 1


def _literal_denylist() -> list[str]:
    values = []
    raw_values = os.environ.get("CONNECTANUM_PUBLIC_ARTIFACT_DENYLIST", "")
    values.extend(raw_values.splitlines())

    denylist_file = os.environ.get("CONNECTANUM_PUBLIC_ARTIFACT_DENYLIST_FILE")
    if denylist_file:
        values.extend(Path(denylist_file).read_text(encoding="utf-8").splitlines())

    return [
        value.strip()
        for value in values
        if value.strip() and not value.strip().startswith("#")
    ]


def scan_text(
    path: str,
    text: str,
    *,
    literal_denylist: Sequence[str] = (),
) -> list[Finding]:
    findings: list[Finding] = []
    for kind, pattern in LOCAL_PATH_PATTERNS:
        for match in pattern.finditer(text):
            line, column = _line_column(text, match.start())
            findings.append(
                Finding(path, line, column, kind, match.group(0)),
            )

    for literal in literal_denylist:
        start = 0
        while True:
            offset = text.find(literal, start)
            if offset < 0:
                break
            line, column = _line_column(text, offset)
            findings.append(
                Finding(path, line, column, "configured private reference", literal),
            )
            start = offset + max(len(literal), 1)

    return sorted(findings, key=lambda finding: (finding.line, finding.column))


def scan_public_artifacts(
    repo_root: Path,
    *,
    paths: Iterable[str] | None = None,
    literal_denylist: Sequence[str] | None = None,
) -> list[Finding]:
    denylist = _literal_denylist() if literal_denylist is None else literal_denylist
    tracked_paths = _git_ls_files(repo_root) if paths is None else list(paths)
    findings: list[Finding] = []
    for path in tracked_paths:
        if not is_public_artifact(path):
            continue
        full_path = repo_root / path
        try:
            text = full_path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        findings.extend(scan_text(path, text, literal_denylist=denylist))
    return sorted(findings, key=lambda finding: (finding.path, finding.line))


def main(argv: Sequence[str] | None = None) -> int:
    del argv
    findings = scan_public_artifacts(REPO_ROOT)
    if not findings:
        return 0

    print(
        "Public artifact reference check failed. Use neutral downstream or "
        "consumer application wording and avoid local paths in checked-in "
        "docs, release notes, examples, and package metadata.",
        file=sys.stderr,
    )
    for finding in findings:
        print(
            f"{finding.path}:{finding.line}:{finding.column}: "
            f"{finding.kind}: {finding.match}",
            file=sys.stderr,
        )
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
