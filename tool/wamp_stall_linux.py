"""Bounded Linux observations for an already verified owned VM target."""
from pathlib import Path
import os

from wamp_stall_vm_services import identity_matches
from wamp_stall_tcp_info import capture_tcp_info


def bounded_text(path, limit=2 * 1024 * 1024):
    with path.open() as stream:
        value = stream.read(limit + 1)
    if len(value) > limit:
        raise ValueError("proc record exceeds diagnostic limit")
    return value


def capture_tcp_environment(root, proc_root):
    """Read fixed TCP policy/counters; global values are explicitly separate."""
    result = {'scope': 'read-only observer network namespace policy, host memory and owned network namespace counters',
              'records': {}, 'errors': []}
    paths = {
        'tcp_rmem': proc_root / 'sys/net/ipv4/tcp_rmem',
        'tcp_mem': proc_root / 'sys/net/ipv4/tcp_mem',
        'tcp_moderate_rcvbuf': proc_root / 'sys/net/ipv4/tcp_moderate_rcvbuf',
        'tcp_shrink_window': proc_root / 'sys/net/ipv4/tcp_shrink_window',
        'rmem_default': proc_root / 'sys/net/core/rmem_default',
        'rmem_max': proc_root / 'sys/net/core/rmem_max',
        'memory_pressure': proc_root / 'pressure/memory',
        'namespace_sockstat': root / 'net/sockstat',
    }
    for name, path in paths.items():
        try:
            result['records'][name] = bounded_text(path, 4096).strip()
        except (OSError, ValueError) as error:
            result['errors'].append({'record': name, 'error': type(error).__name__})
    try:
        memory = bounded_text(proc_root / 'meminfo', 16384)
        result['records']['host_memory'] = {
            key: value.strip() for line in memory.splitlines()
            for key, sep, value in [line.partition(':')]
            if sep and key in ('MemTotal', 'MemAvailable', 'SwapTotal', 'SwapFree')}
    except (OSError, ValueError) as error:
        result['errors'].append({'record': 'host_memory', 'error': type(error).__name__})
    return result


def capture_linux_state(target, proc_root=Path('/proc'), application_ports=()):
    if not identity_matches(target, proc_root):
        return {'error': 'owned process identity changed before Linux observation'}
    root = Path(proc_root) / str(target.pid)
    result = {'pid': target.pid, 'start_ticks': target.identity.start_ticks,
              'scope': 'owned process only; non-atomic diagnostic snapshots',
              'threads': [], 'tcp': [], 'errors': []}
    try:
        status = {}
        fields = {'VmRSS', 'VmSize', 'VmData', 'Threads',
                  'voluntary_ctxt_switches', 'nonvoluntary_ctxt_switches'}
        for line in bounded_text(root / 'status').splitlines():
            key, separator, value = line.partition(':')
            if separator and key in fields:
                status[key] = value.strip()
        result['status'] = status
        tasks = sorted((root / 'task').iterdir(), key=lambda p: p.name)
        result['thread_inventory_count'] = len(tasks)
        result['thread_inventory_truncated'] = len(tasks) > 128
        for task in tasks[:128]:
            if not task.name.isdigit():
                continue
            thread = {'tid': int(task.name)}
            try:
                raw = bounded_text(task / 'stat', 16384)
                begin, end = raw.find('('), raw.rfind(')')
                values = raw[end + 1:].split()
                if begin < 0 or end <= begin or len(values) < 20 or int(raw[:begin]) != thread['tid']:
                    raise ValueError('invalid thread stat record')
                thread.update(name=raw[begin + 1:end], state=values[0],
                              user_ticks=int(values[11]), system_ticks=int(values[12]),
                              start_ticks=int(values[19]))
                try:
                    thread['wait_channel'] = bounded_text(task / 'wchan', 4096).strip()
                except OSError as error:
                    thread['wait_channel_error'] = type(error).__name__
            except (OSError, ValueError) as error:
                thread['error'] = type(error).__name__
            result['threads'].append(thread)
        descriptors = sorted((root / 'fd').iterdir(), key=lambda p: p.name)
        result['fd_inventory_count'] = len(descriptors)
        result['fd_inventory_truncated'] = len(descriptors) > 512
        inodes = set()
        for descriptor in descriptors[:512]:
            try:
                link = os.readlink(descriptor)
                if link.startswith('socket:[') and link.endswith(']') and link[8:-1].isdigit():
                    inodes.add(int(link[8:-1]))
            except OSError:
                continue
        result['socket_inode_count'] = len(inodes)
        for family in ('tcp', 'tcp6'):
            try:
                table = bounded_text(root / 'net' / family)
                for line in table.splitlines()[1:]:
                    values = line.split()
                    if len(values) < 10 or not values[9].isdigit() or int(values[9]) not in inodes:
                        continue
                    tx, rx = values[4].split(':')
                    result['tcp'].append({
                        'family': family, 'inode': int(values[9]),
                        'local_hex': values[1], 'remote_hex': values[2],
                        'state_hex': values[3], 'tx_queue_bytes': int(tx, 16),
                        'rx_queue_bytes': int(rx, 16), 'timer_hex': values[5],
                        'retransmits': int(values[6], 16),
                    })
            except (OSError, ValueError) as error:
                result['errors'].append({'record': family, 'error': type(error).__name__})
    except (OSError, ValueError) as error:
        result['errors'].append({'record': 'process', 'error': type(error).__name__})
    if application_ports:
        result['tcp_info'] = capture_tcp_info(target, result['tcp'], application_ports, proc_root)
        result['tcp_environment'] = capture_tcp_environment(root, proc_root)
    if not identity_matches(target, proc_root):
        return {'error': 'owned process identity changed during Linux observation'}
    return result
