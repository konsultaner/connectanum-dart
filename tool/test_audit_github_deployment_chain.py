#!/usr/bin/env python3
"""Regression checks for deployment-chain audit sensitivity grouping."""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def run(
    args: list[str],
    *,
    cwd: Path,
    capture_output: bool = False,
    check: bool = True,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=cwd,
        check=check,
        capture_output=capture_output,
        text=True,
        env=env,
    )


def write_file(root: Path, relative_path: str, content: str = "test\n") -> None:
    path = root / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def commit_all(root: Path, message: str) -> None:
    run(["git", "add", "."], cwd=root)
    run(
        [
            "git",
            "-c",
            "commit.gpgsign=false",
            "commit",
            "-q",
            "-m",
            message,
        ],
        cwd=root,
    )


def parse_sections(output: str) -> dict[str, list[str]]:
    sections: dict[str, list[str]] = {}
    current: str | None = None

    for line in output.splitlines():
        if line.startswith("## "):
            current = line[3:]
            sections[current] = []
        elif current is not None and line.startswith("- "):
            sections[current].append(line[2:])

    return sections


def copy_audit_script(root: Path) -> None:
    (root / "bin").mkdir()
    shutil.copy2(ROOT / "bin/common.sh", root / "bin/common.sh")
    shutil.copy2(
        ROOT / "bin/audit-github-deployment-chain",
        root / "bin/audit-github-deployment-chain",
    )


def write_fake_gh(root: Path) -> Path:
    fake_gh = root / "fake-gh.py"
    fake_gh.write_text(
        r'''#!/usr/bin/env python3
import os
import sys

HEAD = os.environ["FAKE_HEAD_SHA"]
NOISE_ENABLED = os.environ.get("FAKE_CI_NOISE", "1") != "0"
REPOSITORY = "konsultaner/connectanum-dart"
RUNS = {
    "201": {
        "id": "201",
        "name": "CI",
        "status": "completed",
        "conclusion": "success",
        "head": HEAD,
        "created": "2026-05-18T10:01:00Z",
    },
    "200": {
        "id": "200",
        "name": "CI",
        "status": "completed",
        "conclusion": "success",
        "head": HEAD,
        "created": "2026-05-18T10:00:00Z",
    },
}


def value_after(args, flag, default=""):
    if flag not in args:
        return default
    index = args.index(flag)
    if index + 1 >= len(args):
        return default
    return args[index + 1]


def api_path(args):
    skip_value_after = {"--jq", "--method", "-F", "--input"}
    index = 0
    while index < len(args):
        arg = args[index]
        if arg in skip_value_after:
            index += 2
            continue
        if arg.startswith("-"):
            index += 1
            continue
        return arg
    return ""


def run_row(run_id):
    run = RUNS[run_id]
    return f"{run['id']}\t{run['head']}\t{run['status']}\t{run['conclusion']}"


args = sys.argv[1:]
if not args:
    sys.exit(1)

if args[0] == "api":
    path = api_path(args[1:])
    jq = value_after(args, "--jq")

    if path == f"repos/{REPOSITORY}":
        values = {
            ".visibility": "public",
            ".private": "false",
            ".default_branch": "master",
            ".allow_auto_merge": "true",
            ".delete_branch_on_merge": "true",
        }
        print(values.get(jq, ""))
        sys.exit(0)

    if path == f"repos/{REPOSITORY}/branches/feature":
        print("false")
        sys.exit(0)

    if path == f"repos/{REPOSITORY}/branches/master":
        print("true")
        sys.exit(0)

    if path == f"repos/{REPOSITORY}/branches/master/protection":
        if "required_status_checks" in jq and "join" in jq:
            print("Fast Checks, Full Verify")
        elif "required_status_checks.strict" in jq:
            print("false")
        elif "required_pull_request_reviews.required_approving_review_count" in jq:
            print("1")
        elif "required_pull_request_reviews.require_code_owner_reviews" in jq:
            print("false")
        elif "enforce_admins" in jq:
            print("false")
        elif "allow_force_pushes" in jq:
            print("false")
        elif "allow_deletions" in jq:
            print("false")
        elif "required_linear_history" in jq:
            print("false")
        elif "required_conversation_resolution" in jq:
            print("false")
        sys.exit(0)

    if path == f"repos/{REPOSITORY}/rulesets":
        print("0")
        sys.exit(0)

    if path == f"repos/{REPOSITORY}/actions/workflows":
        sys.exit(0)

    if path == "users/konsultaner/packages/container/connectanum-router":
        print("connectanum-router")
        sys.exit(0)

    if f"repos/{REPOSITORY}/actions/runs/" in path and path.endswith("/jobs?per_page=100"):
        run_id = path.split("/actions/runs/", 1)[1].split("/", 1)[0]
        print(f"Fast Checks\t{run_id}1")
        print(f"Full Verify\t{run_id}2")
        sys.exit(0)

    if f"repos/{REPOSITORY}/check-runs/" in path and path.endswith("/annotations?per_page=100"):
        job_id = path.split("/check-runs/", 1)[1].split("/", 1)[0]
        if NOISE_ENABLED and job_id == "2001":
            print("warning\tpackages/connectanum_client/test/browser_test.dart\t42\tbrowser retry emitted a warning")
        sys.exit(0)

    sys.exit(1)

if args[0:2] == ["pr", "list"]:
    sys.exit(0)

if args[0:2] == ["run", "list"]:
    jq = value_after(args, "--jq")
    if "--workflow" in args and "--limit" in args and value_after(args, "--limit") == "1":
        print("201")
        sys.exit(0)

    if "select(.name == \"CI\")" in jq or "databaseId,headSha,status,conclusion" in " ".join(args):
        print(run_row("201"))
        print(run_row("200"))
        sys.exit(0)

    print(f"- CI #201: completed/success @ {HEAD[:7]} (2026-05-18T10:01:00Z)")
    print(f"- CI #200: completed/success @ {HEAD[:7]} (2026-05-18T10:00:00Z)")
    sys.exit(0)

if args[0:2] == ["run", "view"]:
    run_id = args[2]
    run = RUNS[run_id]
    jq = value_after(args, "--jq")

    if "--log" in args:
        if NOISE_ENABLED and run_id == "200":
            print("warning: browser manager startup flake")
        else:
            print("tests clean")
        sys.exit(0)

    if ".headSha, .status" in jq:
        print(f"{run['head']}\t{run['status']}\t{run['conclusion']}")
    elif ".status, (.conclusion" in jq:
        print(f"{run['status']}\t{run['conclusion']}")
    elif ".jobs[]" in jq:
        print("Fast Checks\tcompleted\tsuccess")
        print("Full Verify\tcompleted\tsuccess")
    elif "Run: CI" in jq:
        print(f"Run: CI #{run_id} {run['status']}/{run['conclusion']} @ {run['head'][:7]}")
        print(f"URL: https://example.invalid/runs/{run_id}")
    else:
        print("")
    sys.exit(0)

sys.exit(1)
''',
        encoding="utf-8",
    )
    fake_gh.chmod(0o755)
    return fake_gh


class DeploymentAuditSensitivityTest(unittest.TestCase):
    def test_local_diagnostic_groups_runtime_inputs_without_github_api(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            copy_audit_script(root)

            run(["git", "init", "-q"], cwd=root)
            run(["git", "config", "user.name", "Connectanum Test"], cwd=root)
            run(["git", "config", "user.email", "test@example.invalid"], cwd=root)
            commit_all(root, "baseline")
            base = run(
                ["git", "rev-parse", "HEAD"],
                cwd=root,
                capture_output=True,
            ).stdout.strip()

            changed_paths = (
                ".github/workflows/wamp-profile-benchmarks.yml",
                "docs/exec-plans/2026-05-17-audit-runtime-sensitivity.md",
                "native/transport/ct_core/src/lib.rs",
                "packages/connectanum_router/lib/src/router/router_instance.dart",
                "packages/connectanum_router/test/router_runtime_test.dart",
            )
            for path in changed_paths:
                write_file(root, path)
            commit_all(root, "change deployment-sensitive paths")

            result = run(
                [
                    "bash",
                    "bin/audit-github-deployment-chain",
                    "--show-sensitive-changes-since",
                    base,
                ],
                cwd=root,
                capture_output=True,
            )
            sections = parse_sections(result.stdout)

            self.assertEqual(
                set(sections["Dart Package Publish Dry Run"]),
                {
                    "packages/connectanum_router/lib/src/router/router_instance.dart",
                    "packages/connectanum_router/test/router_runtime_test.dart",
                },
            )
            self.assertEqual(
                set(sections["Native Artifacts"]),
                {"native/transport/ct_core/src/lib.rs"},
            )
            self.assertEqual(
                set(sections["Router Image"]),
                {
                    "native/transport/ct_core/src/lib.rs",
                    "packages/connectanum_router/lib/src/router/router_instance.dart",
                },
            )
            self.assertEqual(
                set(sections["WAMP Profile Benchmarks"]),
                {
                    ".github/workflows/wamp-profile-benchmarks.yml",
                    "native/transport/ct_core/src/lib.rs",
                    "packages/connectanum_router/lib/src/router/router_instance.dart",
                },
            )
            self.assertEqual(
                set(sections["RC Readiness"]),
                {
                    ".github/workflows/wamp-profile-benchmarks.yml",
                    "native/transport/ct_core/src/lib.rs",
                    "packages/connectanum_router/lib/src/router/router_instance.dart",
                    "packages/connectanum_router/test/router_runtime_test.dart",
                },
            )

    def test_ci_log_scan_checks_all_branch_ci_runs_for_checked_out_head(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            copy_audit_script(root)
            fake_gh = write_fake_gh(root)

            run(["git", "init", "-q"], cwd=root)
            run(["git", "config", "user.name", "Connectanum Test"], cwd=root)
            run(["git", "config", "user.email", "test@example.invalid"], cwd=root)
            write_file(root, "README.md")
            commit_all(root, "baseline")
            run(["git", "checkout", "-q", "-b", "feature"], cwd=root)
            head_sha = run(
                ["git", "rev-parse", "HEAD"],
                cwd=root,
                capture_output=True,
            ).stdout.strip()
            env = {
                **os.environ,
                "GH_BIN": str(fake_gh),
                "FAKE_HEAD_SHA": head_sha,
            }

            result = run(
                [
                    "bash",
                    "bin/audit-github-deployment-chain",
                    "--repository",
                    "konsultaner/connectanum-dart",
                    "--branch",
                    "feature",
                    "--require-clean-latest-ci-logs",
                ],
                cwd=root,
                capture_output=True,
                check=False,
                env=env,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn(
                "Checked-out head CI log scan covers 2 run(s)",
                result.stdout,
            )
            self.assertIn("Run: CI #201 completed/success", result.stdout)
            self.assertIn("Run: CI #200 completed/success", result.stdout)
            self.assertIn(
                "Potential hosted CI run #200 log issues matching:",
                result.stdout,
            )
            self.assertIn(
                "Potential hosted CI run #200 warning/error annotations:",
                result.stdout,
            )
            self.assertIn("Latest CI log-scan audit failed.", result.stderr)

            clean_result = run(
                [
                    "bash",
                    "bin/audit-github-deployment-chain",
                    "--repository",
                    "konsultaner/connectanum-dart",
                    "--branch",
                    "feature",
                    "--require-clean-latest-ci-logs",
                ],
                cwd=root,
                capture_output=True,
                check=False,
                env={**env, "FAKE_CI_NOISE": "0"},
            )

            self.assertEqual(clean_result.returncode, 0, clean_result.stderr)
            self.assertIn(
                "Checked-out head CI log scan covers 2 run(s)",
                clean_result.stdout,
            )


if __name__ == "__main__":
    unittest.main()
