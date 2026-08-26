#!/usr/bin/env python3
"""Regression checks for WampApp platform artifact packaging."""

from __future__ import annotations

import hashlib
import json
import os
import platform
import shutil
import subprocess
import tarfile
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGER = ROOT / "bin/package-wamp-app"
ANDROID_BUILD = ROOT / "examples/wamp_app/client/android/app/build.gradle.kts"
WORKFLOW = ROOT / ".github/workflows/wamp-app-artifacts.yml"
SERVER_ENTRYPOINT = ROOT / "examples/wamp_app/server/bin/wamp_app_server.dart"


class WampAppPackagingTest(unittest.TestCase):
    def test_android_release_signing_never_uses_the_debug_key(self) -> None:
        build_script = ANDROID_BUILD.read_text(encoding="utf-8")

        self.assertNotIn('signingConfigs.getByName("debug")', build_script)
        self.assertIn('rootProject.file("key.properties")', build_script)
        self.assertIn('create("release")', build_script)

    def test_every_artifact_target_has_explicit_beta_metadata(self) -> None:
        system_platform = {"darwin": "macos"}.get(
            platform.system().lower(), platform.system().lower()
        )
        expected = {
            "web": ("client", "web", "release"),
            "android": ("client", "android", "release-and-debug"),
            "ios": ("client", "ios", "release"),
            "macos": ("client", "macos", "release"),
            "linux": ("client", "linux", "release"),
            "windows": ("client", "windows", "release"),
            "server": ("server", system_platform, "release"),
        }

        for target, fields in expected.items():
            with self.subTest(target=target):
                result = subprocess.run(
                    ["bash", str(PACKAGER), "--describe-target", target],
                    cwd=ROOT,
                    check=True,
                    capture_output=True,
                    text=True,
                )
                metadata = json.loads(result.stdout)
                self.assertEqual(metadata["component"], fields[0])
                self.assertEqual(metadata["platform"], fields[1])
                self.assertEqual(metadata["build_mode"], fields[2])
                self.assertEqual(metadata["artifact_role"], "beta-testing")
                self.assertFalse(metadata["store_ready"])
                self.assertTrue(metadata["signing_policy"])
                self.assertTrue(metadata["installability"])

    def test_unknown_target_fails_before_build(self) -> None:
        result = subprocess.run(
            ["bash", str(PACKAGER), "--describe-target", "plan9"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unsupported WampApp artifact target: plan9", result.stderr)

    def test_host_mismatch_fails_before_flutter_is_invoked(self) -> None:
        host = platform.system().lower()
        target = "linux" if host != "linux" else "macos"

        with tempfile.TemporaryDirectory() as temporary_dir:
            fake_bin = Path(temporary_dir) / "bin"
            fake_bin.mkdir()
            marker = Path(temporary_dir) / "flutter-called"
            flutter = fake_bin / "flutter"
            flutter.write_text(
                f"#!/usr/bin/env bash\ntouch {marker!s}\nexit 99\n",
                encoding="utf-8",
            )
            flutter.chmod(0o755)
            environment = os.environ.copy()
            environment["PATH"] = f"{fake_bin}:{environment['PATH']}"

            result = subprocess.run(
                ["bash", str(PACKAGER), "--target", target],
                cwd=ROOT,
                env=environment,
                capture_output=True,
                text=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("requires a", result.stderr)
            self.assertFalse(marker.exists())

    def test_web_package_is_clean_manifested_and_checksum_verified(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_dir:
            checkout = Path(temporary_dir) / "checkout"
            (checkout / "bin").mkdir(parents=True)
            client = checkout / "examples/wamp_app/client"
            client.mkdir(parents=True)
            shutil.copy(ROOT / "bin/common.sh", checkout / "bin/common.sh")
            shutil.copy(PACKAGER, checkout / "bin/package-wamp-app")
            shutil.copy(ROOT / "LICENSE", checkout / "LICENSE")
            (client / "pubspec.yaml").write_text(
                "name: wamp_app\nversion: 0.1.0+1\n", encoding="utf-8"
            )

            stale = client / "build/web/stale.txt"
            stale.parent.mkdir(parents=True)
            stale.write_text("stale", encoding="utf-8")

            fake_bin = checkout / "fake-bin"
            fake_bin.mkdir()
            flutter_log = checkout / "flutter.log"
            flutter = fake_bin / "flutter"
            flutter.write_text(
                textwrap.dedent(
                    f"""\
                    #!/usr/bin/env bash
                    set -euo pipefail
                    printf '%s\\n' "$*" >> {flutter_log!s}
                    case "$1" in
                      clean)
                        rm -rf build
                        ;;
                      pub)
                        [[ "$2" == "get" ]]
                        ;;
                      build)
                        [[ "$2" == "web" ]]
                        mkdir -p build/web
                        printf '<html>fresh</html>\\n' > build/web/index.html
                        ;;
                      *)
                        exit 98
                        ;;
                    esac
                    """
                ),
                encoding="utf-8",
            )
            flutter.chmod(0o755)

            output_dir = checkout / "out"
            github_output = checkout / "github-output"
            github_output.write_text("existing=value\n", encoding="utf-8")
            environment = os.environ.copy()
            environment["PATH"] = f"{fake_bin}:{environment['PATH']}"
            environment["GITHUB_OUTPUT"] = str(github_output)

            result = subprocess.run(
                [
                    "bash",
                    str(checkout / "bin/package-wamp-app"),
                    "--target",
                    "web",
                    "--out-dir",
                    str(output_dir),
                ],
                cwd=checkout,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.stderr, "")

            commands = flutter_log.read_text(encoding="utf-8").splitlines()
            self.assertEqual(commands, ["pub get", "build web --release"])
            archive = next(output_dir.glob("*.tar.gz"))
            checksum = Path(f"{archive}.sha256")
            manifest_path = next(output_dir.glob("*.manifest.json"))
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            self.assertEqual(manifest["schema_version"], 1)
            self.assertEqual(manifest["target"], "web")
            self.assertEqual(manifest["app_version"], "0.1.0+1")
            self.assertEqual(manifest["git_commit"], "unknown")
            self.assertFalse(manifest["git_dirty"])
            self.assertFalse(manifest["store_ready"])

            expected_digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            self.assertEqual(
                checksum.read_text(encoding="utf-8").strip(),
                f"{expected_digest}  {archive.name}",
            )
            with tarfile.open(archive) as packaged:
                names = packaged.getnames()
            self.assertTrue(any(name.endswith("/web/index.html") for name in names))
            self.assertFalse(any(name.endswith("stale.txt") for name in names))

            output_lines = github_output.read_text(encoding="utf-8").splitlines()
            self.assertEqual(output_lines[0], "existing=value")
            self.assertTrue(any(line.startswith("artifact_name=") for line in output_lines))
            self.assertTrue(any(line.startswith("archive_path=") for line in output_lines))

    def test_windows_package_prefetches_matching_hosted_native_release(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_dir:
            checkout = Path(temporary_dir) / "checkout"
            (checkout / "bin").mkdir(parents=True)
            client = checkout / "examples/wamp_app/client"
            client.mkdir(parents=True)
            installer = checkout / "packages/connectanum_client/tool/install_native.dart"
            installer.parent.mkdir(parents=True)
            installer.write_text("// exercised through the fake Dart runner\n", encoding="utf-8")
            shutil.copy(ROOT / "bin/common.sh", checkout / "bin/common.sh")
            shutil.copy(PACKAGER, checkout / "bin/package-wamp-app")
            shutil.copy(ROOT / "LICENSE", checkout / "LICENSE")
            (client / "pubspec.yaml").write_text(
                textwrap.dedent(
                    """\
                    name: wamp_app
                    version: 0.1.0+1
                    dependencies:
                      connectanum_client: 3.0.0-beta.2
                    """
                ),
                encoding="utf-8",
            )

            fake_bin = checkout / "fake-bin"
            fake_bin.mkdir()
            native_path_log = checkout / "native-path.log"
            dart_log = checkout / "dart.log"
            flutter_log = checkout / "flutter.log"
            staged_pubspec_log = checkout / "staged-pubspec.yaml"
            source_pubspec = (client / "pubspec.yaml").read_text(encoding="utf-8")

            uname = fake_bin / "uname"
            uname.write_text(
                """#!/usr/bin/env bash
case "${1:-}" in
  -s) printf 'MINGW64_NT-10.0\n' ;;
  -m) printf 'x86_64\n' ;;
  *) exit 97 ;;
esac
""",
                encoding="utf-8",
            )
            uname.chmod(0o755)

            cargo = fake_bin / "cargo"
            cargo.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            cargo.chmod(0o755)

            dart = fake_bin / "dart"
            dart.write_text(
                textwrap.dedent(
                    f"""\
                    #!/usr/bin/env bash
                    set -euo pipefail
                    printf '%s\\n' "$*" >> {dart_log!s}
                    if [[ "$1" == "pub" && "$2" == "get" ]]; then
                      exit 0
                    fi
                    out_dir=""
                    while [[ $# -gt 0 ]]; do
                      if [[ "$1" == "--out-dir" ]]; then
                        out_dir="$2"
                        shift 2
                      else
                        shift
                      fi
                    done
                    [[ -n "$out_dir" ]]
                    mkdir -p "$out_dir"
                    printf 'prebuilt-dll\n' > "$out_dir/ct_ffi.dll"
                    printf '%s\n' "$out_dir/ct_ffi.dll"
                    """
                ),
                encoding="utf-8",
            )
            dart.chmod(0o755)

            flutter = fake_bin / "flutter"
            flutter.write_text(
                textwrap.dedent(
                    f"""\
                    #!/usr/bin/env bash
                    set -euo pipefail
                    printf '%s\\n' "$*" >> {flutter_log!s}
                    case "$1" in
                      pub)
                        [[ "$2" == "get" ]]
                        ;;
                      build)
                        [[ "$2" == "windows" ]]
                        if [[ "$PWD" != */out/wamp-app-build/windows/wamp_app/client ]]; then
                          exit 97
                        fi
                        cp pubspec.yaml {staged_pubspec_log!s}
                        if [[ "${{FAIL_WINDOWS_BUILD:-}}" == "1" ]]; then
                          exit 96
                        fi
                        [[ -f "${{CONNECTANUM_NATIVE_LIB:-}}" ]]
                        printf '%s\n' "$CONNECTANUM_NATIVE_LIB" > {native_path_log!s}
                        mkdir -p build/windows/x64/runner/Release
                        printf 'windows-exe\n' > build/windows/x64/runner/Release/wamp_app.exe
                        ;;
                      *)
                        exit 98
                        ;;
                    esac
                    """
                ),
                encoding="utf-8",
            )
            flutter.chmod(0o755)

            environment = os.environ.copy()
            environment["PATH"] = f"{fake_bin}:{environment['PATH']}"
            output_dir = checkout / "artifacts"

            failing_environment = environment.copy()
            failing_environment["FAIL_WINDOWS_BUILD"] = "1"
            failed_result = subprocess.run(
                [
                    "bash",
                    str(checkout / "bin/package-wamp-app"),
                    "--target",
                    "windows",
                    "--out-dir",
                    str(output_dir),
                ],
                cwd=checkout,
                env=failing_environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(failed_result.returncode, 96, failed_result.stderr)
            self.assertEqual(
                (client / "pubspec.yaml").read_text(encoding="utf-8"), source_pubspec
            )
            self.assertFalse((checkout / "out/wamp-app-build/windows").exists())
            self.assertEqual(
                flutter_log.read_text(encoding="utf-8").splitlines(),
                ["pub get", "build windows --release --verbose"],
            )
            flutter_log.unlink()

            result = subprocess.run(
                [
                    "bash",
                    str(checkout / "bin/package-wamp-app"),
                    "--target",
                    "windows",
                    "--out-dir",
                    str(output_dir),
                ],
                cwd=checkout,
                env=environment,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                flutter_log.read_text(encoding="utf-8").splitlines(),
                ["pub get", "build windows --release --verbose"],
            )
            staged_pubspec = staged_pubspec_log.read_text(encoding="utf-8")
            self.assertIn("hooks:\n  user_defines:\n    connectanum_client:\n", staged_pubspec)
            self.assertIn("CONNECTANUM_NATIVE_LIB:", staged_pubspec)
            self.assertIn("dependency_overrides:", staged_pubspec)
            self.assertIn(
                (checkout / "packages/connectanum_client").as_posix(), staged_pubspec
            )
            self.assertIn(
                (checkout / "packages/connectanum_core").as_posix(), staged_pubspec
            )
            self.assertEqual(
                (client / "pubspec.yaml").read_text(encoding="utf-8"), source_pubspec
            )
            self.assertFalse(
                (checkout / "out/wamp-app-build/windows").exists(),
                "the disposable Windows build copy should be removed",
            )
            native_path = Path(native_path_log.read_text(encoding="utf-8").strip())
            self.assertTrue(native_path.is_file())
            self.assertIn("wamp-app-native", native_path.parts)
            self.assertIn("v3.0.0-beta.2", dart_log.read_text(encoding="utf-8"))
            self.assertTrue(next(output_dir.glob("*.tar.gz")).is_file())

    def test_workflow_builds_and_uploads_every_platform_target(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")

        for target in ("web", "android", "ios", "macos", "linux", "windows", "server"):
            with self.subTest(target=target):
                self.assertIn(f"target: {target}", workflow)
        self.assertIn("flutter-version: 3.47.1", workflow)
        self.assertIn("fail-fast: false", workflow)
        self.assertIn("bin/package-wamp-app", workflow)
        self.assertIn("bin/wamp-app-production-validate", workflow)
        self.assertIn("name: Production benchmark gates", workflow)
        self.assertIn("wamp-app-production-benchmark-artifacts", workflow)
        for source in (
            "packages/connectanum_client/hook/build.dart",
            "packages/connectanum_client/lib/src/native_release_installer.dart",
            "packages/connectanum_client/tool/install_native.dart",
        ):
            with self.subTest(trigger=source):
                self.assertIn(f"- '{source}'", workflow)
        self.assertIn("if-no-files-found: error", workflow)
        self.assertIn("actions/upload-artifact@v7", workflow)
        self.assertNotIn("steps.package.outputs.archive_path", workflow)
        for suffix in (".tar.gz", ".tar.gz.sha256", ".manifest.json"):
            with self.subTest(upload_suffix=suffix):
                self.assertIn(
                    "${{ github.workspace }}/out/wamp-app-artifacts/"
                    "${{ steps.package.outputs.artifact_name }}" + suffix,
                    workflow,
                )

    def test_server_binary_help_does_not_require_the_dart_runner(self) -> None:
        entrypoint = SERVER_ENTRYPOINT.read_text(encoding="utf-8")

        self.assertIn("Usage: wamp_app_server --config <path>", entrypoint)
        self.assertNotIn("Usage: dart run wamp_app_server", entrypoint)

    def test_server_packaging_rejects_a_locally_modified_config(self) -> None:
        packager = PACKAGER.read_text(encoding="utf-8")

        self.assertIn("git -C \"$(repo_root)\" diff --quiet HEAD --", packager)
        self.assertIn("Refusing to package a locally modified server YAML", packager)


if __name__ == "__main__":
    unittest.main()
