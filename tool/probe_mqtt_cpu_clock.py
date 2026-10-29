"""Linux CPU-clock calibration only; does not alter MQTT budgets or gates."""
import ctypes
import errno
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import time


api = ctypes.CDLL(None).clock_getcpuclockid
api.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
api.restype = ctypes.c_int


def process_clock(pid):
    clock = ctypes.c_int()
    error = api(pid, ctypes.byref(clock))
    if error:
        raise OSError(error, os.strerror(error))
    return clock.value


def ticks_ns(pid):
    fields = Path(f"/proc/{pid}/stat").read_text().rsplit(") ", 1)[1].split()
    return (int(fields[11]) + int(fields[12])) * 1_000_000_000 // hz


child_source = """
import sys,threading,time
def work():
    started=time.thread_time_ns()
    while time.thread_time_ns()-started < 5_000_000:
        pass
print('ready',flush=True)
for line in sys.stdin:
    if line.strip()=='stop':break
    thread=threading.Thread(target=work)
    thread.start()
    thread.join()
    print('done',flush=True)
"""

assert sys.platform == "linux"
hz = os.sysconf("SC_CLK_TCK")
rows = []
child = subprocess.Popen([sys.executable, "-c", child_source], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
try:
    assert child.stdout.readline().strip() == "ready"
    clock = process_clock(child.pid)
    resolution = time.clock_getres(clock)
    for index in range(30):
        before_ns = time.clock_gettime_ns(clock)
        before_ticks = ticks_ns(child.pid)
        child.stdin.write("work\n")
        child.stdin.flush()
        assert child.stdout.readline().strip() == "done"
        after_ticks = ticks_ns(child.pid)
        after_ns = time.clock_gettime_ns(clock)
        precise = after_ns - before_ns
        ticks = after_ticks - before_ticks
        assert precise >= 4_900_000, (index, precise)
        assert ticks >= 0
        rows.append({"iteration": index + 1, "workerTargetNs": 5_000_000,
                     "processCpuClockNs": precise, "procStatCpuNs": ticks,
                     "differenceNs": ticks - precise})
    child.stdin.write("stop\n")
    child.stdin.flush()
    child.communicate(timeout=10)
    assert child.returncode == 0
    try:
        process_clock(child.pid)
    except OSError as error:
        assert error.errno == errno.ESRCH, error
    else:
        raise AssertionError("reaped child unexpectedly has a process clock")
finally:
    if child.poll() is None:
        child.kill()
        child.communicate(timeout=10)

assert any(row["procStatCpuNs"] == 0 for row in rows)
assert any(row["processCpuClockNs"] % (1_000_000_000 // hz) != 0 for row in rows)
print(json.dumps({"diagnosticOnly": True, "platform": platform.platform(),
                  "cpuModel": next(line.split(":", 1)[1].strip()
                                   for line in Path("/proc/cpuinfo").read_text().splitlines()
                                   if line.startswith("model name")),
                  "clockTicksPerSecond": hz, "procStatQuantumNs": 1_000_000_000 // hz,
                  "processCpuClockReportedResolutionSeconds": resolution,
                  "allExitedWorkerThreadsAccounted": True, "reapedChildReportsESRCH": True,
                  "medianProcessCpuClockNs": statistics.median(row["processCpuClockNs"] for row in rows),
                  "maximumAbsoluteDifferenceNs": max(abs(row["differenceNs"]) for row in rows),
                  "rows": rows,
                  "conclusion": "Calibration establishes timer/accounting behavior only, not whether any MQTT gate was misclassified."},
                 indent=2, sort_keys=True))
