from __future__ import annotations

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

    def test_branch_protection_reports_pr_requirement_and_admin_bypass(
        self,
    ) -> None:
        current_head = self._git("rev-parse", "HEAD")

        result = self._run_audit(current_head, branch="master")

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("Require pull requests: true", result.stdout)
        self.assertIn("Required approving reviews: 1", result.stdout)
        self.assertIn("Enforce admins: false", result.stdout)
        self.assertIn("Admin bypass allowed: true", result.stdout)

    def test_github_actions_status_reports_degraded_component(self) -> None:
        current_head = self._git("rev-parse", "HEAD")

        result = self._run_audit(
            current_head,
            github_actions_status="degraded_performance",
        )

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("## GitHub Actions Service Status", result.stdout)
        self.assertIn(
            "GitHub Actions component: degraded_performance",
            result.stdout,
        )
        self.assertIn(
            "GitHub Actions incident: Incident with Actions and Pages "
            "(investigating)",
            result.stdout,
        )

    def test_wamp_profile_benchmarks_accepts_stale_run_when_inputs_unchanged(
        self,
    ) -> None:
        current_head = self._git("rev-parse", "HEAD")
        benchmark_head = self._different_sha(current_head)

        result = self._run_wamp_profile_benchmark_audit(
            current_head,
            benchmark_head,
        )

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(
            "WAMP Profile Benchmarks run covers checked-out WAMP profile inputs: "
            "yes",
            result.stdout,
        )
        self.assertIn(
            "Latest WAMP Profile Benchmarks run is clean and relevant.",
            result.stdout,
        )

    def test_wamp_profile_benchmarks_rejects_stale_run_when_inputs_changed(
        self,
    ) -> None:
        current_head = self._git("rev-parse", "HEAD")
        benchmark_head = self._different_sha(current_head)

        result = self._run_wamp_profile_benchmark_audit(
            current_head,
            benchmark_head,
            changed_paths="packages/connectanum_client/lib/connectanum_client.dart\n",
        )

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(
            "Finding: checked-out head has WAMP profile benchmark-sensitive "
            "changes after benchmark head",
            result.stdout,
        )
        self.assertIn(
            "- packages/connectanum_client/lib/connectanum_client.dart",
            result.stdout,
        )
        self.assertIn("WAMP Profile Benchmarks audit failed.", result.stdout)

    def test_router_image_accepts_stale_run_when_mcp_tests_changed(self) -> None:
        current_head = self._git("rev-parse", "HEAD")
        router_image_head = self._different_sha(current_head)

        result = self._run_router_image_audit(
            current_head,
            router_image_head,
            changed_paths="packages/connectanum_mcp/test/io_client_export_test.dart\n",
        )

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(
            "Router Image dry-run covers checked-out router image inputs: yes",
            result.stdout,
        )
        self.assertIn(
            "Latest Router Image dry-run is clean and relevant.",
            result.stdout,
        )
        self.assertNotIn(
            "router-image-sensitive changes after dry-run head",
            result.stdout,
        )

    def test_router_image_rejects_stale_run_when_mcp_runtime_changed(self) -> None:
        current_head = self._git("rev-parse", "HEAD")
        router_image_head = self._different_sha(current_head)

        result = self._run_router_image_audit(
            current_head,
            router_image_head,
            changed_paths="packages/connectanum_mcp/lib/connectanum_mcp_io.dart\n",
        )

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(
            "Finding: checked-out head has router-image-sensitive changes "
            "after dry-run head",
            result.stdout,
        )
        self.assertIn(
            "- packages/connectanum_mcp/lib/connectanum_mcp_io.dart",
            result.stdout,
        )
        self.assertIn("Router image dry-run audit failed.", result.stdout)

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
        self.assertIn("Dart package strict publish dry-run: ready", result.stdout)
        self.assertNotIn(
            "Dart package strict publish dry-run: deferred for first GitHub RC",
            result.stdout,
        )
        self.assertIn(
            "Latest Native Artifacts prerelease publish is clean and relevant.",
            result.stdout,
        )
        self.assertIn("Native release hosted evidence gate: ready", result.stdout)
        self.assertIn("WAMP profile benchmark gate: ready", result.stdout)
        self.assertIn("RC tag on checked-out head: ready", result.stdout)
        self.assertIn(
            "Native release prerelease tag: ready (v0.1.0-rc.2)",
            result.stdout,
        )
        self.assertIn("GitHub RC prerelease: ready (v0.1.0-rc.2)", result.stdout)
        self.assertIn(
            "Router image RC tag: ready (0.1.0-rc.2, sha256:abcdef)",
            result.stdout,
        )

    def test_rc_readiness_rejects_native_prerelease_tag_mismatch(self) -> None:
        current_head = self._git("rev-parse", "HEAD")

        result = self._run_rc_readiness_with_native_prerelease(
            current_head,
            native_release_tag="v0.1.0-rc.1",
            require_rc_ready=True,
        )

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(
            "Native release prerelease intent: accepted (v0.1.0-rc.1, project).",
            result.stdout,
        )
        self.assertIn(
            "Native release prerelease tag: not ready; latest accepted native "
            "prerelease is v0.1.0-rc.1, selected RC tag is v0.1.0-rc.2.",
            result.stdout,
        )
        self.assertIn("GitHub RC prerelease: ready (v0.1.0-rc.2)", result.stdout)
        self.assertIn(
            "Router image RC tag: ready (0.1.0-rc.2, sha256:abcdef)",
            result.stdout,
        )
        self.assertIn("Release candidate readiness audit failed.", result.stdout)

    def test_rc_readiness_rejects_native_dry_run_for_selected_rc_tag(
        self,
    ) -> None:
        current_head = self._git("rev-parse", "HEAD")

        result = self._run_rc_readiness_with_native_prerelease(
            current_head,
            native_release_tag="v0.1.0-rc-validation-dry-run",
            native_release_mode="dry-run",
            require_rc_ready=True,
        )

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(
            "Native release dry-run intent: accepted "
            "(v0.1.0-rc-validation-dry-run, project).",
            result.stdout,
        )
        self.assertIn("Native release hosted evidence gate: ready", result.stdout)
        self.assertIn(
            "Native release prerelease tag: not ready; selected RC tag "
            "v0.1.0-rc.2 still needs Native Artifacts prerelease evidence.",
            result.stdout,
        )
        self.assertIn("GitHub RC prerelease: ready (v0.1.0-rc.2)", result.stdout)
        self.assertIn(
            "Router image RC tag: ready (0.1.0-rc.2, sha256:abcdef)",
            result.stdout,
        )
        self.assertIn("Release candidate readiness audit failed.", result.stdout)

    def test_rc_readiness_rejects_unexpected_strict_dart_blocker(self) -> None:
        current_head = self._git("rev-parse", "HEAD")

        result = self._run_rc_readiness_with_native_prerelease(
            current_head,
            require_rc_ready=True,
            extra_dart_publish_blocker=True,
        )

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("Dart package strict publish dry-run: not ready", result.stdout)
        self.assertIn(
            "- connectanum_router depends on private workspace package "
            "connectanum_internal (packages/connectanum_internal); publish "
            "connectanum_internal first or remove the hosted dependency before "
            "publishing connectanum_router.",
            result.stdout,
        )
        self.assertIn(
            "- connectanum 2.2.8 (packages/connectanum)",
            result.stdout,
        )
        self.assertIn("- connectanum_client -> connectanum", result.stdout)
        self.assertIn("Release candidate readiness audit failed.", result.stdout)
        self.assertNotIn(
            "Dart package strict publish dry-run: deferred for first GitHub RC",
            result.stdout,
        )

    def test_rc_readiness_rejects_strict_dart_blocker_without_release_plan(
        self,
    ) -> None:
        current_head = self._git("rev-parse", "HEAD")

        result = self._run_rc_readiness_with_native_prerelease(
            current_head,
            require_rc_ready=True,
            omit_dart_release_plan=True,
        )

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("Dart package strict publish dry-run: not ready", result.stdout)
        self.assertIn(
            "- connectanum_router depends on private workspace package "
            "connectanum_internal (packages/connectanum_internal); publish "
            "connectanum_internal first or remove the hosted dependency before "
            "publishing connectanum_router.",
            result.stdout,
        )
        self.assertIn("Release candidate readiness audit failed.", result.stdout)
        self.assertNotIn(
            "Dart package strict publish dry-run: deferred for first GitHub RC",
            result.stdout,
        )

    def test_rc_readiness_rejects_v_prefixed_router_image_preview_tag(
        self,
    ) -> None:
        current_head = self._git("rev-parse", "HEAD")

        result = self._run_rc_readiness_with_native_prerelease(
            current_head,
            router_preview_tag="v0.1.0-rc.2",
            require_rc_ready=True,
        )

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(
            "router image preview primary Docker tag still uses a "
            "project-version v-prefix: v0.1.0-rc.2",
            result.stdout,
        )
        self.assertIn("Router image hosted dry-run gate: not ready", result.stdout)
        self.assertIn("Release candidate readiness audit failed.", result.stdout)

    def test_rc_readiness_rejects_missing_matching_router_image_tag(self) -> None:
        current_head = self._git("rev-parse", "HEAD")

        result = self._run_rc_readiness_with_native_prerelease(
            current_head,
            router_image_tag="v0.1.0-rc.1",
            require_rc_ready=True,
        )

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("GitHub RC prerelease: ready (v0.1.0-rc.2)", result.stdout)
        self.assertIn(
            "Router image RC tag: not ready; "
            "ghcr.io/konsultaner/connectanum-router:0.1.0-rc.2 "
            "is not publicly reachable.",
            result.stdout,
        )
        self.assertIn("Release candidate readiness audit failed.", result.stdout)

    def test_rc_readiness_rejects_local_only_rc_tag_prerelease(self) -> None:
        current_head = self._git("rev-parse", "HEAD")
        stale_head = self._different_sha(current_head)

        result = self._run_rc_readiness_with_native_prerelease(
            current_head,
            github_tag_head=stale_head,
            local_tag_head=current_head,
            require_rc_ready=True,
        )

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("RC tag on checked-out head: ready", result.stdout)
        self.assertIn("- v0.1.0-rc.2 (local)", result.stdout)
        self.assertIn(
            "GitHub RC prerelease: not ready; v0.1.0-rc.2 is not a GitHub tag "
            f"at checked-out head {current_head[:7]}.",
            result.stdout,
        )
        self.assertIn("Release candidate readiness audit failed.", result.stdout)
        self.assertNotIn(
            "GitHub RC prerelease: ready (v0.1.0-rc.2)",
            result.stdout,
        )

    def test_rc_readiness_prefers_github_rc_tag_over_local_lower_tag(self) -> None:
        current_head = self._git("rev-parse", "HEAD")

        result = self._run_rc_readiness_with_native_prerelease(
            current_head,
            local_tag_head=current_head,
            local_tag_name="v0.1.0-rc.1",
        )

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("RC tag on checked-out head: ready", result.stdout)
        self.assertIn("- v0.1.0-rc.1 (local)", result.stdout)
        self.assertIn("- v0.1.0-rc.2 (GitHub)", result.stdout)
        self.assertIn("GitHub RC prerelease: ready (v0.1.0-rc.2)", result.stdout)
        self.assertIn(
            "Router image RC tag: ready (0.1.0-rc.2, sha256:abcdef)",
            result.stdout,
        )
        self.assertNotIn(
            "GitHub RC prerelease: not ready; v0.1.0-rc.1 is not a GitHub tag",
            result.stdout,
        )

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

    def _write_dart_publish_dry_run(
        self,
        path: Path,
        extra_blocker: bool = False,
        omit_release_plan: bool = False,
    ) -> None:
        has_blocker = extra_blocker or omit_release_plan
        blocker_output = ""
        private_package_lines = "                printf 'none.\\n'\n"
        private_dependency_lines = "                printf 'none.\\n'\n"
        extra_dependency_edge_line = ""
        exit_code = 0
        if has_blocker:
            blocker_output = (
                "                printf '\\nDart package release-readiness blockers:\\n'\n"
                "                printf -- '- connectanum_router depends on "
                "private workspace package connectanum_internal "
                "(packages/connectanum_internal); publish "
                "connectanum_internal first or remove the hosted dependency "
                "before publishing connectanum_router.\\n'\n"
            )
            exit_code = 1
            private_dependency_lines = (
                "                printf -- '- connectanum_internal 0.1.0 "
                "(packages/connectanum_internal)\\n'\n"
            )
            private_package_lines = private_dependency_lines
            extra_dependency_edge_line = (
                "                printf -- '- connectanum_internal -> "
                "connectanum_router\\n'\n"
            )

        release_plan_output = ""
        if not omit_release_plan:
            release_plan_output = (
                "                printf '\\nDart package release-order plan:\\n'\n"
                "                printf '\\nCurrently publishable package archives:\\n'\n"
                "                printf -- '- connectanum_client 2.2.6 "
                "(packages/connectanum_client)\\n'\n"
                "                printf -- '- connectanum_core 0.1.0 "
                "(packages/connectanum_core)\\n'\n"
                "                printf -- '- connectanum_mcp 0.1.0 "
                "(packages/connectanum_mcp)\\n'\n"
                "                printf -- '- connectanum_router 0.1.0 "
                "(packages/connectanum_router)\\n'\n"
                "                printf -- '- connectanum 2.2.8 "
                "(packages/connectanum)\\n'\n"
                "                printf -- '- connectanum_auth_server 0.1.0 "
                "(packages/connectanum_auth_server)\\n'\n"
                "                printf -- '- connectanum_bench 0.1.0 "
                "(packages/connectanum_bench)\\n'\n"
                "                printf '\\nPrivate workspace packages not "
                "currently publishable:\\n'\n"
                f"{private_package_lines}"
                "                printf '\\nPrivate workspace packages blocking "
                "publishable targets:\\n'\n"
                f"{private_dependency_lines}"
                "                printf '\\nWorkspace dependency order that must "
                "be satisfied before public publishing:\\n'\n"
                "                printf -- '- connectanum_core -> "
                "connectanum_client\\n'\n"
                "                printf -- '- connectanum_client -> "
                "connectanum_mcp\\n'\n"
                "                printf -- '- connectanum_core -> "
                "connectanum_mcp\\n'\n"
                "                printf -- '- connectanum_core -> "
                "connectanum_router\\n'\n"
                "                printf -- '- connectanum_client -> "
                "connectanum_router\\n'\n"
                "                printf -- '- connectanum_mcp -> "
                "connectanum_router\\n'\n"
                "                printf -- '- connectanum_client -> "
                "connectanum\\n'\n"
                "                printf -- '- connectanum_core -> "
                "connectanum_auth_server\\n'\n"
                "                printf -- '- connectanum_router -> "
                "connectanum_auth_server\\n'\n"
                "                printf -- '- connectanum_auth_server -> "
                "connectanum_bench\\n'\n"
                f"{extra_dependency_edge_line}"
                "                printf '\\nApproved package release strategy:\\n'\n"
                "                printf -- '- Publish the modular package graph "
                "in dependency order.\\n'\n"
                "                printf -- '- Keep the legacy public connectanum "
                "package as the client-facing compatibility wrapper/facade.\\n'\n"
                "                printf '\\nOperator decisions still required "
                "before a real publish:\\n'\n"
                "                printf -- '- Confirm package-name ownership and "
                "publisher configuration on pub.dev.\\n'\n"
            )

        path.write_text(
            textwrap.dedent(
                f"""\
                #!/usr/bin/env bash
                set -euo pipefail
                printf 'Dart package publish dry-run completed for 7 package(s).\\n'
{blocker_output}
                if [[ {1 if has_blocker else 0} -eq 0 ]]; then
                  printf '\\nNo private workspace dependency blockers found for publishable packages.\\n'
                fi
                printf '\\nAll Dart package publish dry-runs reported zero warnings.\\n'
{release_plan_output}
                exit {exit_code}
                """
            )
        )
        path.chmod(0o755)

    def _run_audit(
        self,
        ci_head: str,
        gate: str = "--require-clean-latest-ci",
        branch: str = "add-router",
        github_actions_status: str = "operational",
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
                            elif "required_pull_request_reviews" in jq and "!= null" in jq:
                                print("true")
                            elif "required_approving_review_count" in jq:
                                print("1")
                            elif "require_code_owner_reviews" in jq:
                                print("false")
                            elif "enforce_admins" in jq:
                                print("false")
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
                            print("Dart VM Coverage completed")
                            print("# Check for gpg only if validation is not being skipped")
                            print("gpg: WARNING: This key is not certified with a trusted signature!")
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
                            print("Dart VM Coverage\\tcompleted\\tsuccess")
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
                      *githubstatus.com*)
                        if [[ "${FAKE_GITHUB_ACTIONS_STATUS:-operational}" == "degraded_performance" ]]; then
                          printf '{"status":{"indicator":"minor","description":"Partially Degraded Service"},"components":[{"name":"Actions","status":"degraded_performance"}],"incidents":[{"name":"Incident with Actions and Pages","status":"investigating","components":[{"name":"Actions","status":"degraded_performance"}]}]}'
                        else
                          printf '{"status":{"indicator":"none","description":"All Systems Operational"},"components":[{"name":"Actions","status":"operational"}],"incidents":[]}'
                        fi
                        ;;
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
            env["FAKE_GITHUB_ACTIONS_STATUS"] = github_actions_status
            env["PATH"] = f"{temp_dir}{os.pathsep}{env['PATH']}"

            return subprocess.run(
                [
                    str(AUDIT_SCRIPT),
                    "--branch",
                    branch,
                    gate,
                ],
                cwd=REPO_ROOT,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )

    def _run_wamp_profile_benchmark_audit(
        self,
        ci_head: str,
        benchmark_head: str,
        changed_paths: str = "",
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
                    benchmark_head = os.environ["FAKE_WAMP_PROFILE_BENCHMARK_HEAD"]
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
                            if jq == ".protected":
                                print("false")
                            elif jq == ".commit.sha // empty":
                                print(ci_head)
                            else:
                                sys.exit(1)
                        elif path == f"repos/{repository}/branches/master":
                            if jq == ".protected":
                                print("true")
                            elif jq == ".commit.sha // empty":
                                print(ci_head)
                            else:
                                sys.exit(1)
                        elif path == f"repos/{repository}/branches/master/protection":
                            if "required_status_checks" in jq:
                                print("Fast Checks, Full Verify")
                            elif "required_pull_request_reviews" in jq and "!= null" in jq:
                                print("true")
                            elif "required_approving_review_count" in jq:
                                print("1")
                            elif "require_code_owner_reviews" in jq:
                                print("false")
                            elif "enforce_admins" in jq:
                                print("false")
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
                            workflow = value_after("--workflow")
                            if workflow == "WAMP Profile Benchmarks":
                                print("127")
                            else:
                                print("")
                        else:
                            print(
                                f"- WAMP Profile Benchmarks #127: "
                                f"completed/success @ {benchmark_head[:7]} "
                                "(2026-05-19T00:00:00Z)"
                            )
                    elif args[:2] == ["run", "view"]:
                        run_id = args[2] if len(args) > 2 else ""
                        if run_id != "127":
                            sys.exit(1)

                        json_fields = json_arg()
                        jq = jq_arg()
                        if json_fields == "status,conclusion,headSha,url,displayTitle,event":
                            print(
                                "Run: WAMP Profile Benchmarks #127 "
                                f"completed/success @ {benchmark_head[:7]}"
                            )
                            print("Title: WAMP Profile Benchmarks")
                            print("Event: push")
                            print("URL: https://github.example.invalid/runs/127")
                        elif json_fields == "status,conclusion,headSha,event":
                            print(f"completed\\tsuccess\\t{benchmark_head}\\tpush")
                        elif json_fields == "jobs" and ".steps[]" in jq:
                            print("Run canonical WAMP profile gates\\tcompleted\\tsuccess")
                            print("Upload WAMP profile artifacts\\tcompleted\\tsuccess")
                        elif json_fields == "jobs":
                            print("Linux WAMP profile gates\\tcompleted\\tsuccess")
                        else:
                            sys.exit(1)
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

                    if [[ "${1:-}" == "rev-parse" && "${2:-}" == "HEAD" ]]; then
                      printf '%s\\n' "$FAKE_CI_HEAD"
                      exit 0
                    fi

                    if [[ "${1:-}" == "cat-file" && "${2:-}" == "-e" ]]; then
                      if [[ "${3:-}" == "${FAKE_WAMP_PROFILE_BENCHMARK_HEAD}^{commit}" ]]; then
                        exit 0
                      fi
                    fi

                    if [[ "${1:-}" == "diff" && "${2:-}" == "--name-only" ]]; then
                      printf '%s' "${FAKE_CHANGED_PATHS:-}"
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
            env["FAKE_WAMP_PROFILE_BENCHMARK_HEAD"] = benchmark_head
            env["FAKE_CHANGED_PATHS"] = changed_paths
            env["FAKE_WORKFLOW_PATHS"] = workflow_paths
            env["REAL_GIT"] = real_git or "git"
            env["PATH"] = f"{temp_dir}{os.pathsep}{env['PATH']}"

            return subprocess.run(
                [
                    str(AUDIT_SCRIPT),
                    "--branch",
                    "add-router",
                    "--require-clean-wamp-profile-benchmarks",
                ],
                cwd=REPO_ROOT,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )

    def _run_router_image_audit(
        self,
        ci_head: str,
        router_image_head: str,
        changed_paths: str = "",
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
                    from pathlib import Path

                    args = sys.argv[1:]
                    repository = "konsultaner/connectanum-dart"
                    router_image_head = os.environ["FAKE_ROUTER_IMAGE_HEAD"]
                    preview_tag = os.environ.get("FAKE_ROUTER_PREVIEW_TAG", "sha-preview")
                    workflow_paths = os.environ["FAKE_WORKFLOW_PATHS"].splitlines()


                    def value_after(name):
                        return args[args.index(name) + 1] if name in args else ""


                    def jq_arg():
                        return value_after("--jq")


                    def json_arg():
                        return value_after("--json")


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
                                print(router_image_head)
                            else:
                                sys.exit(1)
                        elif path == f"repos/{repository}/branches/master":
                            if jq == ".protected":
                                print("true")
                            elif jq == ".commit.sha // empty":
                                print(router_image_head)
                            else:
                                sys.exit(1)
                        elif path == f"repos/{repository}/rulesets":
                            print("0")
                        elif path == f"repos/{repository}/actions/workflows":
                            if jq == ".workflows[].path":
                                print("\\n".join(workflow_paths))
                            elif jq.startswith(".workflows[] |"):
                                for path in workflow_paths:
                                    name = path.rsplit("/", 1)[-1]
                                    print(f"- {name}: active ({path})")
                            else:
                                sys.exit(1)
                        elif path.startswith(f"repos/{repository}/check-runs/"):
                            print("")
                        else:
                            sys.exit(1)
                    elif args[:2] == ["run", "list"]:
                        if "--workflow" in args:
                            workflow = value_after("--workflow")
                            if workflow == "Router Image":
                                print("126")
                            else:
                                print("")
                        else:
                            print(
                                f"- Router Image #126: completed/success "
                                f"@ {router_image_head[:7]} "
                                "(2026-05-19T00:00:00Z)"
                            )
                    elif args[:2] == ["run", "view"]:
                        run_id = args[2] if len(args) > 2 else ""
                        if run_id != "126":
                            sys.exit(1)

                        json_fields = json_arg()
                        jq = jq_arg()
                        if json_fields == "status,conclusion,headSha,url,displayTitle,event":
                            print(
                                "Run: Router Image #126 "
                                f"completed/success @ {router_image_head[:7]}"
                            )
                            print("Title: Router Image")
                            print("Event: workflow_dispatch")
                            print("URL: https://github.example.invalid/runs/126")
                        elif json_fields == "status,conclusion,headSha,event":
                            print(f"completed\\tsuccess\\t{router_image_head}\\tworkflow_dispatch")
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
                            print("Publish Router Image\\tcompleted\\tsuccess")
                        else:
                            sys.exit(1)
                    elif args[:2] == ["run", "download"]:
                        download_dir = value_after("--dir")
                        if not download_dir:
                            sys.exit(1)
                        Path(download_dir, "router-image-metadata.md").write_text(
                            "## Router Image Metadata\\n\\n"
                            "- Image: `ghcr.io/konsultaner/connectanum-router`\\n"
                            "- Mode: `dry-run`\\n"
                            "- Publish: `false`\\n"
                            "- Provenance: `false`\\n"
                            "- SBOM: `false`\\n\\n"
                            "### Tags\\n\\n"
                            f"- `ghcr.io/konsultaner/connectanum-router:{preview_tag}`\\n\\n"
                            "### Labels\\n\\n"
                            f"- `org.opencontainers.image.version={preview_tag}`\\n",
                            encoding="utf-8",
                        )
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

                    if [[ "${1:-}" == "rev-parse" && "${2:-}" == "HEAD" ]]; then
                      printf '%s\\n' "$FAKE_CI_HEAD"
                      exit 0
                    fi

                    if [[ "${1:-}" == "cat-file" && "${2:-}" == "-e" ]]; then
                      if [[ "${3:-}" == "${FAKE_ROUTER_IMAGE_HEAD}^{commit}" ]]; then
                        exit 0
                      fi
                    fi

                    if [[ "${1:-}" == "diff" && "${2:-}" == "--name-only" ]]; then
                      printf '%s' "${FAKE_CHANGED_PATHS:-}"
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
                      *githubstatus.com/api/v2/summary.json*)
                        printf '{"status":{"indicator":"none","description":"All Systems Operational"},"components":[{"name":"Actions","status":"operational"}],"incidents":[]}'
                        ;;
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
            env["FAKE_ROUTER_IMAGE_HEAD"] = router_image_head
            env["FAKE_CHANGED_PATHS"] = changed_paths
            env["FAKE_WORKFLOW_PATHS"] = workflow_paths
            env["REAL_GIT"] = real_git or "git"
            env["PATH"] = f"{temp_dir}{os.pathsep}{env['PATH']}"

            return subprocess.run(
                [
                    str(AUDIT_SCRIPT),
                    "--branch",
                    "add-router",
                    "--require-clean-router-image-dry-run",
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
        github_tag_head: str | None = None,
        local_tag_head: str | None = None,
        router_image_tag: str = "0.1.0-rc.2",
        router_preview_tag: str = "0.1.0-rc.2",
        require_rc_ready: bool = False,
        extra_dart_publish_blocker: bool = False,
        omit_dart_release_plan: bool = False,
        local_tag_name: str = "v0.1.0-rc.2",
        native_release_tag: str = "v0.1.0-rc.2",
        native_release_mode: str = "prerelease",
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            fake_gh = temp_path / "gh"
            fake_git = temp_path / "git"
            fake_curl = temp_path / "curl"
            fake_dart_publish = temp_path / "dart-package-publish-dry-run"
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
                    from pathlib import Path

                    args = sys.argv[1:]
                    repository = "konsultaner/connectanum-dart"
                    ci_head = os.environ["FAKE_CI_HEAD"]
                    native_release_tag = os.environ.get("FAKE_NATIVE_RELEASE_TAG", "v0.1.0-rc.2")
                    native_release_mode = os.environ.get("FAKE_NATIVE_RELEASE_MODE", "prerelease")
                    branch_head = os.environ.get("FAKE_BRANCH_HEAD", ci_head)
                    preview_tag = os.environ.get("FAKE_ROUTER_PREVIEW_TAG", "0.1.0-rc.2")
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
                        "WAMP Profile Benchmarks": "127",
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
                            elif "required_pull_request_reviews" in jq and "!= null" in jq:
                                print("true")
                            elif "required_approving_review_count" in jq:
                                print("1")
                            elif "require_code_owner_reviews" in jq:
                                print("false")
                            elif "enforce_admins" in jq:
                                print("false")
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
                                print(f"Release intent accepted: {native_release_tag} (project, {native_release_mode}).")
                                if native_release_mode == "dry-run":
                                    print("Artifact native-release-preview has been successfully uploaded!")
                            else:
                                print("Fast Checks completed")
                                print("Dart VM Coverage completed")
                                print("Full Verify completed")
                            sys.exit(0)

                        if json_fields == "status,conclusion,headSha,url,displayTitle,event":
                            titles = {
                                "124": "Dart Package Publish Dry Run",
                                "125": "Native Artifacts",
                                "126": "Router Image",
                                "127": "WAMP Profile Benchmarks",
                            }
                            events = {
                                "124": "workflow_dispatch",
                                "125": "workflow_dispatch",
                                "126": "workflow_dispatch",
                                "127": "push",
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
                            if run_id == "126":
                                print("Resolve image metadata\\tcompleted\\tsuccess")
                                print("Upload router image preview\\tcompleted\\tsuccess")
                                print("Log in to GHCR\\tcompleted\\tskipped")
                                print("Build or publish multi-arch router image\\tcompleted\\tsuccess")
                            elif run_id == "127":
                                print("Run canonical WAMP profile gates\\tcompleted\\tsuccess")
                                print("Upload WAMP profile artifacts\\tcompleted\\tsuccess")
                            else:
                                sys.exit(1)
                        elif json_fields == "jobs":
                            if run_id == "123":
                                print("Fast Checks\\tcompleted\\tsuccess")
                                print("Dart VM Coverage\\tcompleted\\tsuccess")
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
                            elif run_id == "127":
                                print("Linux WAMP profile gates\\tcompleted\\tsuccess")
                            else:
                                sys.exit(1)
                        else:
                            sys.exit(1)
                    elif args[:2] == ["release", "view"]:
                        tag = args[2] if len(args) > 2 else ""
                        json_fields = json_arg()

                        if json_fields == "isPrerelease,isDraft,targetCommitish,assets":
                            if native_release_mode != "prerelease" or tag != native_release_tag:
                                sys.exit(1)
                            print(f"true\\tfalse\\t{ci_head}\\t30")
                        elif json_fields == "tagName,isPrerelease,isDraft":
                            if tag != "v0.1.0-rc.2":
                                sys.exit(1)
                            print("v0.1.0-rc.2\\ttrue\\tfalse")
                        else:
                            if native_release_mode == "dry-run" and tag == native_release_tag:
                                sys.exit(1)
                            if tag not in (native_release_tag, "v0.1.0-rc.2"):
                                sys.exit(1)
                            print(tag)
                    elif args[:2] == ["run", "download"]:
                        download_dir = value_after("--dir")
                        if not download_dir:
                            sys.exit(1)
                        Path(download_dir, "router-image-metadata.md").write_text(
                            "## Router Image Metadata\\n\\n"
                            "- Image: `ghcr.io/konsultaner/connectanum-router`\\n"
                            "- Mode: `dry-run`\\n"
                            "- Publish: `false`\\n"
                            "- Provenance: `false`\\n"
                            "- SBOM: `false`\\n\\n"
                            "### Tags\\n\\n"
                            f"- `ghcr.io/konsultaner/connectanum-router:{preview_tag}`\\n\\n"
                            "### Labels\\n\\n"
                            f"- `org.opencontainers.image.version={preview_tag}`\\n",
                            encoding="utf-8",
                        )
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
                    local_tag="${FAKE_LOCAL_TAG_NAME:-v0.1.0-rc.2}"

                    if [[ "${1:-}" == "ls-remote" && "${2:-}" == "--tags" ]]; then
                      if [[ -n "${FAKE_GITHUB_TAG_HEAD:-}" ]]; then
                        printf '%s\\trefs/tags/v0.1.0-rc.2\\n' "$FAKE_GITHUB_TAG_HEAD"
                      fi
                      exit 0
                    fi

                    if [[ "${1:-}" == "tag" && "${2:-}" == "--points-at" ]]; then
                      if [[ -n "${FAKE_LOCAL_TAG_HEAD:-}" && "$FAKE_LOCAL_TAG_HEAD" == "$FAKE_CI_HEAD" ]]; then
                        printf '%s\\n' "$local_tag"
                      fi
                      exit 0
                    fi

                    if [[ "${1:-}" == "tag" && "${2:-}" == "--list" ]]; then
                      if [[ -n "${FAKE_LOCAL_TAG_HEAD:-}" ]]; then
                        printf '%s\\n' "$local_tag"
                      fi
                      exit 0
                    fi

                    if [[ "${1:-}" == "rev-list" && "${2:-}" == "-n" && "${3:-}" == "1" && "${4:-}" == "$local_tag" ]]; then
                      if [[ -n "${FAKE_LOCAL_TAG_HEAD:-}" ]]; then
                        printf '%s\\n' "$FAKE_LOCAL_TAG_HEAD"
                        exit 0
                      fi
                    fi

                    if [[ "${1:-}" == "rev-parse" && "${2:-}" == "HEAD" ]]; then
                      printf '%s\\n' "$FAKE_CI_HEAD"
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
                    router_tag="${FAKE_ROUTER_IMAGE_TAG:-0.1.0-rc.2}"

                    case "$*" in
                      *ghcr.io/token*)
                        printf '{"token":"fake-token"}'
                        ;;
                      *tags/list*)
                        printf '{"name":"konsultaner/connectanum-router","tags":["%s"]}' "$router_tag"
                        ;;
                      *manifests/"$router_tag"*)
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
            self._write_dart_publish_dry_run(
                fake_dart_publish,
                extra_blocker=extra_dart_publish_blocker,
                omit_release_plan=omit_dart_release_plan,
            )

            env = os.environ.copy()
            env["GH_BIN"] = str(fake_gh)
            env["DART_PACKAGE_PUBLISH_DRY_RUN_BIN"] = str(fake_dart_publish)
            env["FAKE_CI_HEAD"] = ci_head
            env["FAKE_BRANCH_HEAD"] = branch_head or ci_head
            env["FAKE_GITHUB_TAG_HEAD"] = (
                ci_head if github_tag_head is None else github_tag_head
            )
            env["FAKE_LOCAL_TAG_HEAD"] = local_tag_head or ""
            env["FAKE_LOCAL_TAG_NAME"] = local_tag_name
            env["FAKE_NATIVE_RELEASE_TAG"] = native_release_tag
            env["FAKE_NATIVE_RELEASE_MODE"] = native_release_mode
            env["FAKE_ROUTER_IMAGE_TAG"] = router_image_tag
            env["FAKE_ROUTER_PREVIEW_TAG"] = router_preview_tag
            env["FAKE_WORKFLOW_PATHS"] = workflow_paths
            env["REAL_GIT"] = real_git or "git"
            env["PATH"] = f"{temp_dir}{os.pathsep}{env['PATH']}"

            rc_flag = "--require-rc-ready" if require_rc_ready else "--show-rc-readiness"
            return subprocess.run(
                [
                    str(AUDIT_SCRIPT),
                    "--branch",
                    branch,
                    rc_flag,
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
            fake_dart_publish = temp_path / "dart-package-publish-dry-run"
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
                    from pathlib import Path

                    args = sys.argv[1:]
                    repository = "konsultaner/connectanum-dart"
                    ci_head = os.environ["FAKE_CI_HEAD"]
                    branch_head = os.environ.get("FAKE_BRANCH_HEAD", ci_head)
                    preview_tag = os.environ.get("FAKE_ROUTER_PREVIEW_TAG", "0.1.0-rc.2")
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
                        "WAMP Profile Benchmarks": "127",
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
                            elif "required_pull_request_reviews" in jq and "!= null" in jq:
                                print("true")
                            elif "required_approving_review_count" in jq:
                                print("1")
                            elif "require_code_owner_reviews" in jq:
                                print("false")
                            elif "enforce_admins" in jq:
                                print("false")
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
                                print("Dart VM Coverage completed")
                                print("Full Verify completed")
                            sys.exit(0)

                        if json_fields == "status,conclusion,headSha,url,displayTitle,event":
                            titles = {
                                "124": "Dart Package Publish Dry Run",
                                "125": "Native Artifacts",
                                "126": "Router Image",
                                "127": "WAMP Profile Benchmarks",
                            }
                            events = {
                                "124": "workflow_dispatch",
                                "125": "workflow_dispatch",
                                "126": "workflow_dispatch",
                                "127": "push",
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
                            if run_id == "126":
                                print("Resolve image metadata\\tcompleted\\tsuccess")
                                print("Upload router image preview\\tcompleted\\tsuccess")
                                print("Log in to GHCR\\tcompleted\\tskipped")
                                print("Build or publish multi-arch router image\\tcompleted\\tsuccess")
                            elif run_id == "127":
                                print("Run canonical WAMP profile gates\\tcompleted\\tsuccess")
                                print("Upload WAMP profile artifacts\\tcompleted\\tsuccess")
                            else:
                                sys.exit(1)
                        elif json_fields == "jobs":
                            if run_id == "123":
                                print("Fast Checks\\tcompleted\\tsuccess")
                                print("Dart VM Coverage\\tcompleted\\tsuccess")
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
                            elif run_id == "127":
                                print("Linux WAMP profile gates\\tcompleted\\tsuccess")
                            else:
                                sys.exit(1)
                        else:
                            sys.exit(1)
                    elif args[:2] == ["release", "view"]:
                        sys.exit(1)
                    elif args[:2] == ["run", "download"]:
                        download_dir = value_after("--dir")
                        if not download_dir:
                            sys.exit(1)
                        Path(download_dir, "router-image-metadata.md").write_text(
                            "## Router Image Metadata\\n\\n"
                            "- Image: `ghcr.io/konsultaner/connectanum-router`\\n"
                            "- Mode: `dry-run`\\n"
                            "- Publish: `false`\\n"
                            "- Provenance: `false`\\n"
                            "- SBOM: `false`\\n\\n"
                            "### Tags\\n\\n"
                            f"- `ghcr.io/konsultaner/connectanum-router:{preview_tag}`\\n\\n"
                            "### Labels\\n\\n"
                            f"- `org.opencontainers.image.version={preview_tag}`\\n",
                            encoding="utf-8",
                        )
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
            self._write_dart_publish_dry_run(fake_dart_publish)

            env = os.environ.copy()
            env["GH_BIN"] = str(fake_gh)
            env["DART_PACKAGE_PUBLISH_DRY_RUN_BIN"] = str(fake_dart_publish)
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
