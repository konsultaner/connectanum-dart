import os
import shutil
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
        stale_head = self._different_sha(current_head)

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
        stale_head = self._different_sha(current_head)

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

    def test_rc_readiness_accepts_native_prerelease_evidence(self) -> None:
        current_head = self._git("rev-parse", "HEAD")

        result = self._run_rc_readiness_with_native_prerelease(current_head)

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(
            "Native release prerelease intent: accepted (v0.1.0-rc.2, project).",
            result.stdout,
        )
        self.assertIn(
            "Native GitHub prerelease assets: ready (30 assets).",
            result.stdout,
        )
        self.assertIn(
            "Latest Native Artifacts prerelease publish is clean and relevant.",
            result.stdout,
        )
        self.assertIn("Native release hosted evidence gate: ready", result.stdout)
        self.assertIn("RC tag on checked-out head: ready", result.stdout)
        self.assertIn("GitHub RC prerelease: ready (v0.1.0-rc.2)", result.stdout)

    def test_rc_readiness_suggests_followup_rc_tag_for_stale_tags(self) -> None:
        current_head = self._git("rev-parse", "HEAD")
        stale_head = self._different_sha(current_head)

        result = self._run_rc_readiness_with_stale_rc_tags(
            current_head,
            stale_head,
        )

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(
            "Native release dry-run intent: accepted "
            "(v0.1.0-rc-validation-dry-run, project).",
            result.stdout,
        )
        self.assertIn("Native release hosted evidence gate: ready", result.stdout)
        self.assertIn(
            "Audited branch role: ready (default branch master)",
            result.stdout,
        )
        self.assertIn("RC tag on checked-out head: not ready", result.stdout)
        self.assertIn("Existing GitHub RC tags:", result.stdout)
        self.assertIn(
            f"- v0.1.0-rc.1 -> {stale_head[:7]} (stale for checked-out head)",
            result.stdout,
        )
        self.assertIn(
            f"- v0.1.0-rc-validation-dry-run -> {current_head[:7]} (current)",
            result.stdout,
        )
        self.assertIn("Suggested follow-up RC tag(s):", result.stdout)
        self.assertIn(
            "- v0.1.0-rc.2 (next numeric tag after v0.1.0-rc.1; "
            "requires release approval before pushing)",
            result.stdout,
        )
        self.assertEqual(
            result.stdout.count(
                "- v0.1.0-rc.2 (next numeric tag after v0.1.0-rc.1; "
                "requires release approval before pushing)"
            ),
            1,
            result.stdout,
        )
        self.assertNotIn(
            "- v0.1.0-rc-validation-dry-run (next numeric",
            result.stdout,
        )
        self.assertIn(
            "GitHub RC prerelease: not ready; no RC tag selected.",
            result.stdout,
        )

    def test_rc_readiness_suppresses_followup_tag_when_branch_differs(self) -> None:
        current_head = self._git("rev-parse", "HEAD")
        stale_head = self._different_sha(current_head)

        result = self._run_rc_readiness_with_stale_rc_tags(
            current_head,
            stale_head,
            branch_head=stale_head,
            branch="add-router",
        )

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(
            f"Audited branch head: {stale_head[:7]} (add-router)",
            result.stdout,
        )
        self.assertIn(
            "Branch/head alignment: not ready; audited branch add-router "
            f"points at {stale_head[:7]} while the checkout is {current_head[:7]}.",
            result.stdout,
        )
        self.assertIn(
            "Suggested follow-up RC tag(s): not evaluated until audited branch "
            "head and checked-out head match.",
            result.stdout,
        )
        self.assertNotIn(
            "- v0.1.0-rc.2 (next numeric tag after v0.1.0-rc.1; "
            "requires release approval before pushing)",
            result.stdout,
        )

    def test_rc_readiness_suppresses_followup_tag_for_non_default_branch(
        self,
    ) -> None:
        current_head = self._git("rev-parse", "HEAD")
        stale_head = self._different_sha(current_head)

        result = self._run_rc_readiness_with_stale_rc_tags(
            current_head,
            stale_head,
            branch="add-router",
        )

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("Branch/head alignment: ready", result.stdout)
        self.assertIn(
            "Audited branch role: not ready; RC releases must be audited from "
            "default branch master, but audited branch is add-router.",
            result.stdout,
        )
        self.assertIn(
            "Suggested follow-up RC tag(s): not evaluated until the audited "
            "branch is the default release branch.",
            result.stdout,
        )
        self.assertNotIn(
            "- v0.1.0-rc.2 (next numeric tag after v0.1.0-rc.1; "
            "requires release approval before pushing)",
            result.stdout,
        )

    def _git(self, *args: str) -> str:
        return subprocess.check_output(
            ["git", *args],
            cwd=REPO_ROOT,
            text=True,
        ).strip()

    def _different_sha(self, sha: str) -> str:
        replacement = "0" if sha[0] != "0" else "1"
        return f"{replacement}{sha[1:]}"

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
                    branch_head = os.environ.get("FAKE_BRANCH_HEAD", ci_head)
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
                        if path == "--paginate" and len(args) > 2:
                            path = args[2]
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
                            if jq == ".protected":
                                print("false")
                            elif jq == ".commit.sha // empty":
                                print(branch_head)
                            else:
                                sys.exit(1)
                        elif path == f"repos/{repository}/branches/master":
                            if jq == ".protected":
                                print("true")
                            elif jq == ".commit.sha // empty":
                                print(branch_head)
                            else:
                                sys.exit(1)
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
            env["FAKE_BRANCH_HEAD"] = ci_head
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

    def _run_rc_readiness_with_native_prerelease(
        self,
        ci_head: str,
        branch_head: str | None = None,
        branch: str = "master",
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            fake_gh = temp_path / "gh"
            fake_git = temp_path / "git"
            fake_curl = temp_path / "curl"
            real_git = shutil.which("git")
            self.assertIsNotNone(real_git)

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
                    branch_head = os.environ.get("FAKE_BRANCH_HEAD", ci_head)
                    workflow_paths = os.environ["FAKE_WORKFLOW_PATHS"].splitlines()


                    def value_after(name):
                        return args[args.index(name) + 1] if name in args else ""


                    def jq_arg():
                        return value_after("--jq")


                    def json_arg():
                        return value_after("--json")


                    def print_workflows(jq):
                        if jq == ".workflows[].path":
                            print("\\n".join(workflow_paths))
                        elif jq.startswith(".workflows[] |"):
                            for path in workflow_paths:
                                name = path.rsplit("/", 1)[-1]
                                print(f"- {name}: active ({path})")
                        else:
                            sys.exit(1)


                    workflow_ids = {
                        "CI": "123",
                        "Dart Package Publish Dry Run": "124",
                        "Native Artifacts": "125",
                        "Router Image": "126",
                    }


                    if args[:1] == ["api"]:
                        path = args[1] if len(args) > 1 else ""
                        if path == "--paginate" and len(args) > 2:
                            path = args[2]
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
                            if jq == ".protected":
                                print("false")
                            elif jq == ".commit.sha // empty":
                                print(branch_head)
                            else:
                                sys.exit(1)
                        elif path == f"repos/{repository}/branches/master":
                            if jq == ".protected":
                                print("true")
                            elif jq == ".commit.sha // empty":
                                print(branch_head)
                            else:
                                sys.exit(1)
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
                        elif path.startswith(f"repos/{repository}/check-runs/"):
                            print("")
                        else:
                            sys.exit(1)
                    elif args[:2] == ["run", "list"]:
                        if "--workflow" in args:
                            print(workflow_ids.get(value_after("--workflow"), ""))
                        else:
                            print(f"- CI #123: completed/success @ {ci_head[:7]} (2026-05-19T00:00:00Z)")
                    elif args[:2] == ["run", "view"]:
                        run_id = args[2] if len(args) > 2 else ""
                        json_fields = json_arg()
                        jq = jq_arg()

                        if "--log" in args:
                            if run_id == "125":
                                print("Release intent accepted: v0.1.0-rc.2 (project, prerelease).")
                            else:
                                print("Fast Checks completed")
                                print("Full Verify completed")
                            sys.exit(0)

                        if json_fields == "status,conclusion,headSha,url,displayTitle,event":
                            titles = {
                                "124": "Dart Package Publish Dry Run",
                                "125": "Native Artifacts",
                                "126": "Router Image",
                            }
                            events = {
                                "124": "workflow_dispatch",
                                "125": "workflow_dispatch",
                                "126": "workflow_dispatch",
                            }
                            print(f"Run: {titles[run_id]} #{run_id} completed/success @ {ci_head[:7]}")
                            print(f"Title: {titles[run_id]}")
                            print(f"Event: {events[run_id]}")
                            print(f"URL: https://github.example.invalid/runs/{run_id}")
                        elif json_fields == "status,conclusion,headSha,url":
                            print(f"Run: CI #123 completed/success @ {ci_head[:7]}")
                            print("URL: https://github.example.invalid/runs/123")
                        elif json_fields == "status,conclusion,headSha,event":
                            print(f"completed\\tsuccess\\t{ci_head}\\tworkflow_dispatch")
                        elif json_fields == "status,conclusion,headSha":
                            print(f"completed\\tsuccess\\t{ci_head}")
                        elif json_fields == "event,jobs":
                            print("workflow_dispatch\\tskipped")
                        elif json_fields == "jobs" and ".databaseId" in jq:
                            print("1261\\tPublish Router Image")
                        elif json_fields == "jobs" and ".steps[]" in jq:
                            print("Resolve image metadata\\tcompleted\\tsuccess")
                            print("Upload router image preview\\tcompleted\\tsuccess")
                            print("Log in to GHCR\\tcompleted\\tskipped")
                            print("Build or publish multi-arch router image\\tcompleted\\tsuccess")
                        elif json_fields == "jobs":
                            if run_id == "123":
                                print("Fast Checks\\tcompleted\\tsuccess")
                                print("Full Verify\\tcompleted\\tsuccess")
                            elif run_id == "124":
                                print("Publish Dry Run\\tcompleted\\tsuccess")
                            elif run_id == "125":
                                print("ct_ffi (Linux x64)\\tcompleted\\tsuccess")
                                print("ct_ffi (Linux arm64)\\tcompleted\\tsuccess")
                                print("ct_ffi (macOS Apple Silicon)\\tcompleted\\tsuccess")
                                print("ct_ffi (macOS Intel)\\tcompleted\\tsuccess")
                                print("ct_ffi (Windows x64)\\tcompleted\\tsuccess")
                                print("Publish GitHub Release\\tcompleted\\tsuccess")
                            elif run_id == "126":
                                print("Publish Router Image\\tcompleted\\tsuccess")
                            else:
                                sys.exit(1)
                        else:
                            sys.exit(1)
                    elif args[:2] == ["release", "view"]:
                        tag = args[2] if len(args) > 2 else ""
                        json_fields = json_arg()

                        if tag != "v0.1.0-rc.2":
                            sys.exit(1)

                        if json_fields == "isPrerelease,isDraft,targetCommitish,assets":
                            print(f"true\\tfalse\\t{ci_head}\\t30")
                        elif json_fields == "tagName,isPrerelease,isDraft":
                            print("v0.1.0-rc.2\\ttrue\\tfalse")
                        else:
                            print("v0.1.0-rc.2")
                    elif args[:2] == ["run", "download"]:
                        sys.exit(0)
                    else:
                        sys.exit(1)
                    """
                )
            )
            fake_gh.chmod(0o755)

            fake_git.write_text(
                textwrap.dedent(
                    """\
                    #!/usr/bin/env bash
                    set -euo pipefail

                    if [[ "${1:-}" == "ls-remote" && "${2:-}" == "--tags" ]]; then
                      printf '%s\\trefs/tags/v0.1.0-rc.2\\n' "$FAKE_CI_HEAD"
                      exit 0
                    fi

                    exec "$REAL_GIT" "$@"
                    """
                )
            )
            fake_git.chmod(0o755)

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
                        printf '{"name":"konsultaner/connectanum-router","tags":["v0.1.0-rc.2"]}'
                        ;;
                      *manifests/v0.1.0-rc.2*)
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
            env["FAKE_BRANCH_HEAD"] = branch_head or ci_head
            env["FAKE_WORKFLOW_PATHS"] = workflow_paths
            env["REAL_GIT"] = real_git or "git"
            env["PATH"] = f"{temp_dir}{os.pathsep}{env['PATH']}"

            return subprocess.run(
                [
                    str(AUDIT_SCRIPT),
                    "--branch",
                    branch,
                    "--show-rc-readiness",
                ],
                cwd=REPO_ROOT,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )

    def _run_rc_readiness_with_stale_rc_tags(
        self,
        ci_head: str,
        stale_head: str,
        branch_head: str | None = None,
        branch: str = "master",
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            fake_gh = temp_path / "gh"
            fake_git = temp_path / "git"
            fake_curl = temp_path / "curl"
            real_git = shutil.which("git")
            self.assertIsNotNone(real_git)

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
                    branch_head = os.environ.get("FAKE_BRANCH_HEAD", ci_head)
                    workflow_paths = os.environ["FAKE_WORKFLOW_PATHS"].splitlines()


                    def value_after(name):
                        return args[args.index(name) + 1] if name in args else ""


                    def jq_arg():
                        return value_after("--jq")


                    def json_arg():
                        return value_after("--json")


                    def print_workflows(jq):
                        if jq == ".workflows[].path":
                            print("\\n".join(workflow_paths))
                        elif jq.startswith(".workflows[] |"):
                            for path in workflow_paths:
                                name = path.rsplit("/", 1)[-1]
                                print(f"- {name}: active ({path})")
                        else:
                            sys.exit(1)


                    workflow_ids = {
                        "CI": "123",
                        "Dart Package Publish Dry Run": "124",
                        "Native Artifacts": "125",
                        "Router Image": "126",
                    }


                    if args[:1] == ["api"]:
                        path = args[1] if len(args) > 1 else ""
                        if path == "--paginate" and len(args) > 2:
                            path = args[2]
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
                            if jq == ".protected":
                                print("false")
                            elif jq == ".commit.sha // empty":
                                print(branch_head)
                            else:
                                sys.exit(1)
                        elif path == f"repos/{repository}/branches/master":
                            if jq == ".protected":
                                print("true")
                            elif jq == ".commit.sha // empty":
                                print(branch_head)
                            else:
                                sys.exit(1)
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
                        elif path.startswith(f"repos/{repository}/check-runs/"):
                            print("")
                        else:
                            sys.exit(1)
                    elif args[:2] == ["run", "list"]:
                        if "--workflow" in args:
                            print(workflow_ids.get(value_after("--workflow"), ""))
                        else:
                            print(f"- CI #123: completed/success @ {ci_head[:7]} (2026-05-19T00:00:00Z)")
                    elif args[:2] == ["run", "view"]:
                        run_id = args[2] if len(args) > 2 else ""
                        json_fields = json_arg()
                        jq = jq_arg()

                        if "--log" in args:
                            if run_id == "125":
                                print("Release intent accepted: v0.1.0-rc-validation-dry-run (project, dry-run).")
                                print("Artifact native-release-preview has been successfully uploaded!")
                            else:
                                print("Fast Checks completed")
                                print("Full Verify completed")
                            sys.exit(0)

                        if json_fields == "status,conclusion,headSha,url,displayTitle,event":
                            titles = {
                                "124": "Dart Package Publish Dry Run",
                                "125": "Native Artifacts",
                                "126": "Router Image",
                            }
                            events = {
                                "124": "workflow_dispatch",
                                "125": "workflow_dispatch",
                                "126": "workflow_dispatch",
                            }
                            print(f"Run: {titles[run_id]} #{run_id} completed/success @ {ci_head[:7]}")
                            print(f"Title: {titles[run_id]}")
                            print(f"Event: {events[run_id]}")
                            print(f"URL: https://github.example.invalid/runs/{run_id}")
                        elif json_fields == "status,conclusion,headSha,url":
                            print(f"Run: CI #123 completed/success @ {ci_head[:7]}")
                            print("URL: https://github.example.invalid/runs/123")
                        elif json_fields == "status,conclusion,headSha,event":
                            print(f"completed\\tsuccess\\t{ci_head}\\tworkflow_dispatch")
                        elif json_fields == "status,conclusion,headSha":
                            print(f"completed\\tsuccess\\t{ci_head}")
                        elif json_fields == "event,jobs":
                            print("workflow_dispatch\\tskipped")
                        elif json_fields == "jobs" and ".databaseId" in jq:
                            print("1261\\tPublish Router Image")
                        elif json_fields == "jobs" and ".steps[]" in jq:
                            print("Resolve image metadata\\tcompleted\\tsuccess")
                            print("Upload router image preview\\tcompleted\\tsuccess")
                            print("Log in to GHCR\\tcompleted\\tskipped")
                            print("Build or publish multi-arch router image\\tcompleted\\tsuccess")
                        elif json_fields == "jobs":
                            if run_id == "123":
                                print("Fast Checks\\tcompleted\\tsuccess")
                                print("Full Verify\\tcompleted\\tsuccess")
                            elif run_id == "124":
                                print("Publish Dry Run\\tcompleted\\tsuccess")
                            elif run_id == "125":
                                print("ct_ffi (Linux x64)\\tcompleted\\tsuccess")
                                print("ct_ffi (Linux arm64)\\tcompleted\\tsuccess")
                                print("ct_ffi (macOS Apple Silicon)\\tcompleted\\tsuccess")
                                print("ct_ffi (macOS Intel)\\tcompleted\\tsuccess")
                                print("ct_ffi (Windows x64)\\tcompleted\\tsuccess")
                                print("Publish GitHub Release\\tcompleted\\tsuccess")
                            elif run_id == "126":
                                print("Publish Router Image\\tcompleted\\tsuccess")
                            else:
                                sys.exit(1)
                        else:
                            sys.exit(1)
                    elif args[:2] == ["release", "view"]:
                        sys.exit(1)
                    elif args[:2] == ["run", "download"]:
                        sys.exit(0)
                    else:
                        sys.exit(1)
                    """
                )
            )
            fake_gh.chmod(0o755)

            fake_git.write_text(
                textwrap.dedent(
                    """\
                    #!/usr/bin/env bash
                    set -euo pipefail

                    if [[ "${1:-}" == "ls-remote" && "${2:-}" == "--tags" ]]; then
                      printf '%s\\trefs/tags/v0.1.0-rc.1\\n' "$FAKE_STALE_HEAD"
                      printf '%s\\trefs/tags/v0.1.0-rc-validation-dry-run\\n' "$FAKE_CI_HEAD"
                      exit 0
                    fi

                    if [[ "${1:-}" == "tag" && "${2:-}" == "--points-at" ]]; then
                      exit 0
                    fi

                    if [[ "${1:-}" == "tag" && "${2:-}" == "--list" ]]; then
                      printf 'v0.1.0-rc.1\\n'
                      printf 'v0.1.0-rc-validation-dry-run\\n'
                      exit 0
                    fi

                    if [[ "${1:-}" == "rev-list" && "${2:-}" == "-n" && "${3:-}" == "1" ]]; then
                      if [[ "${4:-}" == "v0.1.0-rc.1" ]]; then
                        printf '%s\\n' "$FAKE_STALE_HEAD"
                        exit 0
                      fi
                      if [[ "${4:-}" == "v0.1.0-rc-validation-dry-run" ]]; then
                        printf '%s\\n' "$FAKE_CI_HEAD"
                        exit 0
                      fi
                    fi

                    exec "$REAL_GIT" "$@"
                    """
                )
            )
            fake_git.chmod(0o755)

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
                        printf '{"name":"konsultaner/connectanum-router","tags":["v0.1.0-rc.1","v0.1.0-rc-validation-dry-run"]}'
                        ;;
                      *manifests/v0.1.0-rc.1*)
                        printf 'HTTP/2 200\\r\\ndocker-content-digest: sha256:abcdef\\r\\n'
                        ;;
                      *manifests/v0.1.0-rc-validation-dry-run*)
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
            env["FAKE_STALE_HEAD"] = stale_head
            env["FAKE_BRANCH_HEAD"] = branch_head or ci_head
            env["FAKE_WORKFLOW_PATHS"] = workflow_paths
            env["REAL_GIT"] = real_git or "git"
            env["PATH"] = f"{temp_dir}{os.pathsep}{env['PATH']}"

            return subprocess.run(
                [
                    str(AUDIT_SCRIPT),
                    "--branch",
                    branch,
                    "--require-rc-ready",
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
