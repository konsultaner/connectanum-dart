"""Forwarding primitives ported unchanged from 7fc4c5d8; no capture entrypoint.

Original source: tool/run_mqtt_ffi_census.py at
7fc4c5d87874691a1d29ace7f40ceca2bcffcab3. The historical driver is unchanged.
"""
import hashlib
import platform
import subprocess
from pathlib import Path

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()



def compile_shim(source, library_dir, destination):
    flags = (["-Wl,-needed_library," + str(library_dir / "libct_ffi.so")]
             if platform.system() == "Darwin" else ["-Wl,--no-as-needed", "-lct_ffi"])
    subprocess.run(["cc", "-std=c11", "-shared", "-fPIC", "-Wall", "-Wextra", "-Werror",
                    str(source), "-L" + str(library_dir), *flags,
                    "-Wl,-rpath," + str(library_dir), "-o", str(destination),
                    *([] if platform.system() == "Darwin" else ["-ldl"])], check=True)



def validate_counts(counts):
    if counts.get("diagnostic_only") is not True:
        raise ValueError("Missing diagnostic label")
    scalars = ["poll_calls", "poll_empty", "poll_errors", "poll_positive", "poll_bytes",
               "send_calls", "send_errors", "send_requested_positive_bytes", "arm_calls"]
    if any(type(counts[k]) is not int or counts[k] < 0 for k in scalars):
        raise ValueError("Invalid counters")
    if counts["poll_calls"] != sum(counts[k] for k in ("poll_empty", "poll_errors", "poll_positive")):
        raise ValueError("Poll result conservation mismatch")
    if counts["size_upper_bounds"] != [64,128,256,512,1024,4096,16384,65536,2147483647]:
        raise ValueError("Histogram bounds changed")
    for key in ["poll_sizes", "send_sizes"]:
        if len(counts[key]) != 9 or any(type(v) is not int or v < 0 for v in counts[key]):
            raise ValueError("Invalid histogram")
    if sum(counts["poll_sizes"]) != counts["poll_positive"] or sum(counts["send_sizes"]) > counts["send_calls"]:
        raise ValueError("Histogram conservation mismatch")
    if counts["send_errors"] > counts["send_calls"]:
        raise ValueError("Send result conservation mismatch")



def validate_row(row, budget):
    count = budget["messages_per_run"]
    fields = {"profile": budget["profile"], "sent": count, "received": count, "received_per_subscriber": [count],
              "duplicates": 0, "warmup": 100, "subscribers": 1,
              "payload_bytes": budget["payload_bytes"], "mqtt_version": budget.get("mqtt_version", "5"),
              "transport": budget.get("transport", "tcp"), "window_messages": budget.get("window_messages", 0),
              "publish_mode": budget.get("publish_mode", "single")}
    if any(row[k] != v for k, v in fields.items()):
        raise ValueError("Full original delivery/body/workload checks failed")



def stop_broker(process):
    """Allow existing stdin shutdown and the atexit counters to complete."""
    if process.stdin is not None and not process.stdin.closed:
        try:
            process.stdin.close()
        except (BrokenPipeError, OSError):
            pass
    try:
        return process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)
        raise
