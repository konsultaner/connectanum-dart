import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
AUDIT_SCRIPT = REPO_ROOT / "bin" / "audit-github-deployment-chain"


class AuditGithubDeploymentChainTest(unittest.TestCase):
    def test_clean_latest_ci_requires_checked_out_head(self) -> None:
        current_head = self._git("rev-parse", "HEAD")
        stale_head = self._git("rev-parse", "HEAD~1")

        result = self._run_audit(stale_head)

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("latest CI run does not cover checked-out head", result.stdout)
        self.assertIn("Latest CI cleanliness audit failed.", result.stdout)

        matching_result = self._run_audit(current_head)

        self.assertEqual(matching_result.returncode, 0, matching_result.stdout)
        self.assertIn("Latest CI run covers checked-out head: yes.", matching_result.stdout)
        self.assertIn("Latest CI run is clean", matching_result.stdout)

    def test_clean_latest_ci_logs_requires_checked_out_head(self) -> None:
        current_head = self._git("rev-parse", "HEAD")
        stale_head = self._git("rev-parse", "HEAD~1")

        result = self._run_audit(stale_head, "--require-clean-latest-ci-logs")

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("latest CI logs do not cover checked-out head", result.stdout)
        self.assertIn("Latest CI log-scan audit failed.", result.stdout)

        matching_result = self._run_audit(
            current_head,
            "--require-clean-latest-ci-logs",
        )

        self.assertEqual(matching_result.returncode, 0, matching_result.stdout)
        self.assertIn("Latest CI logs cover checked-out head: yes.", matching_result.stdout)
        self.assertIn("Latest CI log scan is clean", matching_result.stdout)

    def _git(self, *args: str) -> str:
        return subprocess.check_output(
            ["git", *args],
            cwd=REPO_ROOT,
            text=True,
        ).strip()

    def _run_audit(
        self,
        ci_head: str,
        gate: str = "--require-clean-latest-ci",
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            fake_gh = temp_path / "gh"
            fake_curl = temp_path / "curl"

            workflow_paths = "\n".join(
                sorted(
                    str(path.relative_to(REPO_ROOT))
                    for pattern in ("*.yml", "*.yaml")
                    for path in (REPO_ROOT / ".github" / "workflows").glob(pattern)
                )
            )

            fake_gh.write_text(
                textwrap.dedent(
                    """\
                    #!/usr/bin/env python3
                    import os
                    import sys

                    args = sys.argv[1:]
                    repository = "konsultaner/connectanum-dart"
                    ci_head = os.environ["FAKE_CI_HEAD"]
                    workflow_paths = os.environ["FAKE_WORKFLOW_PATHS"].splitlines()


                    def jq_arg():
                        if "--jq" not in args:
                            return ""
                        return args[args.index("--jq") + 1]


                    def print_workflows(jq):
                        if jq == ".workflows[].path":
                            print("\\n".join(workflow_paths))
                        elif jq.startswith(".workflows[] |"):
                            for path in workflow_paths:
                                name = path.rsplit("/", 1)[-1]
                                print(f"- {name}: active ({path})")
                        else:
                            sys.exit(1)


                    if args[:1] == ["api"]:
                        path = args[1] if len(args) > 1 else ""
                        jq = jq_arg()

                        if path == f"repos/{repository}":
                            values = {
                                ".default_branch": "master",
                                ".visibility": "public",
                                ".private": "false",
                                ".allow_auto_merge": "false",
                                ".delete_branch_on_merge": "false",
                            }
                            if jq in values:
                                print(values[jq])
                            else:
                                sys.exit(1)
                        elif path == f"repos/{repository}/branches/add-router":
                            print("false")
                        elif path == f"repos/{repository}/branches/master":
                            print("true")
                        elif path == f"repos/{repository}/branches/master/protection":
                            if "required_status_checks" in jq:
                                print("Fast Checks, Full Verify")
                            else:
                                print("false")
                        elif path == f"repos/{repository}/rulesets":
                            print("0")
                        elif path == f"repos/{repository}/actions/workflows":
                            print_workflows(jq)
                        elif path == "users/konsultaner/packages/container/connectanum-router":
                            print("connectanum-router")
                        elif path == "orgs/konsultaner/packages/container/connectanum-router":
                            print("connectanum-router")
                        else:
                            sys.exit(1)
                    elif args[:2] == ["run", "list"]:
                        if "--workflow" in args:
                            workflow = args[args.index("--workflow") + 1]
                            if workflow == "CI":
                                print("123")
                            else:
                                print("")
                        else:
                            print(f"- CI #123: completed/success @ {ci_head[:7]} (2026-05-19T00:00:00Z)")
                    elif args[:2] == ["run", "view"]:
                        if "--log" in args:
                            print("Fast Checks completed")
                            print("Full Verify completed")
                            sys.exit(0)
                        json_fields = args[args.index("--json") + 1]
                        if json_fields == "status,conclusion,headSha,url":
                            print(f"Run: CI #123 completed/success @ {ci_head[:7]}")
                            print("URL: https://github.example.invalid/runs/123")
                        elif json_fields == "status,conclusion,headSha":
                            print(f"completed\\tsuccess\\t{ci_head}")
                        elif json_fields == "jobs":
                            print("Fast Checks\\tcompleted\\tsuccess")
                            print("Full Verify\\tcompleted\\tsuccess")
                        else:
                            sys.exit(1)
                    elif args[:2] == ["run", "download"]:
                        sys.exit(0)
                    else:
                        sys.exit(1)
                    """
                )
            )
            fake_gh.chmod(0o755)

            fake_curl.write_text(
                textwrap.dedent(
                    """\
                    #!/usr/bin/env bash
                    set -euo pipefail

                    case "$*" in
                      *ghcr.io/token*)
                        printf '{"token":"fake-token"}'
                        ;;
                      *tags/list*)
                        printf '{"name":"konsultaner/connectanum-router","tags":["v0.1.0-rc.1"]}'
                        ;;
                      *manifests/v0.1.0-rc.1*)
                        printf 'HTTP/2 200\\r\\ndocker-content-digest: sha256:abcdef\\r\\n'
                        ;;
                      *)
                        exit 1
                        ;;
                    esac
                    """
                )
            )
            fake_curl.chmod(0o755)

            env = os.environ.copy()
            env["GH_BIN"] = str(fake_gh)
            env["FAKE_CI_HEAD"] = ci_head
            env["FAKE_WORKFLOW_PATHS"] = workflow_paths
            env["PATH"] = f"{temp_dir}{os.pathsep}{env['PATH']}"

            return subprocess.run(
                [
                    str(AUDIT_SCRIPT),
                    "--branch",
                    "add-router",
                    gate,
                ],
                cwd=REPO_ROOT,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )


if __name__ == "__main__":
    unittest.main()
