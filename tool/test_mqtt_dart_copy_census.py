"""Executable forwarding controls for the diagnostic shim, without network data."""
import ctypes
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from copy import deepcopy
from types import SimpleNamespace
from unittest.mock import patch
import textwrap

import run_mqtt_dart_copy_census as census

from mqtt_copy_census_support import compile_shim, validate_counts, validate_row, stop_broker
from run_mqtt_dart_copy_census import verify_inputs

SOURCE = Path(__file__).with_name("mqtt_ffi_census.c")
FAKE = r'''
#include <stdint.h>
#include <errno.h>
#include <stddef.h>
static int32_t wanted, sends, arms, last_connection, last_length;
static const uint8_t *last_pointer;
void fake_result(int32_t result) { wanted = result; }
int32_t ct_poll_mqtt_chunk(int32_t id, uint8_t *out, int32_t capacity) {
  last_connection = id; last_length = capacity;
  if (wanted > 0 && wanted <= capacity)
    for (int32_t i = 0; i < wanted; i++) out[i] = (uint8_t)(i ^ 122);
  errno = EAGAIN;
  return wanted;
}
int32_t ct_send_mqtt_chunk(int32_t id, const uint8_t *bytes, int32_t length) {
  sends++; last_connection = id; last_length = length; last_pointer = bytes;
  errno = EINTR;
  return wanted;
}
#ifndef OMIT_ARM
void ct_arm_message_ready_callback_v1(void) { arms++; }
#endif
int32_t fake_arms(void) { return arms; }
int32_t fake_sends(void) { return sends; }
int32_t fake_connection(void) { return last_connection; }
int32_t fake_length(void) { return last_length; }
uintptr_t fake_pointer(void) { return (uintptr_t)last_pointer; }
int32_t ct_unwrapped_resolution_control(void) { return 37; }
'''


def child(shim):
    import errno
    library = ctypes.CDLL(shim, use_errno=True)
    library.ct_poll_mqtt_chunk.argtypes = [ctypes.c_int32, ctypes.c_void_p, ctypes.c_int32]
    library.ct_send_mqtt_chunk.argtypes = [ctypes.c_int32, ctypes.c_void_p, ctypes.c_int32]
    library.fake_pointer.restype = ctypes.c_size_t
    buffer = (ctypes.c_uint8 * 16)(*([255] * 16))
    for result in [0, -7, 5, 17]:
        library.fake_result(result)
        assert library.ct_poll_mqtt_chunk(91, buffer, 16) == result
        assert ctypes.get_errno() == errno.EAGAIN
        assert library.fake_connection() == 91 and library.fake_length() == 16
    assert list(buffer) == [i ^ 122 for i in range(5)] + [255] * 11
    # Pointer, signed arguments, result and errno must pass through unchanged;
    # validation belongs to the real native implementation, never this shim.
    for result, length in [(0, 5), (-1, 0), (-1, 1048577), (-1, -1)]:
        library.fake_result(result)
        assert library.ct_send_mqtt_chunk(-93, buffer, length) == result
        assert ctypes.get_errno() == errno.EINTR
        assert library.fake_connection() == -93 and library.fake_length() == length
        assert library.fake_pointer() == ctypes.addressof(buffer)
    library.ct_arm_message_ready_callback_v1()
    assert library.fake_arms() == 1 and library.fake_sends() == 4
    assert library.ct_unwrapped_resolution_control() == 37
    real = ctypes.CDLL(str(Path(shim).parent / "libct_ffi.so"))
    address = lambda symbol: ctypes.cast(symbol, ctypes.c_void_p).value
    assert address(library.ct_unwrapped_resolution_control) == address(real.ct_unwrapped_resolution_control)
    assert address(library.ct_poll_mqtt_chunk) != address(real.ct_poll_mqtt_chunk)


class ForwardingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "fake.c").write_text(FAKE)

    def tearDown(self):
        self.temp.cleanup()

    def build(self, omit=False):
        subprocess.run(["cc", "-shared", "-fPIC", "-Wall", "-Wextra", "-Werror",
                        *( ["-DOMIT_ARM"] if omit else [] ), str(self.root / "fake.c"),
                        "-o", str(self.root / "libct_ffi.so")], check=True)
        shim = self.root / "census.so"
        compile_shim(SOURCE, self.root, shim)
        return shim

    def invoke(self, shim, output=True):
        env = os.environ.copy()
        env.pop("CONNECTANUM_MQTT_CENSUS_OUTPUT", None)
        if output: env["CONNECTANUM_MQTT_CENSUS_OUTPUT"] = str(self.root / "counts.json")
        return subprocess.run([sys.executable, __file__, "--child", str(shim)], env=env,
                              capture_output=True, text=True)

    def test_actual_linked_forwarding_arguments_buffers_errno_counts_and_resolution(self):
        result = self.invoke(self.build())
        self.assertEqual(result.returncode, 0, result.stderr)
        counts = json.loads((self.root / "counts.json").read_text())
        expected = dict(diagnostic_only=True, poll_calls=4, poll_empty=1, poll_errors=1,
                        poll_positive=2, poll_bytes=22, send_calls=4, send_errors=3,
                        send_requested_positive_bytes=1048582, arm_calls=1,
                        size_upper_bounds=[64,128,256,512,1024,4096,16384,65536,2147483647],
                        poll_sizes=[2,0,0,0,0,0,0,0,0], send_sizes=[1,0,0,0,0,0,0,0,1])
        self.assertEqual(counts, expected)
        validate_counts(counts)
        with self.assertRaisesRegex(ValueError, "conservation"):
            validate_counts({**counts, "poll_calls": 0})

    def test_missing_real_entry_point_stops_before_capture(self):
        result = self.invoke(self.build(omit=True))
        self.assertEqual(result.returncode, 120)
        self.assertFalse((self.root / "counts.json").exists())

    def test_missing_output_stops_before_capture(self):
        result = self.invoke(self.build(), output=False)
        self.assertEqual(result.returncode, 120)

    def test_existing_counts_never_overwritten(self):
        shim = self.build()
        (self.root / "counts.json").write_text("retained evidence\n")
        result = self.invoke(shim)
        self.assertEqual(result.returncode, 121)
        self.assertEqual((self.root / "counts.json").read_text(), "retained evidence\n")

    def test_wrong_source_and_attempt_rejected_before_binary_loading(self):
        (self.root / "source-run.json").write_text(json.dumps({"id": 41395075328, "head_sha": "0" * 40, "run_attempt": 1}))
        with self.assertRaisesRegex(ValueError, "source/run/attempt"):
            verify_inputs(self.root)
        (self.root / "source-run.json").write_text(json.dumps({"id": 41395075328, "head_sha": "ad48d679b24a371cca37ad9397a64b261008f57c", "run_attempt": 2}))
        with self.assertRaisesRegex(ValueError, "source/run/attempt"):
            verify_inputs(self.root)

    def test_duplicate_or_changed_window_rejected(self):
        budget = {"profile": "fixture", "messages_per_run": 2, "payload_bytes": 128, "window_messages": 512}
        row = dict(profile="fixture", sent=2, received=2, received_per_subscriber=[2], duplicates=0, warmup=100, subscribers=1,
                   payload_bytes=128, mqtt_version="5", transport="tcp", window_messages=512, publish_mode="single")
        validate_row(row, budget)
        for changed in [{"duplicates": 1}, {"window_messages": 256}, {"warmup": 0}]:
            with self.assertRaisesRegex(ValueError, "original delivery"):
                validate_row({**row, **changed}, budget)

    def test_shutdown_uses_existing_stdin_path_and_reaps(self):
        marker = self.root / "closed"
        script = "import sys;from pathlib import Path;sys.stdin.read();Path(sys.argv[1]).write_text('closed')"
        process = subprocess.Popen([sys.executable, "-c", script, str(marker)], stdin=subprocess.PIPE)
        self.assertEqual(stop_broker(process), 0)
        self.assertEqual(marker.read_text(), "closed")


class DeclarationAndConservation(unittest.TestCase):
    def test_fresh_client_is_exact_source_only_and_preserves_delivery_guards(self):
        encoded = (census.probe.ROOT / census.fresh.CLIENT_SOURCE).read_bytes()
        changed = census.fresh.instrument(encoded).decode()
        for marker in ["unexpected warmup publication", "out-of-order publication",
                       "duplicates': duplicate", "await publisher.publish('bench/one', payload)",
                       "fresh_bodies_generated", "mqttCensusBodyMatches"]:
            self.assertIn(marker, changed)
        self.assertNotIn("payload[i] = (i * 29 + 7)", changed)
        self.assertNotIn("data.setUint32", changed)
        with self.assertRaisesRegex(ValueError, "Original client source"):
            census.fresh.instrument(encoded + b"\n")

    def test_manual_copy_mode_is_isolated_and_cannot_cancel_started_capture(self):
        workflow = (census.probe.ROOT / '.github/workflows/mqtt-profile.yml').read_text()
        self.assertIn('cancel-in-progress: false', workflow)
        profile = workflow.split('  profile:', 1)[1].split('  intel:', 1)[0]
        intel = workflow.split('  intel:', 1)[1].split('  dart-copy-census:', 1)[0]
        for block in [profile, intel]:
            self.assertIn("inputs.dart_copy_census_declaration == ''", block)
        block = workflow.split('  dart-copy-census:', 1)[1]
        self.assertIn("github.event_name == 'workflow_dispatch'", block)
        self.assertNotIn('compare_mqtt_native.sh', block)
        script = textwrap.dedent(block.split('run: |', 1)[1].split('      - uses:', 1)[0])
        for env, status in [({}, 0), ({'RECOVER_RUN': '123'}, 1),
                            ({'COMPARE_WORKERS': '2'}, 1), ({'PROBE_INTEL': 'true'}, 1)]:
            result = subprocess.run(['bash', '-c', script], capture_output=True,
                                    env={**os.environ, 'RECOVER_RUN': '', 'COMPARE_WORKERS': '',
                                         'PROBE_INTEL': 'false', **env})
            self.assertEqual(result.returncode, status, result.stderr)

    def declaration(self):
        return {
            "capture_ready": True, "runtime_source": census.probe.SOURCE,
            "source_run": census.SOURCE_RUN, "profiles": list(census.PROFILES),
            "rows_required": 25, "fresh_verified_deliveries_required": 4025000,
            "native_sha256": census.NATIVE, "original_client_witness_sha256": census.CLIENT,
            "client_mode": "fresh-per-publication-v1", "fresh_body_nonce_base": 196000000,
            "tool_revision": "f" * 40,
            "tool_sha256": {n: census.support.digest(census.probe.ROOT / n) for n in census.TOOLS},
            "own_canonical": {"head": "f" * 40, "complete_pass": True,
                              **{n: "d" * 64 for n in ("log_sha256", "receipt_sha256", "native_sha256", "tree_sha256")}},
            "controls_passed": True, "root_review_complete": True,
            "controls_receipt_sha256": "c" * 64, "root_review_sha256": "b" * 64,
        }

    def test_positive_then_adversarial_readiness_and_source_guards(self):
        value = self.declaration()
        def command(args, **kwargs):
            return "f" * 40 + "\n" if args[1] == "rev-parse" else b"" if args[1] == "status" else ""
        with patch.object(census, "subprocess", SimpleNamespace(check_output=command)):
            census.verify_declaration(value)
            for delta in [{"capture_ready": False}, {"rows_required": 24},
                          {"profiles": list(reversed(census.PROFILES))},
                          {"native_sha256": "0" * 64}, {"original_client_witness_sha256": "0" * 64},
                          {"client_mode": "original-reused-body"}, {"fresh_body_nonce_base": 0},
                          {"tool_revision": "0" * 40}, {"tool_sha256": {}},
                          {"own_canonical": {}}, {"controls_passed": False},
                          {"root_review_complete": False}]:
                with self.subTest(delta=delta), self.assertRaises(ValueError):
                    census.verify_declaration({**value, **delta})
        def runtime_change(args, **kwargs):
            return "f" * 40 + "\n" if args[1] == "rev-parse" else b"" if args[1] == "status" else "packages/runtime.dart\n"
        with patch.object(census, "subprocess", SimpleNamespace(check_output=runtime_change)):
            with self.assertRaisesRegex(ValueError, "cannot change runtime"):
                census.verify_declaration(value)

    def test_own_canonical_and_full_controls_required(self):
        value = self.declaration()
        def command(args, **kwargs):
            return "f" * 40 + "\n" if args[1] == "rev-parse" else b"" if args[1] == "status" else ""
        with patch.object(census, "subprocess", SimpleNamespace(check_output=command)):
            for delta in [{"head": "0" * 40}, {"complete_pass": False}, {"native_sha256": ""}]:
                bad = deepcopy(value)
                bad["own_canonical"].update(delta)
                with self.assertRaises(ValueError):
                    census.verify_declaration(bad)

    def test_poll_frame_and_histogram_conservation_rejects_forgery(self):
        ffi = dict(poll_calls=2, poll_positive=2, poll_empty=0, poll_errors=0,
                   poll_bytes=100, send_calls=1, send_errors=0, arm_calls=1,
                   size_upper_bounds=[64,128,256,512,1024,4096,16384,65536,2147483647],
                   poll_sizes=[2,0,0,0,0,0,0,0,0])
        value = {"diagnostic_only": True, "kind": "mqtt_dart_logical_copy_requests",
                 "counts": dict.fromkeys(census.COUNTERS, 0)}
        value["counts"].update(native_poll_copy_requests=2, native_poll_copy_bytes=100,
                              body_constructor_requests=2, body_constructor_requested_bytes=40,
                              zero_body_constructor_requests=1, nonempty_body_copy_requests=1,
                              body_copy_bytes=40, frames_completed=2, completed_body_bytes=40,
                              nonempty_frames_completed=1)
        census.validate_dart_counts(value, ffi)
        # Actual graceful native integration has negative terminal polls. They
        # are retained as errors in the C ledger and do not make Dart copies.
        census.validate_dart_counts(value, {**ffi, "poll_calls": 4, "poll_errors": 2})
        for key, number in [("native_poll_copy_requests", 3), ("native_poll_copy_bytes", 101),
                            ("frames_completed", 3), ("zero_body_constructor_requests", 2),
                            ("completed_body_bytes", 41), ("body_copy_bytes", -1),
                            ("body_constructor_requests", True), ("growth_copy_bytes", 1)]:
            bad = deepcopy(value)
            bad["counts"][key] = number
            with self.subTest(key=key), self.assertRaises(ValueError):
                census.validate_dart_counts(bad, ffi)
        with self.assertRaisesRegex(ValueError, "histogram"):
            census.validate_dart_counts(value, {**ffi, "poll_sizes": [0,2,0,0,0,0,0,0,0]})


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--child":
        child(sys.argv[2])
    else:
        unittest.main()
