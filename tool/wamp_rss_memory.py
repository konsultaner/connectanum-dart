"""Optional read-only attribution for owned production benchmark processes."""
import hashlib
import json
from pathlib import Path
import threading
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

from wamp_stall_vm_services import discover_vm_services, identity_matches, loopback_service_uri
from wamp_stall_linux import bounded_text


ALLOCATOR_METHOD = 'ext.connectanum.diagnosticMallocInfo'


def memory_rpc(uri, method, isolate_id=None):
    types = {'getVM': 'VM', 'getProcessMemoryUsage': 'ProcessMemoryUsage',
             'getMemoryUsage': 'MemoryUsage', ALLOCATOR_METHOD: 'ConnectanumAllocatorDiagnostic'}
    if method not in types:
        raise ValueError('Unsupported memory diagnostic RPC')
    needs_isolate = method in ('getMemoryUsage', ALLOCATOR_METHOD)
    if needs_isolate != (isinstance(isolate_id, str) and isolate_id.startswith('isolates/')):
        raise ValueError('Invalid diagnostic isolate identifier')
    uri = loopback_service_uri(uri)
    url = urllib.parse.urljoin(uri, method)
    if needs_isolate:
        url += '?' + urllib.parse.urlencode({'isolateId': isolate_id})
    with urllib.request.urlopen(url, timeout=1) as response:
        raw = response.read(524289)
    if len(raw) > 524288:
        raise ValueError('Memory RPC exceeds response limit')
    envelope = json.loads(raw)
    if not isinstance(envelope, dict) or 'error' in envelope:
        raise ValueError('Memory RPC failed')
    result = envelope.get('result', envelope)
    if not isinstance(result, dict) or result.get('type') != types[method]:
        raise ValueError('Memory RPC returned unexpected type')
    return result


def validate_allocator_counters(result, expected_pid):
    if (type(result.get('pid')) is not int or result['pid'] != expected_pid
            or not isinstance(result.get('glibc_version'), str)
            or not result['glibc_version'] or len(result['glibc_version']) > 64):
        raise ValueError('Invalid allocator owner/version')
    raw = result.get('malloc_info_xml')
    if (not isinstance(raw, str) or len(raw.encode()) > 524288
            or '<!DOCTYPE' in raw or '<!ENTITY' in raw):
        raise ValueError('Invalid allocator XML')
    root = ET.fromstring(raw)
    if root.tag != 'malloc' or root.attrib != {'version': '1'} or len(list(root.iter())) > 16384:
        raise ValueError('Unsupported allocator XML')
    heaps = root.findall('heap')
    if not heaps or len(heaps) > 512 or len({heap.get('nr') for heap in heaps}) != len(heaps):
        raise ValueError('Invalid allocator arena set')
    def counter(tag, kind):
        # Direct children are all-arena totals. Never add per-arena values again.
        values = root.findall(f"{tag}[@type='{kind}']")
        if len(values) != 1:
            raise ValueError('Missing or duplicate allocator total')
        value = values[0].get('size', '')
        if not value.isascii() or not value.isdigit() or int(value) > 2**64 - 1:
            raise ValueError('Invalid allocator counter')
        return int(value)
    return {'arena_count': len(heaps), 'arena_system_current_bytes': counter('system', 'current'),
            'arena_free_fast_bytes': counter('total', 'fast'), 'arena_free_rest_bytes': counter('total', 'rest'),
            'mmap_bytes': counter('total', 'mmap'),
            'limitations': 'Non-atomic allocator counters, not resident bytes; thread caches are not counted as free bins'}


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


def capture_owned_memory(driver_pid, row, proc_root=Path('/proc'), *, allocator_attribution=False):
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
        result['roles'][target.role] = capture_target_memory(target, driver_pid, expected[target.role], proc_root,
                                                           allocator_attribution=allocator_attribution)
    result['status'] = 'failed' if any('error' in role for role in result['roles'].values()) else 'complete'
    result['completed_at_unix_seconds'] = time.time()
    return result


def capture_target_memory(target, driver_pid, expected_pid, proc_root=Path('/proc'), *, allocator_attribution=False):
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
        allocator = {}
        if allocator_attribution:
            isolates = vm.get('isolates')
            if (not isinstance(isolates, list) or not 1 <= len(isolates) <= 16
                    or any(not isinstance(item, dict) or not isinstance(item.get('id'), str)
                           or not item['id'].startswith('isolates/') for item in isolates)
                    or len({item['id'] for item in isolates}) != len(isolates)):
                raise ValueError('Invalid allocator observation isolate set')
            main = [item['id'] for item in isolates if item.get('name') == 'main']
            if len(main) != 1:
                raise ValueError('Allocator extension requires exactly one main isolate')
            # Preserve group identity; isolates sharing a heap are not additive.
            allocator['isolate_refs'] = isolates
            allocator['isolate_memory_usage'] = {}
            for isolate in isolates:
                sample = memory_rpc(target.uri, 'getMemoryUsage', isolate['id'])
                if any(type(sample.get(key)) is not int or sample[key] < 0
                       for key in ('externalUsage', 'heapUsage', 'heapCapacity')):
                    raise ValueError('Invalid isolate memory usage')
                allocator['isolate_memory_usage'][isolate['id']] = sample
            sample = memory_rpc(target.uri, ALLOCATOR_METHOD, main[0])
            allocator['allocator_counters'] = validate_allocator_counters(sample, target.pid)
            allocator['allocator_diagnostic'] = sample
        maps = bounded_text(Path(proc_root) / str(target.pid) / 'smaps', 8 * 1024 * 1024)
        if not maps.strip():
            raise ValueError('Owned memory maps are empty')
        if not identity_matches(target, proc_root):
            raise ValueError('Owned memory process identity changed during observation')
        record.update(process_memory_usage=usage, bucket_count=count, linux_smaps=maps, **allocator)
    except Exception as error:
        record['error'] = type(error).__name__
    return record


class MemoryAttribution:
    """Observe complete report boundaries while the unchanged driver continues."""
    def __init__(self, process, output, policy, *, allocator_attribution=False):
        self.process, self.output = process, output
        self.allocator_attribution = allocator_attribution
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
                        snapshot = (capture_owned_memory(self.process.pid, row, allocator_attribution=True)
                                    if self.allocator_attribution else capture_owned_memory(self.process.pid, row))
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
