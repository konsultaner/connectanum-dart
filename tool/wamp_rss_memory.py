"""Optional read-only attribution for owned production benchmark processes."""
import hashlib
import json
from pathlib import Path
import threading
import time
import urllib.parse
import urllib.request

from wamp_stall_vm_services import discover_vm_services, identity_matches, loopback_service_uri
from wamp_stall_linux import bounded_text


def memory_rpc(uri, method):
    if method not in ('getVM', 'getProcessMemoryUsage'):
        raise ValueError('Unsupported memory diagnostic RPC')
    uri = loopback_service_uri(uri)
    with urllib.request.urlopen(urllib.parse.urljoin(uri, method), timeout=1) as response:
        raw = response.read(524289)
    if len(raw) > 524288:
        raise ValueError('Memory RPC exceeds response limit')
    envelope = json.loads(raw)
    if not isinstance(envelope, dict) or 'error' in envelope:
        raise ValueError('Memory RPC failed')
    result = envelope.get('result', envelope)
    expected = 'VM' if method == 'getVM' else 'ProcessMemoryUsage'
    if not isinstance(result, dict) or result.get('type') != expected:
        raise ValueError('Memory RPC returned unexpected type')
    return result


def validate_memory_tree(root):
    # Bucket names may change. Sizes include children; never sum ancestors and
    # descendants. SDK heap capacity/Used buckets are not live-heap measurements.
    if not isinstance(root, dict) or type(root.get('size')) is not int or root['size'] <= 0:
        raise ValueError('Invalid VM memory root size')
    pending = [(root, 0)]
    count = 0
    while pending:
        node, depth = pending.pop()
        count += 1
        if count > 512 or depth > 16:
            raise ValueError('Memory tree exceeds diagnostic limits')
        if (not isinstance(node, dict) or not isinstance(node.get('name'), str)
                or type(node.get('size')) is not int or not isinstance(node.get('children'), list)):
            raise ValueError('Invalid VM memory bucket')
        pending.extend((child, depth + 1) for child in node['children'])
    return count


def capture_owned_memory(driver_pid, row, proc_root=Path('/proc')):
    expected = {'worker': row['client_process_metrics']['pid'], 'router': row['server_process_metrics']['pid']}
    if (any(type(pid) is not int or pid <= 0 for pid in expected.values())
            or len(set(expected.values())) != 2):
        raise ValueError('Invalid memory observation process identities')
    targets = discover_vm_services(driver_pid, proc_root)
    if len(targets) != 2 or {target.role for target in targets} != set(expected):
        raise ValueError('Expected one owned router and worker memory endpoint')
    result = {'scope': 'non-atomic read-only process maps and standard VM memory buckets; never acceptance',
              'observed_after_workload': row['workload'], 'started_at_unix_seconds': time.time(), 'roles': {}}
    for target in targets:
        result['roles'][target.role] = capture_target_memory(target, driver_pid, expected[target.role], proc_root)
    result['status'] = 'failed' if any('error' in role for role in result['roles'].values()) else 'complete'
    result['completed_at_unix_seconds'] = time.time()
    return result


def capture_target_memory(target, driver_pid, expected_pid, proc_root=Path('/proc')):
    record = {'pid': target.pid, 'start_ticks': target.identity.start_ticks,
              'observer_pid': target.observer_pid, 'observer_start_ticks': target.observer_identity.start_ticks,
              'driver_pid': driver_pid, 'driver_start_ticks': target.driver_identity.start_ticks,
              'parent_pid': target.identity.parent, 'observer_parent_pid': target.observer_identity.parent}
    try:
        if (target.driver_pid != driver_pid or target.pid != expected_pid
                or not identity_matches(target, proc_root)):
            raise ValueError('Owned memory process identity does not match report')
        vm = memory_rpc(target.uri, 'getVM')
        if type(vm.get('pid')) is not int or vm['pid'] != target.pid:
            raise ValueError('Memory VM endpoint PID does not match owner')
        usage = memory_rpc(target.uri, 'getProcessMemoryUsage')
        count = validate_memory_tree(usage.get('root'))
        maps = bounded_text(Path(proc_root) / str(target.pid) / 'smaps', 8 * 1024 * 1024)
        if not maps.strip():
            raise ValueError('Owned memory maps are empty')
        if not identity_matches(target, proc_root):
            raise ValueError('Owned memory process identity changed during observation')
        record.update(process_memory_usage=usage, bucket_count=count, linux_smaps=maps)
    except Exception as error:
        record['error'] = type(error).__name__
    return record


class MemoryAttribution:
    """Observe complete report boundaries while the unchanged driver continues."""
    def __init__(self, process, output, policy):
        self.process, self.output = process, output
        warmups, measured = policy['minimum_warmup_runs'], policy['minimum_repetitions']
        if type(warmups) is not int or warmups < 1 or type(measured) is not int or measured < 2:
            raise ValueError('Memory attribution requires distinct warmup and pre-final report stages')
        total = warmups + measured
        self.stages = {warmups: 'after_warmup_report', total - 1: 'before_last_report'}
        self.stop = threading.Event()
        self.snapshots, self.errors = {}, []
        self.thread = threading.Thread(target=self.observe, daemon=True)
        self.thread.start()

    def observe(self):
        try:
            self.read_reports()
        except Exception as error:
            # HTTP exceptions may contain private service URIs. Retain types,
            # not exception strings, and keep partial snapshots for inspection.
            self.errors.append(type(error).__name__)

    def read_reports(self):
        path = self.output / 'reports.jsonl'
        while not path.is_file():
            if self.stop.wait(0.05) or self.process.poll() is not None:
                return
        with path.open('rb') as stream:
            count = 0
            while not self.stop.is_set():
                position = stream.tell()
                line = stream.readline(8 * 1024 * 1024 + 1)
                if len(line) > 8 * 1024 * 1024:
                    raise ValueError('Report row exceeds memory observer limit')
                if not line.endswith(b'\n'):
                    stream.seek(position)
                    if self.process.poll() is not None or self.stop.wait(0.05):
                        return
                    continue
                row = json.loads(line)
                count += 1
                if count in self.stages:
                    stage = self.stages[count]
                    try:
                        snapshot = capture_owned_memory(self.process.pid, row)
                    except Exception as error:
                        snapshot = {'status': 'failed', 'error': type(error).__name__,
                                    'scope': 'owned memory discovery failed; no zero-value evidence'}
                    snapshot['after_complete_report_count'] = count
                    snapshot['report_line_sha256'] = hashlib.sha256(line).hexdigest()
                    snapshot['observed_report_completed_at_ms'] = row.get('completed_at_ms')
                    name = f'memory-{stage}.json'
                    (self.output / name).write_text(json.dumps(snapshot, indent=2) + '\n')
                    self.snapshots[stage] = name
                    if snapshot['status'] != 'complete':
                        self.errors.append(f'{stage}: memory observation failed')

    def finish(self):
        self.stop.set()
        self.thread.join(timeout=8)
        if self.thread.is_alive():
            self.errors.append('Memory observer did not stop')
        missing = sorted(set(self.stages.values()) - self.snapshots.keys())
        return {'status': 'failed' if self.errors or missing else 'complete',
                'snapshots': self.snapshots, 'errors': self.errors, 'missing_stages': missing,
                'thread_stopped': not self.thread.is_alive()}
