"""Independent participant validation, protocol errors and resource cleanup."""
import contextlib
import io
import json
import runpy
import struct
import sys
import threading
import time
import types
import unittest
from unittest import mock

import mqtt_gateway_paho_peer as paho
import mqtt_gateway_reference_server as reference


CONFIG = dict(path='mqtt_to_mqtt', payload_bytes=32, window=2, mqtt_version='5',
              transport='tcp', port=1883, certificate='cert', diagnostic_only=False,
              mosquitto='mosquitto')
MEMORY = dict(warm_rss_bytes=100, peak_rss_bytes=200, drained_rss_bytes=120)


class FakeClient:
    def __init__(self):
        self.sent = []
        self.reason = 0
        self.subscription_failed = False
        self.published = True
        self.closed = self.stopped = 0
    def connect(self, *args): self.address = args
    def loop_start(self): self.on_connect(self, None, {}, self.reason, None)
    def subscribe(self, *args, **kwargs):
        self.on_subscribe(self, None, 1, [types.SimpleNamespace(is_failure=self.subscription_failed)], None)
    def publish(self, topic, payload, **kwargs):
        self.sent.append((topic, payload))
        return types.SimpleNamespace(wait_for_publish=lambda **_: None, is_published=lambda: self.published)
    def disconnect(self):
        self.closed += 1
        self.on_disconnect(self, None, {}, 0, None)
    def loop_stop(self): self.stopped += 1
    def ws_set_options(self, **kwargs): self.websocket = kwargs
    def tls_set(self, **kwargs): self.tls = kwargs


def mqtt(client):
    return types.SimpleNamespace(MQTTv5=5, MQTTv311=311,
        CallbackAPIVersion=types.SimpleNamespace(VERSION2=2), Client=mock.Mock(return_value=client))


def meter():
    return mock.Mock(snapshot=mock.Mock(return_value=MEMORY))


class MeasurementTest(unittest.TestCase):
    def test_exact_binary_header_bytes_order_duplicates_population_and_clock(self):
        measurement = paho.Measurement(32)
        measurement.begin(2, 2)
        with self.assertRaises(ValueError): measurement.summary()
        for value in [b'', paho.payload(32, 1, 0, 100), paho.payload(32, 2, 3, 100)]:
            with self.assertRaises(ValueError): measurement.accept(value, 110)
        bad = bytearray(paho.payload(32, 2, 0, 100)); bad[0] ^= 1
        with self.assertRaises(ValueError): measurement.accept(bad, 110)
        bad = bytearray(paho.payload(32, 2, 0, 100)); bad[31] ^= 1
        with self.assertRaises(ValueError): measurement.accept(bad, 110)
        with self.assertRaises(ValueError): measurement.accept(paho.payload(32, 2, 0, 100), 99)
        with self.assertRaises(ValueError): measurement.accept(paho.payload(32, 2, 1, 100), 110)
        measurement.accept(paho.payload(32, 2, 0, 100), 110)
        with self.assertRaises(ValueError): measurement.accept(paho.payload(32, 2, 0, 100), 110)
        measurement.accept(paho.payload(32, 2, 1, 100), 110)
        self.assertEqual(measurement.summary()['latency_histogram_us'], [(10, 2)])
        unordered = paho.Measurement(24, ordered=False)
        unordered.begin(1, 2)
        unordered.accept(paho.payload(24, 1, 1, 100), 110)
        unordered.accept(paho.payload(24, 1, 0, 90), 120)
        self.assertEqual(unordered.summary()['order_errors'], 2)
        self.assertEqual(unordered.summary()['first_sent_us'], 90)
        short = paho.Measurement(16)
        with self.assertRaises(ValueError): short.accept(bytes(16), 100)
        with self.assertRaises(ValueError): paho.payload(23, 1, 0, 1)
        for phase, count in [(-1, 1), (True, 1), (1, True), (1, 0), (1, 1000001)]:
            with self.assertRaises(ValueError): measurement.begin(phase, count)

    def test_rss_samples_active_peak_and_post_drain_and_stops_its_thread(self):
        sampled = threading.Event()
        values = [100, 250, 120]
        def read():
            value = values.pop(0) if len(values) > 1 else values[0]
            if value == 250: sampled.set()
            return value
        memory = paho.Memory(read)
        try:
            self.assertTrue(sampled.wait(2))
            self.assertEqual(memory.snapshot(), MEMORY | {'peak_rss_bytes': 250})
            memory.begin()
            self.assertEqual(memory.snapshot()['peak_rss_bytes'], 120)
        finally: memory.close()
        self.assertFalse(memory.thread.is_alive())
        real = paho.Memory()
        try: self.assertGreater(real.snapshot()['warm_rss_bytes'], 0)
        finally: real.close()


class PahoParticipantTest(unittest.TestCase):
    def run_peer(self, role, commands, *, client=None, config=None):
        client = client or FakeClient()
        memory = meter()
        output = []
        paho.run(role, config or CONFIG, commands, output.append, mqtt(client), memory_factory=lambda: memory)
        self.assertTrue(client.closed)
        self.assertTrue(client.stopped)
        memory.close.assert_called_once()
        return client, output

    def test_burst_publication_requires_matching_delivery_credits(self):
        client, output = self.run_peer('publisher', map(json.dumps, [
            dict(op='begin', phase=1, count=3), dict(op='publish', phase=1, count=3),
            dict(op='credit', phase=1, received=2), dict(op='credit', phase=1, received=3),
            dict(op='sample'), dict(op='close')]))
        self.assertEqual([event['kind'] for event in output], ['ready','armed','sent','sampled','closed'])
        self.assertEqual(len(client.sent), 3)
        for i, (_, data) in enumerate(client.sent):
            self.assertEqual(struct.unpack_from('>IIQ', data), (0x43544757, 1, i))
        for transport in ['tcp','tls','ws','wss']:
            client, _ = self.run_peer('publisher', [json.dumps(dict(op='publish',phase=1,count=1,flow_control=False))],
                                      config=dict(CONFIG,transport=transport,mqtt_version='3.1.1'))
            if transport in ('ws','wss'): self.assertEqual(client.websocket, {'path':'/mqtt'})
            if transport in ('tls','wss'): self.assertEqual(client.tls['ca_certs'],'cert')

    def test_subscriber_reports_errors_and_exact_fanout_progress(self):
        client = FakeClient()
        def lines():
            yield json.dumps(dict(op='begin',phase=2,count=3))
            client.on_disconnect(client,None,{},1,None)
            client.on_message(client,None,types.SimpleNamespace(topic='wrong',payload=b''))
            client.on_message(client,None,types.SimpleNamespace(topic='bench/gateway',payload=b''))
            for i in range(3):
                client.on_message(client,None,types.SimpleNamespace(topic='bench/gateway',payload=paho.payload(32,2,i,100)))
            yield json.dumps(dict(op='sample'))
            yield json.dumps(dict(op='close'))
        with mock.patch.object(paho.time,'time_ns',return_value=110000):
            _, output = self.run_peer('subscriber',lines(),client=client)
        self.assertEqual(len([e for e in output if e['kind']=='error']),3)
        self.assertEqual([e['received'] for e in output if e['kind']=='progress'],[2,3])
        self.assertEqual(next(e for e in output if e['kind']=='received')['received'],3)

    def test_rejections_timeouts_and_bad_controls_still_stop_resources(self):
        for role, commands, client in [
            ('publisher',[dict(op='unknown')],FakeClient()),
            ('subscriber',[dict(op='publish')],FakeClient()),
            ('publisher',[dict(op='publish',phase=1,count=1),dict(op='credit',phase=2,received=1)],FakeClient()),
            ('publisher',[dict(op='publish',phase=1,count=1,flow_control=False)],FakeClient()),
        ]:
            if commands[-1].get('flow_control') is False: client.published=False
            memory=meter()
            with self.assertRaises((ValueError,TimeoutError)):
                paho.run(role,CONFIG,map(json.dumps,commands),lambda _:None,mqtt(client),memory_factory=lambda:memory)
            memory.close.assert_called_once()
        with self.assertRaises(ValueError): paho.run('unknown',CONFIG,[],lambda _:None,mqtt(FakeClient()))
        for connection in [True,False]:
            client=FakeClient(); memory=meter()
            events=[mock.Mock(wait=mock.Mock(return_value=connection)),mock.Mock(wait=mock.Mock(return_value=False))]
            with mock.patch.object(paho.threading,'Event',side_effect=events),self.assertRaises(TimeoutError):
                paho.run('subscriber',CONFIG,[],lambda _:None,mqtt(client),memory_factory=lambda:memory)
            memory.close.assert_called_once()
        client=FakeClient(); client.reason=1; client.subscription_failed=True
        _, output=self.run_peer('subscriber',[],client=client)
        self.assertEqual([e['message'] for e in output if e['kind']=='error'],['CONNECT rejected','SUBSCRIBE rejected'])

    def test_cli_pins_the_independent_library_and_handles_the_real_entrypoint(self):
        for args in [[],['subscriber']]:
            with self.assertRaises(ValueError): paho.main(args)
        with mock.patch.object(paho.importlib.metadata,'version',return_value='changed'),self.assertRaises(ValueError):
            paho.main(['subscriber','{}'])
        fake=types.ModuleType('paho'); parent=types.ModuleType('paho.mqtt'); client=types.ModuleType('paho.mqtt.client')
        fake.mqtt=parent; parent.client=client
        with (mock.patch.dict(sys.modules,{'paho':fake,'paho.mqtt':parent,'paho.mqtt.client':client}),
              mock.patch.object(paho.importlib.metadata,'version',return_value='2.1.0'),
              mock.patch.object(paho,'run',side_effect=lambda role,config,lines,emit,mqtt:emit({'kind':'ready'})),
              contextlib.redirect_stdout(io.StringIO()) as output):
            paho.main(['subscriber','{}'])
        self.assertIn('ready',output.getvalue())
        with mock.patch.object(sys,'argv',['mqtt_gateway_paho_peer.py']),self.assertRaises(ValueError):
            runpy.run_path(str(reference.__file__).replace('reference_server','paho_peer'),run_name='__main__')


class ReferenceParticipantTest(unittest.TestCase):
    def test_reference_protocol_uses_the_actual_broker_pid_and_pins_version(self):
        for commands in [[],[dict(op='begin',phase=1),dict(op='sample'),dict(op='close')],[dict(op='unknown')]]:
            with self.subTest(commands=commands):
                memory=meter(); output=[]; broker=mock.Mock(pid=1234)
                with (mock.patch.object(reference.reference,'mosquitto_version',return_value='mosquitto version 2.0.18'),
                      mock.patch.object(reference.reference,'available_port',return_value=1883),
                      mock.patch.object(reference.reference,'wait_for_listener'),
                      mock.patch.object(reference.reference,'stop_broker') as stop,
                      mock.patch.object(reference.reference,'process_metrics',return_value=(1,100,200)),
                      mock.patch.object(reference.subprocess,'Popen',return_value=broker),
                      mock.patch.object(reference,'Memory',side_effect=lambda read_rss:(self.assertEqual(read_rss(),100),memory)[1])):
                    if commands and commands[0]['op']=='unknown':
                        with self.assertRaises(ValueError): reference.run(CONFIG,map(json.dumps,commands),output.append)
                    else: reference.run(CONFIG,map(json.dumps,commands),output.append)
                    self.assertEqual(output[0]['pid'],1234)
                    memory.close.assert_called_once(); stop.assert_called_once_with(broker)
        with mock.patch.object(reference.reference,'mosquitto_version',return_value='changed'),self.assertRaises(ValueError):
            reference.run(CONFIG,[],lambda _:None)
        with (mock.patch.object(reference.reference,'mosquitto_version',return_value='changed'),
              mock.patch.object(reference.subprocess,'Popen') as process,
              mock.patch.object(reference.reference,'wait_for_listener',side_effect=TimeoutError()),
              mock.patch.object(reference.reference,'stop_broker') as stop):
            with self.assertRaises(TimeoutError): reference.run(dict(CONFIG,diagnostic_only=True),[],lambda _:None)
            stop.assert_called_once_with(process.return_value)

    def test_reference_cli_and_entrypoint(self):
        for args in [[],['client','{}']]:
            with self.assertRaises(ValueError): reference.main(args)
        with mock.patch.object(reference,'run',side_effect=lambda config,lines,emit:emit({'kind':'ready'})),contextlib.redirect_stdout(io.StringIO()) as output:
            reference.main(['server','{}'])
        self.assertIn('ready',output.getvalue())
        with mock.patch.object(sys,'argv',['mqtt_gateway_reference_server.py']),self.assertRaises(ValueError):
            runpy.run_path(reference.__file__,run_name='__main__')


if __name__ == '__main__':
    unittest.main()
