#!/usr/bin/env python3
"""Matched live gateway benchmarks with exact delivery and per-process memory."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
from pathlib import Path
import queue
import signal
import statistics
import ssl
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
            or matrix == 'smoke']
    result.extend(paho)
    return result


def overload_profiles():
    return [dict(id='overload-'+link, transport=link, mqtt_version=mqtt,
                 serializer=serializer, payload_bytes=65536, subscribers=2,
                 window=16, mqtt_client='connectanum')
            for link,mqtt,serializer in [('tcp','5','cbor'),('wss','3.1.1','flatbuffers')]]


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
    check_drained_queues(queues, path)
    deliveries = count * profile['subscribers']
    return dict(profile=profile['id'], path=path, run=run, sent=count,
                subscribers=profile['subscribers'], received=deliveries, duplicates=0,
                drops=0,load_disconnects=0,errors=0,
                duration_seconds=duration, delivered_per_sec=deliveries / duration,
                payload_mib_per_sec=deliveries * profile['payload_bytes'] / duration / 1048576,
                p50_us=percentile(histogram, .50), p95_us=percentile(histogram, .95),
                p99_us=percentile(histogram, .99), processes=processes, queues=queues)


def check_drained_queues(queues, path):
    if path in PATHS:
        for key in ('state_subscriptions', 'state_pending_invocations', 'active_connections'):
            if type(queues[key]) is not int or queues[key] != 0:
                raise ValueError(f'Router did not release {key} after disconnect')
        owned = int(path in DIRECTIONS)
        if any(type(queues[key]) is not int or queues[key] != owned for key in ('state_sessions','state_registrations')):
            raise ValueError('Router retained client sessions or registrations')
    if path in ('mqtt_to_wamp', 'wamp_to_mqtt'):
        for key in ('pending_bytes', 'pending_operations', 'pending_policy_futures', 'broker_pending_bytes', 'broker_pending_tasks', 'broker_outbound_bytes', 'broker_connected_peers', 'cancellation_listeners', 'errors', 'denied'):
            if type(queues[key]) is not int or queues[key] != 0:
                raise ValueError(f'Gateway did not drain {key}')


def check_publications(queues,path,count):
    own = 'mqtt_publications' if path == 'mqtt_to_wamp' else 'wamp_publications'
    other = 'wamp_publications' if path == 'mqtt_to_wamp' else 'mqtt_publications'
    if any(type(queues[key]) is not int or queues[key] != expected for key,expected in [(own,count),(other,0)]):
        raise ValueError('Gateway publication counters indicate loss or a translation loop')


def process_summary(samples):
    result = {}
    for role in samples[0]['processes']:
        readings = [row['processes'][role] for row in samples]
        population = sum(row['received'] if role == 'broker' else row['slow_received']
                         if role == 'subscriber-1' and 'slow_received' in row else row['sent'] for row in samples)
        result[role] = dict(
            cpu_seconds_per_million_messages=sum(p['cpu_seconds'] for p in readings) * 1_000_000 / population if population else None,
            warm_rss_bytes=statistics.median(p['warm_rss_bytes'] for p in readings),
            peak_rss_bytes=max(p['peak_rss_bytes'] for p in readings),
            drained_rss_bytes=max(p['drained_rss_bytes'] for p in readings),
            retained_bytes=max(0, max(p['drained_rss_bytes']-p['warm_rss_bytes'] for p in readings)),
        )
    return result


def coefficient_of_variation(values):
    mean = statistics.mean(values)
    return statistics.pstdev(values)/mean if mean else 0


def translation_checks(result, budget):
    checks = dict(
        rate_repeatability=result['max_rate_cv'] <= budget['max_rate_cv'],
        p99_repeatability=result['max_p99_cv'] <= budget['max_p99_cv'],
        cpu_repeatability=result['max_cpu_cv'] <= budget['max_cpu_cv'],
        absolute_throughput=result['delivered_per_sec'] >= budget['min_delivered_per_sec'],
        absolute_p95=result['p95_us'] <= budget['max_p95_us'],
        absolute_p99=result['p99_us'] <= budget['max_p99_us'],
        absolute_cpu=result['broker_cpu_seconds_per_million'] <= budget['max_broker_cpu_seconds_per_million'],
        throughput=result['throughput_ratio'] >= budget['min_throughput_ratio'],
        p95=result['p95_over_control_sum'] <= budget['max_p95_over_control_sum'],
        p99=result['p99_over_control_sum'] <= budget['max_p99_over_control_sum'],
        cpu=result['cpu_over_control_sum'] <= budget['max_cpu_over_control_sum'],
        peak_rss=result['peak_rss_bytes'] <= budget['max_peak_rss_bytes'],
        drained_rss=result['drained_rss_bytes'] <= budget['max_drained_rss_bytes'],
        retained_growth=result['retained_growth_bytes'] <= budget['max_retained_growth_bytes'],
        lifecycle_slope=result['rss_growth_bytes_per_cycle'] <= budget['max_rss_growth_bytes_per_cycle'],
    )
    for role, process in result['processes'].items():
        limits = budget['processes']['subscriber' if role.startswith('subscriber-') else role]
        for field in ('peak_rss_bytes','drained_rss_bytes','retained_bytes','cpu_seconds_per_million_messages'):
            checks[f'{role}_{field}'] = process[field] <= limits['max_'+field]
    return checks


def overload_checks(result, limits):
    checks = dict(throughput=result['delivered_per_sec'] >= limits['min_delivered_per_sec'],
                  p99=result['p99_us'] <= limits['max_p99_us'],
                  retained_growth=result['retained_growth_bytes'] <= limits['max_retained_growth_bytes'])
    for role, process in result['processes'].items():
        for field in ('peak_rss_bytes','drained_rss_bytes','retained_bytes'):
            checks[f'{role}_{field}'] = process[field] <= limits['processes'][role]['max_'+field]
    return checks


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
            control_p99 = med(PATHS[0], 'p99_us') + med(wamp_control, 'p99_us')
            number(control_p99, 'control p99 latency', positive=True)
            peak = max(row['processes']['broker']['peak_rss_bytes'] for row in samples[direction])
            drains = [row['processes']['broker']['drained_rss_bytes'] for row in samples[direction]]
            result = dict(profile=profile['id'], direction=direction,
                          delivered_per_sec=med(direction, 'delivered_per_sec'),
                          payload_mib_per_sec=med(direction, 'payload_mib_per_sec'),
                          p50_us=med(direction, 'p50_us'), p95_us=med(direction, 'p95_us'), p99_us=med(direction, 'p99_us'),
                          broker_cpu_seconds_per_million=cpu(direction),
                          peak_rss_bytes=peak, drained_rss_bytes=max(drains),
                          retained_growth_bytes=max(0, max(drains) - drains[0]),
                          rss_growth_bytes_per_cycle=max(0, statistics.linear_regression(range(len(drains)),drains).slope) if len(drains)>1 else 0,
                          processes=process_summary(samples[direction]),
                          throughput_ratio=med(direction, 'delivered_per_sec') / control_rate,
                          p95_over_control_sum=med(direction, 'p95_us') / control_latency,
                          p99_over_control_sum=med(direction, 'p99_us') / control_p99,
                          cpu_over_control_sum=cpu(direction) / control_cpu)
            matched = ('mqtt_to_mqtt',wamp_control,direction)
            result['max_rate_cv'] = max(coefficient_of_variation([r['delivered_per_sec'] for r in samples[path]]) for path in matched)
            result['max_p99_cv'] = max(coefficient_of_variation([r['p99_us'] for r in samples[path]]) for path in matched)
            result['max_cpu_cv'] = max(coefficient_of_variation([r['processes']['broker']['cpu_seconds']/r['received'] for r in samples[path]]) for path in matched)
            if budgets is not None:
                checks = translation_checks(result,budgets['profiles'][profile['id']][direction])
                result['checks'],result['passed'] = checks,all(checks.values())
            output.append(result)
    return output


def summarize_overload(rows, expected_profiles, runs, budgets=None):
    expected = {(p['id'], d, run) for p in expected_profiles for d in DIRECTIONS for run in range(1,runs+1)}
    indexed = {(r['profile'],r['path'],r['run']):r for r in rows}
    if len(indexed) != len(rows) or set(indexed) != expected:
        raise ValueError('Incomplete or duplicate overload lifecycle matrix')
    output = []
    for profile in expected_profiles:
        for direction in DIRECTIONS:
            samples = [indexed[profile['id'],direction,run] for run in range(1,runs+1)]
            for row in samples:
                if row['slow_received'] >= row['sent'] or row['recovery_received'] != 64:
                    raise ValueError('Overload did not disconnect and recover')
                for process in row['processes'].values():
                    check_memory(process)
                check_drained_queues(row['queues'],direction)
                check_drained_queues(row['recovery_queues'],direction)
            drains = [r['processes']['broker']['drained_rss_bytes'] for r in samples]
            result = dict(profile=profile['id'],direction=direction,
                          delivered_per_sec=statistics.median(r['delivered_per_sec'] for r in samples),
                          p95_us=statistics.median(r['p95_us'] for r in samples),
                          p99_us=statistics.median(r['p99_us'] for r in samples),
                          stalled_peak_rss_bytes=max(r['stalled_peak_rss_bytes'] for r in samples),
                          processes=process_summary(samples),
                          retained_growth_bytes=max(0,max(drains)-drains[0]),
                          slow_received_max=max(r['slow_received'] for r in samples),
                          recovery_received=64)
            if budgets is not None:
                checks = overload_checks(result,budgets['overload'][profile['id']][direction])
                result['checks'],result['passed'] = checks,all(checks.values())
            output.append(result)
    return output


class Child:
    def __init__(self, label, command, events, output, env):
        self.label, self.closing = label, False
        self.log = (output / f'{label}.stderr.log').open('a')
        self.stdout_log = (output / f'{label}.stdout.jsonl').open('a')
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
        if self.process.returncode != 0:
            raise RuntimeError(f'{self.label} exited with code {self.process.returncode} during cleanup')


class Campaign:
    def __init__(self, worker, output, config, *, timeout=60, load_timeout=None):
        self.worker, self.output, self.config = worker, output, config
        self.timeout = timeout
        self.load_timeout = timeout if load_timeout is None else load_timeout
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

    def event(self, deadline=None, *, expected_disconnect=None):
        deadline = time.monotonic() + self.timeout if deadline is None else deadline
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError('Benchmark phase exceeded its deadline')
            label, message = self.events.get(timeout=remaining)
            kind = message['kind']
            if kind == 'eof' and (label not in self.children or self.children[label].closing):
                continue
            if (kind == 'error' and label == expected_disconnect and
                    message.get('message') == 'MqttProtocolException: MQTT connection closed'):
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
        deadline = time.monotonic() + self.load_timeout
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

    def settle(self, seconds):
        """Keep listeners alive long enough to reject late duplicates/errors."""
        if seconds <= 0:
            return
        try:
            label,message = self.event(time.monotonic()+seconds)
        except (queue.Empty,TimeoutError):
            return
        raise ValueError(f'Unexpected event after complete delivery {label}: {message}')

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
            self.settle(drain_seconds)
            closed = self.close_clients(clients)
            for label, message in closed.items():
                processes[label]['drained_rss_bytes'] = message['memory']['drained_rss_bytes']
                processes[label]['peak_rss_bytes'] = max(processes[label]['peak_rss_bytes'], message['memory']['peak_rss_bytes'])
            time.sleep(drain_seconds)
            server.send(dict(op='sample'))
            final = self.expect(['broker'], 'sampled')['broker']
            processes['broker'].update(final['memory'])
            if path in DIRECTIONS:
                check_publications(final['queues'],path,run*(warmup+count))
            row = delivery_row(profile, path, run, count, list(reports.values()), processes, final['queues'])
            rows.append(row)
            with raw_path.open('a') as raw:
                raw.write(json.dumps(row) + '\n')
        return rows

    def run_overload(self, profile, path, runs, count, stall_ms, drain_seconds):
        """Stall one application isolate; the healthy recipient remains exact."""
        self.config.update(path=path, reference=False)
        server = self.spawn('broker', 'server')
        ready = self.expect(['broker'], 'ready')['broker']
        server.measurement_pid = ready['pid']
        self.config['port'] = ready['port']
        rows = []
        for run in range(1, runs+1):
            clients = ['publisher', 'subscriber-0', 'subscriber-1']
            labels = ['broker', *clients]
            for label in clients:
                self.spawn(label, 'publisher' if label == 'publisher' else 'subscriber')
            self.expect(clients, 'ready')
            self.phase(run*3, 64, clients, server)
            phase = run*3+1
            for label in labels:
                self.children[label].send(dict(op='begin', phase=phase, count=count))
            self.expect(labels, 'armed')
            self.children['subscriber-1'].send(dict(op='stall', milliseconds=stall_ms))
            self.expect(['subscriber-1'], 'stalled')
            before = {label: reference.process_metrics(self.children[label].measurement_pid)[0] for label in labels}
            self.children['publisher'].send(dict(op='publish', phase=phase, count=count))
            fast, slow, sent, resumed = None, None, False, False
            progress = dict.fromkeys(('subscriber-0','subscriber-1'), 0)
            stalled_rss = []
            deadline = time.monotonic()+self.timeout
            while fast is None or slow is None or not sent or not resumed:
                label, message = self.event(deadline, expected_disconnect='subscriber-1')
                kind = message['kind']
                if message.get('phase') != phase:
                    raise ValueError('Overload worker phase mismatch')
                if kind == 'progress' and label in progress:
                    value = message['received']
                    if type(value) is not int or not progress[label] < value <= count:
                        raise ValueError('Invalid overload delivery progress')
                    progress[label] = value
                    if label == 'subscriber-0':
                        self.children['publisher'].send(dict(op='credit', phase=phase, received=value))
                        if not resumed:
                            stalled_rss.append(reference.process_metrics(self.children['subscriber-1'].measurement_pid)[1])
                elif kind == 'sent' and label == 'publisher' and message['sent'] == count and not sent:
                    sent = True
                elif kind == 'received' and label == 'subscriber-0' and fast is None:
                    fast = message
                elif kind == 'disconnected' and label == 'subscriber-1' and slow is None:
                    slow = message
                elif kind == 'resumed' and label == 'subscriber-1' and not resumed:
                    resumed = True
                else:
                    raise ValueError(f'Unexpected overload event {label}: {message}')
            if not stalled_rss or not 0 <= slow['received'] < count:
                raise ValueError('Stalled consumer did not hit bounded disconnect')
            cpu = {label: reference.process_metrics(self.children[label].measurement_pid)[0]-before[label] for label in labels}
            for label in labels:
                self.children[label].send(dict(op='sample'))
            samples = self.expect(labels, 'sampled')
            processes = {label:dict(sample['memory'], cpu_seconds=cpu[label]) for label,sample in samples.items()}
            self.settle(drain_seconds)
            closed = self.close_clients(clients)
            for label, sample in closed.items():
                processes[label].update(sample['memory'])
            time.sleep(drain_seconds)
            server.send(dict(op='sample'))
            drained = self.expect(['broker'], 'sampled')['broker']
            check_drained_queues(drained['queues'],path)
            check_publications(drained['queues'],path,run*(count+128)-64)
            processes['broker'].update(drained['memory'])
            # Reuse exact delivery validation for the healthy recipient.
            healthy = delivery_row(dict(profile,subscribers=1),path,run,count,[fast],
                                   {k:v for k,v in processes.items() if k != 'subscriber-1'},drained['queues'])
            for label in ['publisher','subscriber-0']:
                self.spawn(label,'publisher' if label == 'publisher' else 'subscriber')
            self.expect(['publisher','subscriber-0'],'ready')
            reports, _ = self.phase(run*3+2,64,['publisher','subscriber-0'],server)
            self.settle(drain_seconds)
            self.close_clients(['publisher','subscriber-0'])
            time.sleep(drain_seconds)
            server.send(dict(op='sample'))
            final = self.expect(['broker'],'sampled')['broker']
            check_drained_queues(final['queues'],path)
            check_publications(final['queues'],path,run*(count+128))
            if reports['subscriber-0']['received'] != 64:
                raise ValueError('Overload recovery delivery mismatch')
            row = dict(healthy,processes=processes,slow_received=slow['received'],
                       load_disconnects=1,slow_disconnected=True,
                       stalled_peak_rss_bytes=max(stalled_rss),recovery_received=64,
                       recovery_queues=final['queues'])
            rows.append(row)
            with (self.output/'raw.jsonl').open('a') as raw:
                raw.write(json.dumps(row)+'\n')
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


def shard_profiles(items, shard):
    index,total = (int(value) for value in shard.split('/'))
    if not 1 <= total <= 32 or not 0 <= index < total:
        raise ValueError('Invalid benchmark shard')
    return items[index::total]


def validate_budget(budget, args):
    if budget['schema_version'] != 1 or len(budget['baseline_source_commit']) != 40:
        raise ValueError('Invalid gateway baseline provenance')
    if sys.platform != budget['platform']:
        raise ValueError('Numeric gateway budgets require their recorded platform; use record-only for diagnostics')
    for field in ('runs','messages','warmup','overload_runs','overload_messages','overload_stall_ms','drain_seconds'):
        minimum = number(budget['workload'][field],field,positive=True)
        if getattr(args,field) < minimum:
            raise ValueError(f'Gate workload is below its accepted {field}')
    if args.matrix != 'release':
        raise ValueError('Strict gates require the complete release profile inventory')
    for group,inventory in [('profiles',profiles('release')),('overload',overload_profiles())]:
        if set(budget[group]) != {p['id'] for p in inventory}:
            raise ValueError('Budget/profile inventory mismatch')
        for directions in budget[group].values():
            if set(directions) != set(DIRECTIONS):
                raise ValueError('Budget direction inventory mismatch')
            for limits in directions.values():
                for key,value in limits.items():
                    if key == 'processes':
                        required = {'broker','publisher','subscriber'} if group == 'profiles' else {'broker','publisher','subscriber-0','subscriber-1'}
                        if set(value) != required:
                            raise ValueError('Budget process inventory mismatch')
                        for fields in value.values():
                            metrics = ('max_peak_rss_bytes','max_drained_rss_bytes','max_retained_bytes')
                            if group == 'profiles':
                                metrics += ('max_cpu_seconds_per_million_messages',)
                            for metric in metrics:
                                number(fields[metric],metric)
                    else:
                        number(value,key)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--worker', type=Path)
    parser.add_argument('--paho-python', default=os.environ.get('PAHO_PYTHON', sys.executable))
    parser.add_argument('--mosquitto', default='mosquitto')
    parser.add_argument('--matrix', choices=('smoke', 'release'), default='smoke')
    parser.add_argument('--profile')
    parser.add_argument('--shard',default='0/1',help='Zero-based index/count; CI runs every shard on separate runners')
    parser.add_argument('--runs', type=int, default=5)
    parser.add_argument('--messages', type=int, default=5000)
    parser.add_argument('--warmup', type=int, default=200)
    parser.add_argument('--overload-runs', type=int, default=3)
    parser.add_argument('--overload-messages', type=int, default=2048)
    parser.add_argument('--overload-stall-ms', type=int, default=20000)
    parser.add_argument('--drain-seconds', type=float, default=.5)
    parser.add_argument('--record-only', action='store_true')
    parser.add_argument('--budget', type=Path, default=ROOT / 'tool/mqtt_gateway_benchmark_budgets.json')
    args = parser.parse_args(argv)
    configured_library = os.environ.get('CONNECTANUM_NATIVE_LIB')
    if not configured_library:
        parser.error('Set CONNECTANUM_NATIVE_LIB to the native router library')
    library = Path(configured_library).resolve()
    try:
        selected = shard_profiles([p for p in profiles(args.matrix) if args.profile is None or p['id'] == args.profile],args.shard)
        overload_selected = shard_profiles(overload_profiles(),args.shard)
    except ValueError as error:
        parser.error(str(error))
    if not library.is_file() or not selected or args.runs < 1 or args.messages < 1 or args.warmup < 1 or args.drain_seconds < 0 or args.overload_runs < 1 or args.overload_messages < 1 or not 1 <= args.overload_stall_ms <= 60000:
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
    if budget is not None:
        validate_budget(budget,args)
    args.output.mkdir(parents=True, exist_ok=True)
    rows, overload_rows = [], []
    with tempfile.TemporaryDirectory() as temporary:
        worker = args.worker.resolve() if args.worker else compile_worker(Path(temporary))
        environment = {'schema_version': 2, 'diagnostic_only': args.record_only,
                       'peak_rss_scope':'process_lifetime_high_water',
                       'native_outbound_queue_frames':64,
                       'observe_publisher_disconnects':True,'quiescence_before_disconnect':True,
                       'allocation_bytes_per_delivery':None,
                       'allocation_measurement':'not_exposed_by_release_runtime',
                       'paho_payload_oracle':'periodic_bytes_c_comparison','paho_tcp_nodelay':True,
                       'profiles': selected,'overload_profiles':overload_selected, 'source_commit': source_commit, 'source_dirty': source_dirty,
                       'workload': dict(matrix=args.matrix,shard=args.shard, runs=args.runs, messages=args.messages,
                                        warmup=args.warmup, drain_seconds=args.drain_seconds,load_timeout_seconds=300,
                                        overload_runs=args.overload_runs,overload_messages=args.overload_messages,
                                        overload_stall_ms=args.overload_stall_ms),
                       'worker_build': 'unverified_override' if args.worker else 'dart_build_cli_current_source',
                       'python_version': sys.version,
                       'dart_version': subprocess.check_output(['dart', '--version'], text=True).strip(),
                       'platform': sys.platform,'system':platform.platform(),'architecture':platform.machine(),
                       'logical_cpus':os.cpu_count(),'openssl_version':ssl.OPENSSL_VERSION,
                       'runner_image':os.environ.get('ImageOS'),'runner_image_version':os.environ.get('ImageVersion'),
                       'tls_ca_sha256':hashlib.sha256(reference.TLS_CA.read_bytes()).hexdigest(),
                       'mosquitto_version': reference.mosquitto_version(args.mosquitto),
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
                          'certificate': str(reference.TLS_CERT), 'ca_certificate':str(reference.TLS_CA), 'key': str(reference.TLS_KEY)}
                campaign = Campaign(worker, output, config,load_timeout=300)
                try:
                    values = campaign.run(profile, path, args.runs, args.messages, args.warmup, args.drain_seconds)
                    rows.extend(values)
                    print(f"{profile['id']} {path}: {len(values)} exact lifecycles completed",flush=True)
                    (output / 'raw.jsonl').write_text(''.join(json.dumps(row) + '\n' for row in values))
                finally:
                    campaign.close()
        summary = summarize(rows, selected, args.runs, budget)
        for profile in overload_selected:
            for direction in DIRECTIONS:
                output = args.output / profile['id'] / direction
                output.mkdir(parents=True,exist_ok=True)
                config = dict(profile,path=direction,port=0,native_library=str(library),
                              paho_python=args.paho_python,certificate=str(reference.TLS_CERT),ca_certificate=str(reference.TLS_CA),key=str(reference.TLS_KEY))
                campaign = Campaign(worker,output,config,timeout=90)
                try:
                    overload_rows.extend(campaign.run_overload(profile,direction,args.overload_runs,
                                         args.overload_messages,args.overload_stall_ms,args.drain_seconds))
                    print(f"{profile['id']} {direction}: slow-peer isolation and recovery completed",flush=True)
                finally:
                    campaign.close()
        overload = summarize_overload(overload_rows,overload_selected,args.overload_runs,budget)
        result = dict(environment, results=summary,overload=overload)
        (args.output / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')
        for row in [*summary,*overload]:
            verdict = 'MEASURED' if budget is None else 'PASS' if row['passed'] else 'FAIL: '+', '.join(k for k,v in row['checks'].items() if not v)
            peak = row['processes']['broker']['peak_rss_bytes']
            print(f"{row['profile']} {row['direction']}: {row['delivered_per_sec']:.0f}/s, p95 {row['p95_us']:.0f} us, broker peak {peak/1048576:.1f} MiB; {verdict}", flush=True)
        return int(budget is not None and not all(row['passed'] for row in [*summary,*overload]))


if __name__ == '__main__':
    raise SystemExit(main())
