"""Discover existing VM observers only inside an owned Linux process subtree."""
from dataclasses import dataclass, field
import ipaddress
import json
import os
from pathlib import Path
import urllib.parse


@dataclass(frozen=True)
class ProcessIdentity:
    parent: int
    start_ticks: int


@dataclass(frozen=True)
class VmServiceTarget:
    role: str
    pid: int
    observer_pid: int
    driver_pid: int
    identity: ProcessIdentity
    observer_identity: ProcessIdentity
    driver_identity: ProcessIdentity
    uri: str = field(repr=False)


def process_identity(pid, proc_root):
    if type(pid) is not int or pid <= 0:
        raise ValueError("invalid process identifier")
    raw = (Path(proc_root) / str(pid) / "stat").read_text(errors="replace")
    begin, end = raw.find("("), raw.rfind(")")
    if begin < 0 or end <= begin or int(raw[:begin].strip()) != pid:
        raise ValueError("invalid process identity record")
    fields = raw[end + 1:].split()
    if len(fields) < 20:
        raise ValueError("short process identity record")
    return ProcessIdentity(int(fields[1]), int(fields[19]))


def owned_processes(driver_pid, proc_root, limit=128):
    root = Path(proc_root)
    identity = process_identity(driver_pid, root)
    found = {driver_pid: identity}
    pending = [driver_pid]
    while pending:
        pid = pending.pop()
        try:
            if process_identity(pid, root) != found[pid]:
                continue
            for task in sorted((root / str(pid) / "task").iterdir()):
                if not task.name.isdigit():
                    continue
                try:
                    children = (task / "children").read_text().split()
                except (FileNotFoundError, ProcessLookupError):
                    continue
                for value in children:
                    if not value.isdigit() or int(value) <= 0:
                        raise ValueError("invalid child process record")
                    child = int(value)
                    if child in found:
                        continue
                    try:
                        stamp = process_identity(child, root)
                    except (FileNotFoundError, ProcessLookupError):
                        continue
                    if stamp.parent != pid:
                        continue
                    if len(found) >= limit:
                        raise ValueError("owned process discovery limit exceeded")
                    found[child] = stamp
                    pending.append(child)
        except (FileNotFoundError, ProcessLookupError):
            continue
    if process_identity(driver_pid, root) != identity:
        raise ValueError("diagnostic driver identity changed")
    return found


def loopback_service_uri(value):
    if not isinstance(value, str) or any(character.isspace() for character in value):
        raise ValueError("VM service endpoint must be a string")
    parsed = urllib.parse.urlsplit(value)
    if (parsed.scheme != "http" or parsed.username is not None or parsed.password is not None
            or parsed.query or parsed.fragment or not parsed.path.endswith("/")
            or parsed.port is None or not 0 < parsed.port < 65536):
        raise ValueError("invalid VM service endpoint")
    if not ipaddress.ip_address(parsed.hostname or "").is_loopback:
        raise ValueError("VM service endpoint is not loopback")
    return value


def identity_matches(target, proc_root):
    try:
        return (process_identity(target.driver_pid, proc_root) == target.driver_identity
                and process_identity(target.pid, proc_root) == target.identity
                and process_identity(target.observer_pid, proc_root) == target.observer_identity)
    except (OSError, ValueError):
        return False


def discover_vm_services(driver_pid, proc_root=Path("/proc")):
    processes = owned_processes(driver_pid, proc_root)
    found = {}
    for observer_pid, stamp in sorted(processes.items()):
        if observer_pid == driver_pid:
            continue
        try:
            argv = [os.fsdecode(arg) for arg in
                    (Path(proc_root) / str(observer_pid) / "cmdline").read_bytes().split(b"\0") if arg]
            if not any(Path(arg).name == "dart_vm_metrics_observer_main.dart" for arg in argv[:-1]):
                continue
            config = json.loads(argv[-1])
            if (not isinstance(config, dict) or type(config.get("pid")) is not int
                    or type(config.get("all_isolates")) is not bool
                    or config["pid"] not in processes or config["pid"] in (driver_pid, observer_pid)):
                continue
            uri = loopback_service_uri(config.get("service_uri"))
            role = "router" if config["all_isolates"] else "worker"
            target = VmServiceTarget(role, config["pid"], observer_pid, driver_pid,
                                     processes[config["pid"]], stamp, processes[driver_pid], uri)
            if identity_matches(target, proc_root):
                found.setdefault((role, target.pid), target)
        except (OSError, ValueError, TypeError):
            continue
    if len(found) > 4:
        raise ValueError("too many owned VM service targets")
    return [found[key] for key in sorted(found)]
