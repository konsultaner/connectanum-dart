import json
import os
import pathlib
import socket
import stat
import subprocess
import tempfile
import time
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

    def test_smoke_dry_run_plans_bidirectional_native_ui_test(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            state = pathlib.Path(temporary_directory) / "does-not-exist"
            result = self.run_script(
                "--dry-run",
                "--smoke",
                "--port",
                "18082",
                "--state-dir",
                str(state),
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(state.exists())
        self.assertIn("Two-device UI smoke", result.stdout)
        self.assertEqual(
            result.stdout.count("integration_test/two_device_smoke_test.dart"),
            2,
        )
        self.assertIn("WAMP_APP_SMOKE_USERNAME=android-run-id", result.stdout)
        self.assertIn("WAMP_APP_SMOKE_PEER=ios-run-id", result.stdout)
        self.assertIn("WAMP_APP_SMOKE_USERNAME=ios-run-id", result.stdout)
        self.assertIn("WAMP_APP_SMOKE_PEER=android-run-id", result.stdout)
        self.assertIn("WAMP_APP_SMOKE_OUTBOUND=from-android-run-id", result.stdout)
        self.assertIn("WAMP_APP_SMOKE_INBOUND=from-ios-run-id", result.stdout)
        self.assertIn("WAMP_APP_SMOKE_OUTBOUND=from-ios-run-id", result.stdout)
        self.assertIn("WAMP_APP_SMOKE_INBOUND=from-android-run-id", result.stdout)
        self.assertIn("WAMP_APP_SMOKE_ROLE=initiator", result.stdout)
        self.assertIn("WAMP_APP_SMOKE_ROLE=responder", result.stdout)
        self.assertEqual(
            result.stdout.count("WAMP_APP_SMOKE_GROUP_TITLE=native-group-run-id"),
            2,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_GROUP_OUTBOUND=group-from-android-run-id",
            result.stdout,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_GROUP_INBOUND=group-from-ios-run-id",
            result.stdout,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_GROUP_OUTBOUND=group-from-ios-run-id",
            result.stdout,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_GROUP_INBOUND=group-from-android-run-id",
            result.stdout,
        )
        self.assertEqual(
            result.stdout.count(
                "WAMP_APP_SMOKE_VIEW_ONCE=view-once-from-android-run-id"
            ),
            2,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_CALL_READY_OUTBOUND=voice-ready-android-run-id",
            result.stdout,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_CALL_READY_INBOUND=voice-ready-ios-run-id",
            result.stdout,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_CALL_READY_OUTBOUND=voice-ready-ios-run-id",
            result.stdout,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_CALL_READY_INBOUND=voice-ready-android-run-id",
            result.stdout,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_VIDEO_READY_OUTBOUND=video-ready-android-run-id",
            result.stdout,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_VIDEO_READY_INBOUND=video-ready-ios-run-id",
            result.stdout,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_VIDEO_READY_OUTBOUND=video-ready-ios-run-id",
            result.stdout,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_VIDEO_READY_INBOUND=video-ready-android-run-id",
            result.stdout,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_PROFILE_STATUS=profile-status-android-run-id",
            result.stdout,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_PROFILE_STATUS=profile-status-ios-run-id",
            result.stdout,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_PEER_PROFILE_STATUS=profile-status-ios-run-id",
            result.stdout,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_PEER_PROFILE_STATUS=profile-status-android-run-id",
            result.stdout,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_CONTROLS_READY_OUTBOUND=controls-ready-android-run-id",
            result.stdout,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_CONTROLS_READY_OUTBOUND=controls-ready-ios-run-id",
            result.stdout,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_CONTROLS_READY_INBOUND=controls-ready-ios-run-id",
            result.stdout,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_CONTROLS_READY_INBOUND=controls-ready-android-run-id",
            result.stdout,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_BACKUP_PASSPHRASE=backup-passphrase-android-run-id",
            result.stdout,
        )
        self.assertIn(
            "WAMP_APP_SMOKE_BACKUP_PASSPHRASE=backup-passphrase-ios-run-id",
            result.stdout,
        )
        self.assertEqual(
            result.stdout.count(
                "WAMP_APP_SMOKE_RICH_MEDIA=rich-media-from-android-run-id"
            ),
            2,
        )
        self.assertEqual(
            result.stdout.count(
                "WAMP_APP_SMOKE_RICH_MEDIA_ACK=rich-media-opened-ios-run-id"
            ),
            2,
        )
        self.assertEqual(result.stdout.count("android.permission.RECORD_AUDIO"), 1)
        self.assertEqual(result.stdout.count("android.permission.CAMERA"), 1)
        self.assertIn("simctl privacy ios-simulator grant microphone", result.stdout)
        self.assertIn("simctl privacy ios-simulator grant camera", result.stdout)
        self.assertEqual(result.stdout.count("--timeout 22m"), 2)
        self.assertNotIn("--no-resident", result.stdout)

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

    def test_smoke_failure_forces_router_exit_and_removes_reverse(self):
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            port = reservation.getsockname()[1]

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = pathlib.Path(temporary_directory)
            state = temporary / "state"
            adb_log = temporary / "adb.log"
            runtime_tmp_log = temporary / "runtime-tmp.log"
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
            commands = {
                "uname": (
                    "#!/usr/bin/env bash\n"
                    "[[ \"$1\" == -s ]] && printf '%s\\n' Darwin && exit 0\n"
                    "exit 99\n"
                ),
                "flutter": (
                    "#!/usr/bin/env bash\n"
                    "if [[ \"$1\" == devices && \"$2\" == --machine ]]; then\n"
                    f"  printf '%s\\n' '{json.dumps(devices)}'\n"
                    "  exit 0\n"
                    "fi\n"
                    "if [[ \"$1\" == pub && \"$2\" == get ]]; then exit 0; fi\n"
                    "if [[ \"$1\" == build && \"$2\" == apk ]]; then\n"
                    "  mkdir -p build/app/outputs/flutter-apk\n"
                    "  : >build/app/outputs/flutter-apk/app-debug.apk\n"
                    "  exit 0\n"
                    "fi\n"
                    "if [[ \"$1\" == build && \"$2\" == ios ]]; then\n"
                    "  mkdir -p build/ios/iphonesimulator/Runner.app\n"
                    "  exit 0\n"
                    "fi\n"
                    "if [[ \"$1\" == test ]]; then\n"
                    "  printf '%s\\n' '00:00 +0: exchanges encrypted chat, rich media, controls, backup, and WebRTC calls'\n"
                    "  [[ \" $* \" == *\" -d emulator-5554 \"* ]] && exit 7\n"
                    "  exit 0\n"
                    "fi\n"
                    "exit 99\n"
                ),
                "dart": (
                    "#!/usr/bin/env bash\n"
                    "if [[ \"$1\" == pub && \"$2\" == get ]]; then exit 0; fi\n"
                    "if [[ \"$1\" == run && \"$2\" == wamp_app_server ]]; then\n"
                    "  printf '%s\\n' \"$TMPDIR\" >\"$WAMP_APP_TEST_TMPDIR_LOG\"\n"
                    "  config=\"$4\"\n"
                    "  port=$(awk '/^  port:/ {print $2; exit}' \"$config\")\n"
                    "  exec python3 - \"$port\" <<'PY'\n"
                    "import signal\n"
                    "import socket\n"
                    "import sys\n"
                    "import time\n"
                    "signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
                    "with socket.socket() as listener:\n"
                    "    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)\n"
                    "    listener.bind(('127.0.0.1', int(sys.argv[1])))\n"
                    "    listener.listen()\n"
                    "    while True:\n"
                    "        time.sleep(1)\n"
                    "PY\n"
                    "fi\n"
                    "exit 99\n"
                ),
                "adb": (
                    "#!/usr/bin/env bash\n"
                    "printf '%s\\n' \"$*\" >>\"$WAMP_APP_TEST_ADB_LOG\"\n"
                ),
                "xcrun": (
                    "#!/usr/bin/env bash\n"
                    "if [[ \"$1\" == simctl && \"$2\" == get_app_container ]]; then\n"
                    "  exit 0\n"
                    "fi\n"
                    "if [[ \"$1\" == simctl && \"$2\" == privacy ]]; then\n"
                    "  exit 0\n"
                    "fi\n"
                    "if [[ \"$1\" == simctl && \"$2\" == install ]]; then\n"
                    "  exit 0\n"
                    "fi\n"
                    "exit 99\n"
                ),
            }
            for name, source in commands.items():
                command = temporary / name
                command.write_text(source, encoding="utf-8")
                command.chmod(command.stat().st_mode | stat.S_IXUSR)

            environment = os.environ.copy()
            environment["PATH"] = f"{temporary}:{environment['PATH']}"
            environment["WAMP_APP_TEST_ADB_LOG"] = str(adb_log)
            environment["WAMP_APP_TEST_TMPDIR_LOG"] = str(runtime_tmp_log)
            started = time.monotonic()
            result = subprocess.run(
                [
                    str(SCRIPT),
                    "--smoke",
                    "--port",
                    str(port),
                    "--state-dir",
                    str(state),
                ],
                cwd=ROOT,
                env=environment,
                text=True,
                capture_output=True,
                check=False,
                timeout=20,
            )

            self.assertLess(time.monotonic() - started, 15)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("two-device UI smoke failed", result.stderr)
            adb_calls = adb_log.read_text(encoding="utf-8")
            self.assertIn("reverse tcp:", adb_calls)
            self.assertIn("reverse --remove tcp:", adb_calls)
            self.assertEqual(
                runtime_tmp_log.read_text(encoding="utf-8").strip(),
                str(state / "runtime-tmp"),
            )
            with socket.socket() as released:
                released.bind(("127.0.0.1", port))


if __name__ == "__main__":
    unittest.main()
