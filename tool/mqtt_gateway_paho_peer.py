#!/usr/bin/env python3
"""Independent Paho participant for the gateway JSON-lines benchmark protocol."""
from __future__ import annotations

from collections import Counter
import importlib.metadata
import json
import os
import resource
import ssl
import struct
import sys
import threading
import time

from run_mqtt_benchmark_gate import process_metrics


_BYTE_PATTERN = bytes((i * 31) & 255 for i in range(256))


def payload(size, phase, sequence, sent_us):
    if size < 24:
        raise ValueError('Payload must fit the benchmark header')
    # 31 * 223 == 1 (mod 256): rotate the same pattern without per-byte Python.
    offset = (24 + (phase + sequence) * 223) & 255
    end = offset + size - 24
    body = (_BYTE_PATTERN * ((end + 255) // 256))[offset:end]
    return struct.pack('>IIQQ', 0x43544757, phase, sequence, sent_us) + body


class Measurement:
    def __init__(self, size, ordered=True):
        self.size = size
        self.ordered = ordered
        self.begin(0, 1)

    def begin(self, phase, count):
        if type(phase) is not int or phase < 0 or type(count) is not int or count < 1 or count > 1000000:
            raise ValueError('Invalid phase count')
        self.phase, self.count, self.received = phase, count, 0
        self.seen = bytearray(count)
        self.histogram = Counter()
        self.first_sent, self.last_received = 0, 0
        self.order_errors = 0

    def accept(self, data, received_us):
        if len(data) != self.size or len(data) < 24:
            raise ValueError('Wrong payload length')
        magic, phase, sequence, sent = struct.unpack_from('>IIQQ', data)
        if magic != 0x43544757 or phase != self.phase or sequence >= self.count:
            raise ValueError('Wrong payload identity')
        if self.seen[sequence]:
            raise ValueError('Duplicate delivery')
        if sequence != self.received:
            self.order_errors += 1
            if self.ordered:
                raise ValueError('Out-of-order delivery')
        if data != payload(len(data), phase, sequence, sent):
            raise ValueError('Payload byte mismatch')
        if received_us < sent:
            raise ValueError('Measurement clock regressed')
        self.seen[sequence] = 1
        self.received += 1
        self.histogram[received_us - sent] += 1
        self.first_sent = min(self.first_sent or sent, sent)
        self.last_received = received_us

    def summary(self):
        if self.received != self.count or self.last_received <= self.first_sent:
            raise ValueError('Incomplete measurement')
        return dict(received=self.received, duplicates=0, order_errors=self.order_errors,
                    ordered=self.ordered, payload_bytes=self.size, first_sent_us=self.first_sent,
                    last_received_us=self.last_received,
                    latency_histogram_us=sorted(self.histogram.items()))


class Memory:
    def __init__(self, read_rss=None, read_peak_rss=None):
        self.read_rss = read_rss or (lambda: process_metrics(os.getpid())[1])
        self.read_peak_rss = read_peak_rss or read_rss or (
            lambda: resource.getrusage(resource.RUSAGE_SELF).ru_maxrss * (1 if sys.platform == 'darwin' else 1024))
        self.lock = threading.Lock()
        self.stopped = threading.Event()
        self.begin()
        self.thread = threading.Thread(target=self._poll, daemon=True)
        self.thread.start()

    def begin(self):
        with self.lock:
            self.warm = self.peak = self.read_rss()

    def _poll(self):
        while not self.stopped.wait(.02):
            self.snapshot()

    def snapshot(self):
        with self.lock:
            current = self.read_rss()
            self.peak = max(self.peak, current, self.read_peak_rss())
            return dict(warm_rss_bytes=self.warm, peak_rss_bytes=self.peak,
                        drained_rss_bytes=current)

    def close(self):
        self.stopped.set()
        self.thread.join(timeout=2)


def run(role, config, lines, output, mqtt, *, memory_factory=Memory):
    if role not in ('publisher', 'subscriber'):
        raise ValueError('Unknown Paho role')
    lock = threading.Lock()
    def emit(message):
        with lock:
            output(message)
    connected, subscribed = threading.Event(), threading.Event()
    closing = False
    phase = 0
    measurement = Measurement(config['payload_bytes'], config['path'] != 'wamp_to_mqtt' or config['window'] == 1)
    version = mqtt.MQTTv5 if config['mqtt_version'] == '5' else mqtt.MQTTv311
    websocket = config['transport'] in ('ws', 'wss')
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=f'bench-{role}-{os.getpid()}',
                         protocol=version, transport='websockets' if websocket else 'tcp')
    meter = memory_factory()
    def on_connect(_client, _userdata, _flags, reason, _properties):
        if reason != 0:
            emit(dict(kind='error', message='CONNECT rejected'))
        connected.set()
    def on_subscribe(_client, _userdata, _mid, reasons, _properties):
        if not reasons or any(reason.is_failure for reason in reasons):
            emit(dict(kind='error', message='SUBSCRIBE rejected'))
        subscribed.set()
    def on_disconnect(_client, _userdata, _flags, _reason, _properties):
        if not closing:
            emit(dict(kind='error', message='Unexpected MQTT disconnect'))
    def on_message(_client, _userdata, message):
        try:
            if message.topic != 'bench/gateway':
                raise ValueError('Wrong MQTT topic')
            measurement.accept(message.payload, time.time_ns() // 1000)
            if measurement.received % config['window'] == 0 or measurement.received == measurement.count:
                emit(dict(kind='progress', phase=phase, received=measurement.received))
            if measurement.received == measurement.count:
                emit(dict(kind='received', phase=phase, **measurement.summary(), memory=meter.snapshot()))
        except (ValueError, TypeError) as error:
            emit(dict(kind='error', message=str(error)))
    client.on_connect, client.on_subscribe = on_connect, on_subscribe
    client.on_disconnect, client.on_message = on_disconnect, on_message
    try:
        if websocket:
            client.ws_set_options(path='/mqtt')
        if config['transport'] in ('tls', 'wss'):
            client.tls_set(ca_certs=config['ca_certificate'], cert_reqs=ssl.CERT_REQUIRED,
                           tls_version=ssl.PROTOCOL_TLS_CLIENT)
        client.connect('127.0.0.1', config['port'], 60)
        client.loop_start()
        if not connected.wait(10):
            raise TimeoutError('Paho CONNECT timeout')
        if role == 'subscriber':
            client.subscribe('bench/gateway', qos=0)
            if not subscribed.wait(10):
                raise TimeoutError('Paho SUBSCRIBE timeout')
        emit(dict(kind='ready', pid=os.getpid()))
        iterator = iter(lines)
        for line in iterator:
            command = json.loads(line)
            op = command['op']
            if op == 'begin':
                phase = command['phase']
                measurement.begin(phase, command['count'])
                meter.begin()
                emit(dict(kind='armed', phase=phase))
            elif op == 'sample':
                emit(dict(kind='sampled', memory=meter.snapshot()))
            elif op == 'publish' and role == 'publisher':
                phase, count = command['phase'], command['count']
                measurement.begin(phase, count)
                meter.begin()
                for first in range(0, count, config['window']):
                    end = min(count, first + config['window'])
                    for sequence in range(first, end):
                        result = client.publish('bench/gateway', payload(config['payload_bytes'], phase, sequence, time.time_ns() // 1000), qos=0)
                        result.wait_for_publish(timeout=30)
                        if not result.is_published():
                            raise TimeoutError('Paho publication did not drain')
                    if command.get('flow_control') is not False:
                        credit = json.loads(next(iterator))
                        if credit != dict(op='credit', phase=phase, received=end):
                            raise ValueError('Invalid delivery credit')
                emit(dict(kind='sent', phase=phase, sent=count, memory=meter.snapshot()))
            elif op == 'close':
                closing = True
                client.disconnect()
                client.loop_stop()
                emit(dict(kind='closed', memory=meter.snapshot()))
                return
            else:
                raise ValueError('Unknown Paho worker command')
    finally:
        closing = True
        try:
            client.disconnect()
        finally:
            try:
                client.loop_stop()
            finally:
                meter.close()


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 2:
        raise ValueError('Expected Paho role and JSON profile')
    if importlib.metadata.version('paho-mqtt') != '2.1.0':
        raise ValueError('Paho version changed; rebaseline required')
    import paho.mqtt.client as mqtt
    run(args[0], json.loads(args[1]), sys.stdin,
        lambda message: print(json.dumps(message), flush=True), mqtt)


if __name__ == '__main__':
    main()
