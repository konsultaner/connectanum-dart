import json
import os
import pathlib
import stat
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin" / "run-wamp-app-lab"


class RunWampAppLabTests(unittest.TestCase):
    def run_script(self, *arguments: str, devices: list[dict] | None = None):
        if devices is None:
            devices = [
                {
                    "name": "Android Emulator",
                    "id": "emulator-5554",
                    "isSupported": True,
                    "targetPlatform": "android-arm64",
                    "emulator": True,
                },
                {
                    "name": "iPhone Simulator",
                    "id": "ios-simulator",
                    "isSupported": True,
                    "targetPlatform": "ios",
                    "emulator": True,
                },
            ]
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = pathlib.Path(temporary_directory)
            flutter = temporary / "flutter"
            flutter.write_text(
                "#!/usr/bin/env bash\n"
                "if [[ \"$1\" == devices && \"$2\" == --machine ]]; then\n"
                f"  printf '%s\\n' '{json.dumps(devices)}'\n"
                "  exit 0\n"
                "fi\n"
                "if [[ \"$1\" == emulators ]]; then\n"
                "  printf '%s\\n' 'fake_android • Fake Android • Google • android'\n"
                "  exit 0\n"
                "fi\n"
                "exit 99\n",
                encoding="utf-8",
            )
            flutter.chmod(flutter.stat().st_mode | stat.S_IXUSR)
            environment = os.environ.copy()
            environment["PATH"] = f"{temporary}:{environment['PATH']}"
            return subprocess.run(
                [str(SCRIPT), *arguments],
                cwd=ROOT,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
            )

    def test_dry_run_resolves_router_and_both_emulators(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            state = pathlib.Path(temporary_directory) / "does-not-exist"
            result = self.run_script(
                "--dry-run",
                "--port",
                "18081",
                "--state-dir",
                str(state),
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(state.exists())
        self.assertIn("endpoint: ws://localhost:18081/ws", result.stdout)
        self.assertIn("Android emulator: emulator-5554", result.stdout)
        self.assertIn("iOS simulator: ios-simulator", result.stdout)
        self.assertIn("--no-resident", result.stdout)
        self.assertEqual(result.stdout.count("WAMP_APP_SERVER_ADDRESS="), 2)

    def test_dry_run_rejects_physical_devices(self):
        result = self.run_script(
            "--dry-run",
            "--android-device",
            "physical-android",
            devices=[
                {
                    "name": "Phone",
                    "id": "physical-android",
                    "isSupported": True,
                    "targetPlatform": "android-arm64",
                    "emulator": False,
                }
            ],
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not a running supported emulator", result.stderr)

    def test_dry_run_plans_boot_when_no_emulator_is_running(self):
        result = self.run_script("--dry-run", devices=[])

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Android AVD to boot: fake_android", result.stdout)
        self.assertIn("iOS simulator: boot the default simulator", result.stdout)

    def test_relative_state_directory_is_resolved_from_repo_root(self):
        result = self.run_script(
            "--dry-run",
            "--state-dir",
            ".dart_tool/custom-wamp-app-lab",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            f"state: {ROOT}/.dart_tool/custom-wamp-app-lab",
            result.stdout,
        )

    def test_android_selector_cannot_resolve_an_ios_device(self):
        result = self.run_script(
            "--dry-run",
            "--android-device",
            "ios-simulator",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not a running supported emulator", result.stderr)

    def test_invalid_port_fails_before_device_discovery(self):
        result = self.run_script("--dry-run", "--port", "80")

        self.assertEqual(result.returncode, 2)
        self.assertIn("between 1024 and 65535", result.stderr)

    def test_android_selectors_are_mutually_exclusive(self):
        result = self.run_script(
            "--dry-run",
            "--android-device",
            "emulator-5554",
            "--android-emulator",
            "fake_android",
        )

        self.assertEqual(result.returncode, 2)
        self.assertIn("mutually exclusive", result.stderr)


if __name__ == "__main__":
    unittest.main()
