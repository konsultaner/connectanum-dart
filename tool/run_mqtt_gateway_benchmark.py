#!/usr/bin/env python3
"""Matched live gateway benchmarks with exact delivery and per-process memory."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import queue
import signal
import statistics
import subprocess
import sys
import tempfile
import threading
import time

import run_mqtt_benchmark_gate as reference

ROOT = Path(__file__).resolve().parents[1]
PATHS = ('mqtt_to_mqtt', 'wamp_to_wamp', 'wamp_to_wamp_ack', 'mqtt_to_wamp', 'wamp_to_mqtt')
DIRECTIONS = ('mqtt_to_wamp', 'wamp_to_mqtt')
ALL_PATHS = (*PATHS, 'mosquitto')


def profiles(matrix='smoke'):
    result = []
    for link, transport in enumerate(('tcp', 'tls', 'ws', 'wss')):
        for version, mqtt in enumerate(('5', '3.1.1')):
            for size, payload in enumerate((128, 1024, 65536)):
                if matrix == 'smoke' and size != (link + version) % 3:
                    continue
                serializer = ('json', 'msgpack', 'cbor', 'flatbuffers')[(link + version + size) % 4]
                subscribers = (1, 4)[(version + size) % 2]
                window = (1, 16)[(link + size) % 2]
                name = f'{transport}-{mqtt}-{serializer}-{payload}-{subscribers}-{window}'
                result.append(dict(id=name, transport=transport, mqtt_version=mqtt,
                                   serializer=serializer, payload_bytes=payload,
                                   subscribers=subscribers, window=window,
                                   mqtt_client='connectanum'))
    paho = [dict(p, id=p['id'] + '-paho', mqtt_client='paho') for p in result
            if matrix == 'release' and p['payload_bytes'] == (128, 1024, 65536)[
                (('tcp', 'tls', 'ws', 'wss').index(p['transport']) + (p['mqtt_version'] == '3.1.1')) % 3]
            or matrix == 'smoke' and p['transport'] == 'tcp']
    result.extend(paho)
    return result


def number(value, name, *, positive=False):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0 or positive and value == 0:
        raise ValueError(f'Invalid {name}: {value!r}')
    return value


def percentile(histogram, fraction):
    counts = {}
    for latency, count in histogram:
        number(latency, 'latency')
        number(count, 'latency count', positive=True)
        if not isinstance(latency, int) or not isinstance(count, int):
            raise ValueError('Latency histogram requires integral microseconds/counts')
        counts[latency] = counts.get(latency, 0) + count
    wanted = math.ceil(sum(counts.values()) * fraction)
    seen = 0
    for latency, count in sorted(counts.items()):
        seen += count
        if seen >= wanted:
            return latency
    raise ValueError('Empty latency histogram')


def check_memory(memory):
    warm, peak, drained = (number(memory[key], key, positive=True) for key in
                           ('warm_rss_bytes', 'peak_rss_bytes', 'drained_rss_bytes'))
    if peak < max(warm, drained):
        raise ValueError('RSS peak is below a measured phase sample')


def delivery_row(profile, path, run, count, reports, processes, queues):
    if len(reports) != profile['subscribers']:
        raise ValueError('Missing subscriber report')
    histogram = []
    starts, ends = [], []
    ordered = path != 'wamp_to_mqtt' or profile['window'] == 1
    for report in reports:
        if (report['received'] != count or report['duplicates'] != 0 or
                report['payload_bytes'] != profile['payload_bytes'] or
                report['ordered'] != ordered or ordered and report['order_errors'] != 0):
            raise ValueError('Delivery bytes/count/order/duplicate validation failed')
        values = report['latency_histogram_us']
        percentile(values, 0.5)
        if sum(item[1] for item in values) != count:
            raise ValueError('Latency population differs from delivery count')
        histogram.extend(values)
        starts.append(number(report['first_sent_us'], 'first send', positive=True))
        ends.append(number(report['last_received_us'], 'last receive', positive=True))
    duration = (max(ends) - min(starts)) / 1_000_000
    number(duration, 'measurement duration', positive=True)
    required = {'broker', 'publisher', *[f'subscriber-{i}' for i in range(profile['subscribers'])]}
    if set(processes) != required:
        raise ValueError('Missing per-process memory/CPU measurement')
    for process in processes.values():
        check_memory(process)
        number(process['cpu_seconds'], 'process CPU')
    if path in PATHS:
        for key in ('state_subscriptions', 'state_pending_invocations', 'active_connections'):
            if type(queues[key]) is not int or queues[key] != 0:
                raise ValueError(f'Router did not release {key} after disconnect')
        owned = int(path in DIRECTIONS)
        if any(type(queues[key]) is not int or queues[key] != owned for key in ('state_sessions','state_registrations')):
            raise ValueError('Router retained client sessions or registrations')
    if path in ('mqtt_to_wamp', 'wamp_to_mqtt'):
        for key in ('pending_bytes', 'pending_operations', 'pending_policy_futures', 'broker_pending_bytes', 'broker_pending_tasks', 'broker_outbound_bytes', 'broker_connected_peers', 'cancellation_listeners'):
            if type(queues[key]) is not int or queues[key] != 0:
                raise ValueError(f'Gateway did not drain {key}')
    deliveries = count * profile['subscribers']
    return dict(profile=profile['id'], path=path, run=run, sent=count,
                subscribers=profile['subscribers'], received=deliveries, duplicates=0,
                duration_seconds=duration, delivered_per_sec=deliveries / duration,
                payload_mib_per_sec=deliveries * profile['payload_bytes'] / duration / 1048576,
                p50_us=percentile(histogram, .50), p95_us=percentile(histogram, .95),
                p99_us=percentile(histogram, .99), processes=processes, queues=queues)


def summarize(rows, expected_profiles, runs, budgets=None):
    indexed = {}
    for row in rows:
        key = row['profile'], row['path'], row['run']
        if key in indexed:
            raise ValueError('Duplicate benchmark sample')
        indexed[key] = row
    expected = {(p['id'], path, run) for p in expected_profiles for path in ALL_PATHS for run in range(1, runs + 1)}
    if set(indexed) != expected:
        raise ValueError('Incomplete direction/control/profile/run matrix')
    output = []
    for profile in expected_profiles:
        samples = {path: [indexed[profile['id'], path, run] for run in range(1, runs + 1)] for path in ALL_PATHS}
        med = lambda path, metric: statistics.median(row[metric] for row in samples[path])
        cpu = lambda path: statistics.median(row['processes']['broker']['cpu_seconds'] * 1_000_000 / row['received'] for row in samples[path])
        for direction in DIRECTIONS:
            wamp_control = 'wamp_to_wamp_ack' if direction == 'wamp_to_mqtt' else 'wamp_to_wamp'
            control_rate = min(med(PATHS[0], 'delivered_per_sec'), med(wamp_control, 'delivered_per_sec'))
            control_cpu = cpu(PATHS[0]) + cpu(wamp_control)
            number(control_cpu, 'control CPU', positive=True)
            control_latency = med(PATHS[0], 'p95_us') + med(wamp_control, 'p95_us')
            number(control_latency, 'control latency', positive=True)
            peak = max(row['processes']['broker']['peak_rss_bytes'] for row in samples[direction])
            drains = [row['processes']['broker']['drained_rss_bytes'] for row in samples[direction]]
            result = dict(profile=profile['id'], direction=direction,
                          delivered_per_sec=med(direction, 'delivered_per_sec'),
                          payload_mib_per_sec=med(direction, 'payload_mib_per_sec'),
                          p50_us=med(direction, 'p50_us'), p95_us=med(direction, 'p95_us'), p99_us=med(direction, 'p99_us'),
                          broker_cpu_seconds_per_million=cpu(direction),
                          peak_rss_bytes=peak, drained_rss_bytes=max(drains),
                          retained_growth_bytes=max(0, max(drains) - drains[0]),
                          throughput_ratio=med(direction, 'delivered_per_sec') / control_rate,
                          p95_over_control_sum=med(direction, 'p95_us') / control_latency,
                          cpu_over_control_sum=cpu(direction) / control_cpu)
            if budgets is not None:
                budget = budgets['profiles'][profile['id']][direction]
                result['passed'] = (
                    result['throughput_ratio'] >= budget['min_throughput_ratio'] and
                    result['p95_over_control_sum'] <= budget['max_p95_over_control_sum'] and
                    result['cpu_over_control_sum'] <= budget['max_cpu_over_control_sum'] and
                    peak <= budget['max_peak_rss_bytes'] and
                    max(drains) <= budget['max_drained_rss_bytes'] and
                    result['retained_growth_bytes'] <= budget['max_retained_growth_bytes'])
            output.append(result)
    return output


class Child:
    def __init__(self, label, command, events, output, env):
        self.label, self.closing = label, False
        self.log = (output / f'{label}.stderr.log').open('w')
        self.stdout_log = (output / f'{label}.stdout.jsonl').open('w')
        try:
            self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                            stderr=self.log, text=True, bufsize=1, env=env,
                                            start_new_session=os.name == 'posix')
        except BaseException:
            self.log.close()
            self.stdout_log.close()
            raise
        def read():
            try:
                for line in self.process.stdout:
                    try:
                        message = json.loads(line)
                        if not isinstance(message, dict) or not isinstance(message.get('kind'), str):
                            raise ValueError('Invalid worker event')
                        if message.get('kind') != 'progress':
                            self.stdout_log.write(line)
                            self.stdout_log.flush()
                        events.put((label, message))
                    except ValueError:
                        self.stdout_log.write(line)
                        self.stdout_log.flush()
                        events.put((label, {'kind': 'error', 'message': 'Non-JSON worker output'}))
            finally:
                events.put((label, {'kind': 'eof'}))
        self.thread = threading.Thread(target=read, daemon=True)
        self.thread.start()
        self.measurement_pid = self.process.pid

    def send(self, message):
        self.process.stdin.write(json.dumps(message) + '\n')
        self.process.stdin.flush()

    def stop(self):
        self.closing = True
        try:
            self.process.stdin.close()
        except BrokenPipeError:
            pass
        if self.process.poll() is None:
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                if os.name == 'posix':
                    os.killpg(self.process.pid, signal.SIGKILL)
                else:
                    self.process.kill()
                self.process.wait(timeout=5)
        self.thread.join(timeout=2)
        self.process.stdout.close()
        self.log.close()
        self.stdout_log.close()


class Campaign:
    def __init__(self, worker, output, config, *, timeout=60):
        self.worker, self.output, self.config = worker, output, config
        self.timeout = timeout
        self.events = queue.Queue()
        self.children = {}
        self.env = {**os.environ, 'CONNECTANUM_NATIVE_LIB': config['native_library']}
        self.reference_version = None

    def spawn(self, label, role):
        mqtt = self.config['path'].startswith('mqtt') if role == 'publisher' else self.config['path'].endswith('mqtt')
        command = ([self.config['paho_python'], str(ROOT / 'tool/mqtt_gateway_reference_server.py')]
                   if role == 'server' and self.config.get('reference')
                   else [self.config['paho_python'], str(ROOT / 'tool/mqtt_gateway_paho_peer.py')]
                   if role != 'server' and mqtt and self.config['mqtt_client'] == 'paho'
                   else [str(self.worker)])
        child = Child(label, [*command, role, json.dumps(self.config)], self.events, self.output, self.env)
        self.children[label] = child
        return child

    def event(self, deadline=None):
        deadline = time.monotonic() + self.timeout if deadline is None else deadline
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError('Benchmark phase exceeded its deadline')
            label, message = self.events.get(timeout=remaining)
            kind = message['kind']
            if kind == 'eof' and (label not in self.children or self.children[label].closing):
                continue
            if kind in ('error', 'eof'):
                raise RuntimeError(f'{label}: {message}')
            return label, message

    def expect(self, labels, kind):
        result = {}
        deadline = time.monotonic() + self.timeout
        while set(result) != set(labels):
            label, message = self.event(deadline)
            if label not in labels or message['kind'] != kind or label in result:
                raise ValueError(f'Unexpected worker event {label}: {message}')
            result[label] = message
        return result

    def phase(self, phase, count, clients, server):
        labels = [server.label, *clients]
        for label in labels:
            self.children[label].send(dict(op='begin', phase=phase, count=count))
        self.expect(labels, 'armed')
        before = {label: reference.process_metrics(self.children[label].measurement_pid)[0] for label in labels}
        self.children['publisher'].send(dict(op='publish', phase=phase, count=count))
        progress = {label: 0 for label in clients if label.startswith('subscriber')}
        received, sent, credited = {}, False, 0
        deadline = time.monotonic() + self.timeout
        while not sent or len(received) != len(progress):
            label, message = self.event(deadline)
            if message['phase'] != phase:
                raise ValueError('Worker phase mismatch')
            if message['kind'] == 'progress' and label in progress:
                if type(message['received']) is not int or not progress[label] < message['received'] <= count:
                    raise ValueError('Invalid delivery progress')
                progress[label] = message['received']
                minimum = min(progress.values())
                if minimum > credited:
                    self.children['publisher'].send(dict(op='credit', phase=phase, received=minimum))
                    credited = minimum
            elif message['kind'] == 'received' and label in progress:
                if label in received:
                    raise ValueError('Duplicate subscriber completion')
                received[label] = message
            elif label == 'publisher' and message['kind'] == 'sent' and message['sent'] == count:
                sent = True
            else:
                raise ValueError(f'Unexpected load event {label}: {message}')
        cpu = {label: reference.process_metrics(self.children[label].measurement_pid)[0] - before[label] for label in labels}
        for label in labels:
            self.children[label].send(dict(op='sample'))
        samples = self.expect(labels, 'sampled')
        return received, {label: {**sample['memory'], 'cpu_seconds': cpu[label]} for label, sample in samples.items()}

    def close_clients(self, labels):
        for label in labels:
            self.children[label].closing = True
            self.children[label].send(dict(op='close'))
        closed = self.expect(labels, 'closed')
        for label in labels:
            self.children.pop(label).stop()
        return closed

    def run(self, profile, path, runs, count, warmup, drain_seconds):
        self.config['path'] = 'mqtt_to_mqtt' if path == 'mosquitto' else path
        self.config['reference'] = path == 'mosquitto'
        raw_path = self.output / 'raw.jsonl'
        raw_path.write_text('')
        server = self.spawn('broker', 'server')
        ready = self.expect(['broker'], 'ready')['broker']
        server.measurement_pid = ready['pid']
        self.reference_version = ready.get('version')
        self.config['port'] = ready['port']
        rows = []
        for run in range(1, runs + 1):
            clients = ['publisher', *[f'subscriber-{i}' for i in range(profile['subscribers'])]]
            for label in clients:
                self.spawn(label, 'publisher' if label == 'publisher' else 'subscriber')
            self.expect(clients, 'ready')
            self.phase(run * 2, warmup, clients, server)
            reports, processes = self.phase(run * 2 + 1, count, clients, server)
            closed = self.close_clients(clients)
            for label, message in closed.items():
                processes[label]['drained_rss_bytes'] = message['memory']['drained_rss_bytes']
                processes[label]['peak_rss_bytes'] = max(processes[label]['peak_rss_bytes'], message['memory']['peak_rss_bytes'])
            time.sleep(drain_seconds)
            server.send(dict(op='sample'))
            final = self.expect(['broker'], 'sampled')['broker']
            processes['broker'].update(final['memory'])
            row = delivery_row(profile, path, run, count, list(reports.values()), processes, final['queues'])
            rows.append(row)
            with raw_path.open('a') as raw:
                raw.write(json.dumps(row) + '\n')
        return rows

    def close(self):
        failure = None
        for child in self.children.values():
            try:
                child.stop()
            except BaseException as error:
                failure = failure or error
        self.children.clear()
        if failure is not None:
            raise failure


def compile_worker(directory):
    try:
        subprocess.run(['dart', 'build', 'cli', '--target', 'bin/mqtt_gateway_worker.dart', '--output', str(directory)],
                       cwd=ROOT / 'packages/connectanum_bench', check=True, capture_output=True, text=True,
                       env={**os.environ, 'CONNECTANUM_SKIP_NATIVE_BUILD': '1'}, timeout=300)
    except subprocess.CalledProcessError as error:
        raise RuntimeError(f'AOT worker build failed:\n{error.stdout}\n{error.stderr}') from error
    return directory / 'bundle/bin/mqtt_gateway_worker'


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--worker', type=Path)
    parser.add_argument('--paho-python', default=os.environ.get('PAHO_PYTHON', sys.executable))
    parser.add_argument('--mosquitto', default='mosquitto')
    parser.add_argument('--matrix', choices=('smoke', 'release'), default='smoke')
    parser.add_argument('--profile')
    parser.add_argument('--runs', type=int, default=5)
    parser.add_argument('--messages', type=int, default=5000)
    parser.add_argument('--warmup', type=int, default=200)
    parser.add_argument('--drain-seconds', type=float, default=.5)
    parser.add_argument('--record-only', action='store_true')
    parser.add_argument('--budget', type=Path, default=ROOT / 'tool/mqtt_gateway_benchmark_budgets.json')
    args = parser.parse_args(argv)
    configured_library = os.environ.get('CONNECTANUM_NATIVE_LIB')
    if not configured_library:
        parser.error('Set CONNECTANUM_NATIVE_LIB to the native router library')
    library = Path(configured_library).resolve()
    selected = [p for p in profiles(args.matrix) if args.profile is None or p['id'] == args.profile]
    if not library.is_file() or not selected or args.runs < 1 or args.messages < 1 or args.warmup < 1 or args.drain_seconds < 0:
        parser.error('Invalid benchmark library/profile/count/drain configuration')
    if args.profile is not None and not args.record_only:
        parser.error('Partial profile runs are diagnostic only')
    source_commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    source_dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip())
    if not args.record_only and (source_dirty or args.worker is not None):
        parser.error('Strict gates require clean source and a freshly compiled worker')
    if args.output.exists() and any(args.output.iterdir()):
        parser.error('Benchmark output must be empty; preserve earlier evidence')
    budget = None if args.record_only else json.loads(args.budget.read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    rows = []
    with tempfile.TemporaryDirectory() as temporary:
        worker = args.worker.resolve() if args.worker else compile_worker(Path(temporary))
        environment = {'schema_version': 1, 'diagnostic_only': args.record_only,
                       'profiles': selected, 'source_commit': source_commit, 'source_dirty': source_dirty,
                       'workload': dict(matrix=args.matrix, runs=args.runs, messages=args.messages,
                                        warmup=args.warmup, drain_seconds=args.drain_seconds),
                       'worker_build': 'unverified_override' if args.worker else 'dart_build_cli_current_source',
                       'python_version': sys.version,
                       'dart_version': subprocess.check_output(['dart', '--version'], text=True).strip(),
                       'platform': sys.platform, 'mosquitto_version': reference.mosquitto_version(args.mosquitto),
                       'cpu_model': reference.cpu_model(),
                       'native_library_sha256': hashlib.sha256(library.read_bytes()).hexdigest(),
                       'worker_sha256': hashlib.sha256(worker.read_bytes()).hexdigest()}
        (args.output / 'environment.json').write_text(json.dumps(environment, indent=2) + '\n')
        for profile in selected:
            for path in ALL_PATHS:
                output = args.output / profile['id'] / path
                output.mkdir(parents=True, exist_ok=True)
                config = {**profile, 'path': path, 'port': 0, 'native_library': str(library),
                          'paho_python': args.paho_python,
                          'mosquitto': args.mosquitto, 'diagnostic_only': args.record_only,
                          'certificate': str(reference.TLS_CERT), 'key': str(reference.TLS_KEY)}
                campaign = Campaign(worker, output, config)
                try:
                    values = campaign.run(profile, path, args.runs, args.messages, args.warmup, args.drain_seconds)
                    rows.extend(values)
                    (output / 'raw.jsonl').write_text(''.join(json.dumps(row) + '\n' for row in values))
                finally:
                    campaign.close()
        summary = summarize(rows, selected, args.runs, budget)
        result = dict(environment, results=summary)
        (args.output / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')
        for row in summary:
            print(f"{row['profile']} {row['direction']}: {row['delivered_per_sec']:.0f}/s, p95 {row['p95_us']:.0f} us, peak {row['peak_rss_bytes']/1048576:.1f} MiB", flush=True)
        return int(budget is not None and not all(row['passed'] for row in summary))


if __name__ == '__main__':
    raise SystemExit(main())
