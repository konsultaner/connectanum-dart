"""Executable forwarding controls for the diagnostic shim, without network data."""
import ctypes
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from run_mqtt_ffi_census import compile_shim, validate_counts, validate_row, verify_inputs, stop_broker

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
        (self.root / "source-run.json").write_text(json.dumps({"id": 41351945654, "head_sha": "0" * 40, "run_attempt": 1}))
        with self.assertRaisesRegex(ValueError, "source/run/attempt"):
            verify_inputs(self.root)
        (self.root / "source-run.json").write_text(json.dumps({"id": 41351945654, "head_sha": "1152116064651ee01bd6fd52a798fee975d954bf", "run_attempt": 2}))
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


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--child": child(sys.argv[2])
    else: unittest.main()
