"""Fail-closed accounting and orchestration regressions for the gateway gate."""
import copy
import contextlib
import io
import json
import os
import queue
import runpy
import subprocess
import sys
import tempfile
import unittest
from types import SimpleNamespace
from pathlib import Path
from unittest import mock

import run_mqtt_gateway_benchmark as gate


PROFILE = gate.profiles()[0]
MEMORY = dict(warm_rss_bytes=100, peak_rss_bytes=200, drained_rss_bytes=120)
QUEUES = dict.fromkeys(('pending_bytes', 'pending_operations', 'pending_policy_futures',
                       'broker_pending_bytes', 'broker_pending_tasks', 'broker_outbound_bytes',
                       'broker_connected_peers', 'cancellation_listeners',
                       'state_subscriptions', 'state_pending_invocations', 'active_connections'), 0)
QUEUES.update(state_sessions=1,state_registrations=1)


def sample(profile=PROFILE, path='mqtt_to_wamp', run=1):
    reports = [dict(received=2, duplicates=0, payload_bytes=profile['payload_bytes'],
                    ordered=path != 'wamp_to_mqtt' or profile['window'] == 1,
                    order_errors=0, latency_histogram_us=[[10, 1], [20, 1]],
                    first_sent_us=100, last_received_us=200)
               for _ in range(profile['subscribers'])]
    processes = {label: dict(MEMORY, cpu_seconds=.01) for label in
                 ('broker', 'publisher', *[f'subscriber-{i}' for i in range(profile['subscribers'])])}
    queues=dict(QUEUES,state_sessions=int(path in gate.DIRECTIONS),state_registrations=int(path in gate.DIRECTIONS))
    return gate.delivery_row(profile, path, run, 2, reports, processes, queues)


class GatewayAccountingTest(unittest.TestCase):
    def test_matrix_covers_real_directions_controls_and_independent_peers(self):
        for matrix, count in [('smoke', 10), ('release', 32)]:
            profiles = gate.profiles(matrix)
            self.assertEqual(len(profiles), count)
            self.assertEqual(len({p['id'] for p in profiles}), count)
            self.assertEqual({p['transport'] for p in profiles}, {'tcp', 'tls', 'ws', 'wss'})
            self.assertEqual({p['mqtt_version'] for p in profiles}, {'5', '3.1.1'})
            self.assertEqual({p['serializer'] for p in profiles}, {'json', 'cbor', 'msgpack', 'flatbuffers'})
            self.assertEqual({p['payload_bytes'] for p in profiles}, {128, 1024, 65536})
            self.assertEqual({p['subscribers'] for p in profiles}, {1, 4})
            self.assertEqual({p['window'] for p in profiles}, {1, 16})
            self.assertEqual({p['mqtt_client'] for p in profiles}, {'paho', 'connectanum'})
        self.assertEqual(len(gate.ALL_PATHS), 6)

    def test_invalid_counters_and_latency_histograms_fail(self):
        for value in [True, -1, '1', None, float('nan'), float('inf')]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                gate.number(value, 'test')
        with self.assertRaises(ValueError):
            gate.number(0, 'test', positive=True)
        self.assertEqual(gate.number(0, 'test'), 0)
        self.assertEqual(gate.percentile([[10, 2], [20, 1], [10, 1]], .95), 20)
        for histogram in [[], [[1.5, 1]], [[1, .5]], [[1, 0]]]:
            with self.assertRaises(ValueError):
                gate.percentile(histogram, .5)
        with self.assertRaises(ValueError):
            gate.check_memory(dict(MEMORY, peak_rss_bytes=99))

    def test_delivery_requires_exact_count_population_identity_and_each_process(self):
        row = sample()
        self.assertEqual(row['received'], 2)
        self.assertEqual(row['p99_us'], 20)
        for key, value in [('received', 1), ('duplicates', 1), ('payload_bytes', 1),
                           ('ordered', False), ('order_errors', 1), ('latency_histogram_us', [[10, 1]]),
                           ('last_received_us', 50)]:
            with self.subTest(key=key), mock.patch.object(gate, 'percentile', wraps=gate.percentile):
                report = dict(received=2, duplicates=0, payload_bytes=128, ordered=True,
                              order_errors=0, latency_histogram_us=[[10, 2]], first_sent_us=100, last_received_us=200)
                report[key] = value
                with self.assertRaises(ValueError):
                    gate.delivery_row(PROFILE, 'mqtt_to_wamp', 1, 2, [report], row['processes'], QUEUES)
        with self.assertRaises(ValueError):
            gate.delivery_row(PROFILE, 'mqtt_to_wamp', 1, 2, [], {}, QUEUES)
        report = dict(received=2, duplicates=0, payload_bytes=128, ordered=True,
                      order_errors=0, latency_histogram_us=[[10, 2]], first_sent_us=100, last_received_us=200)
        with self.assertRaises(ValueError):
            gate.delivery_row(PROFILE, 'mqtt_to_wamp', 1, 2, [report], {}, QUEUES)
        for key in QUEUES:
            with self.subTest(key=key), self.assertRaises(ValueError):
                gate.delivery_row(PROFILE, 'mqtt_to_wamp', 1, 2, [report], row['processes'], dict(QUEUES, **{key: 9}))
        burst = dict(PROFILE, window=16)
        report['ordered'], report['order_errors'] = False, 2
        gate.delivery_row(burst, 'wamp_to_mqtt', 1, 2, [report], row['processes'], QUEUES)

    def test_complete_matched_matrix_and_every_numeric_regression_budget(self):
        rows = [sample(path=path, run=run) for path in gate.ALL_PATHS for run in (1, 2)]
        summary = gate.summarize(rows, [PROFILE], 2)
        self.assertEqual({r['direction'] for r in summary}, set(gate.DIRECTIONS))
        self.assertTrue(all(r['throughput_ratio'] == 1 for r in summary))
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            gate.summarize(rows + rows[:1], [PROFILE], 2)
        with self.assertRaisesRegex(ValueError, 'Incomplete'):
            gate.summarize(rows[:-1], [PROFILE], 2)
        limits = dict(min_throughput_ratio=.9, max_p95_over_control_sum=.6,
                      max_cpu_over_control_sum=.6, max_peak_rss_bytes=200,
                      max_drained_rss_bytes=120, max_retained_growth_bytes=0)
        budget = {'profiles': {PROFILE['id']: {d: dict(limits) for d in gate.DIRECTIONS}}}
        self.assertTrue(all(r['passed'] for r in gate.summarize(rows, [PROFILE], 2, budget)))
        for key in limits:
            broken = copy.deepcopy(budget)
            broken['profiles'][PROFILE['id']]['mqtt_to_wamp'][key] = 2 if key.startswith('min_') else -1
            self.assertFalse(gate.summarize(rows, [PROFILE], 2, broken)[0]['passed'])
        bad = copy.deepcopy(rows)
        for row in bad:
            row['processes']['broker']['cpu_seconds'] = 0
        with self.assertRaisesRegex(ValueError, 'control CPU'):
            gate.summarize(bad, [PROFILE], 2)
        for row in bad:
            row['processes']['broker']['cpu_seconds'] = .01
            row['p95_us'] = 0
        with self.assertRaisesRegex(ValueError, 'control latency'):
            gate.summarize(bad, [PROFILE], 2)


class GatewayControlTest(unittest.TestCase):
    def campaign(self, **changes):
        return gate.Campaign(Path('worker'), Path('.'), dict(PROFILE, native_library='native',
            path='mqtt_to_wamp', paho_python='python', **changes), timeout=.01)

    def test_eof_errors_duplicates_and_expired_deadlines_fail_closed(self):
        campaign = self.campaign()
        campaign.events.put(('old', {'kind': 'eof'}))
        campaign.events.put(('broker', {'kind': 'ready'}))
        self.assertEqual(campaign.expect(['broker'], 'ready'), {'broker': {'kind': 'ready'}})
        for message in [{'kind': 'error'}, {'kind': 'eof'}]:
            campaign.children['bad'] = mock.Mock(closing=False)
            campaign.events.put(('bad', message))
            with self.assertRaises(RuntimeError):
                campaign.event()
        with self.assertRaises(TimeoutError):
            campaign.event(0)
        campaign.events.put(('bad', {'kind': 'ready'}))
        with self.assertRaises(ValueError):
            campaign.expect(['broker'], 'ready')
        with self.assertRaises(queue.Empty):
            campaign.event()

    def test_client_dispatch_selects_paho_only_for_the_mqtt_leg(self):
        with mock.patch.object(gate, 'Child') as child:
            campaign = self.campaign()
            campaign.spawn('subscriber-0', 'subscriber')
            self.assertEqual(child.call_args.args[1][0], 'worker')
            campaign.config['mqtt_client'] = 'paho'
            campaign.spawn('publisher', 'publisher')
            self.assertTrue(child.call_args.args[1][1].endswith('mqtt_gateway_paho_peer.py'))
            campaign.config['reference'] = True
            campaign.spawn('broker', 'server')
            self.assertTrue(child.call_args.args[1][1].endswith('mqtt_gateway_reference_server.py'))
            campaign.close()
            self.assertFalse(campaign.children)

    def test_flow_control_waits_for_every_subscriber_and_rejects_bad_progress(self):
        for invalid in [None, 'phase', 'label', 'duplicate', 'bool', 'count', 'kind']:
            with self.subTest(invalid=invalid):
                campaign = self.campaign()
                server = mock.Mock(label='broker')
                campaign.children = {name: mock.Mock(measurement_pid=1) for name in ['broker', 'publisher', 'subscriber-0']}
                events = [('broker', {'kind':'armed'}), ('publisher', {'kind':'armed'}), ('subscriber-0', {'kind':'armed'})]
                progress = dict(kind='progress', phase=1, received=2)
                if invalid == 'phase': progress['phase'] = 2
                if invalid == 'bool': progress['received'] = True
                if invalid == 'count': progress['received'] = 3
                if invalid == 'kind': progress['kind'] = 'unknown'
                events.append(('unknown' if invalid == 'label' else 'subscriber-0', progress))
                report = dict(kind='received', phase=1, received=2)
                events.append(('subscriber-0', report))
                if invalid == 'duplicate': events.append(('subscriber-0', report))
                events.append(('publisher', dict(kind='sent', phase=1, sent=2)))
                events.extend((name, dict(kind='sampled', memory=MEMORY)) for name in campaign.children)
                campaign.event = mock.Mock(side_effect=events)
                with mock.patch.object(gate.reference, 'process_metrics', side_effect=[(1, 100, 200)] * 3 + [(1.1, 100, 200)] * 3):
                    if invalid is None:
                        reports, processes = campaign.phase(1, 2, ['publisher', 'subscriber-0'], server)
                        self.assertEqual(set(reports), {'subscriber-0'})
                        self.assertGreater(processes['broker']['cpu_seconds'], 0)
                        campaign.children['publisher'].send.assert_any_call(dict(op='credit',phase=1,received=2))
                    else:
                        with self.assertRaises(ValueError):
                            campaign.phase(1, 2, ['publisher', 'subscriber-0'], server)

    def test_a_complete_campaign_preserves_raw_samples_and_disconnect_memory(self):
        with tempfile.TemporaryDirectory() as temporary:
            campaign = self.campaign()
            campaign.output = Path(temporary)
            server = mock.Mock(label='broker')
            campaign.spawn = mock.Mock(return_value=server)
            campaign.expect = mock.Mock(side_effect=[{'broker':dict(pid=1,port=1234,version='pinned')},
                {}, {'broker':dict(memory=MEMORY,queues=QUEUES)}])
            row = sample()
            report = dict(received=2, duplicates=0, payload_bytes=128, ordered=True, order_errors=0,
                          latency_histogram_us=[[10,2]],first_sent_us=100,last_received_us=200)
            campaign.phase = mock.Mock(side_effect=[({}, {}), ({'subscriber-0':report},row['processes'])])
            campaign.close_clients = mock.Mock(return_value={name:dict(memory=MEMORY) for name in ['publisher','subscriber-0']})
            with mock.patch.object(gate.time,'sleep'):
                rows = campaign.run(PROFILE,'mosquitto',1,2,1,0)
            self.assertEqual(len(rows),1)
            self.assertEqual(json.loads((Path(temporary)/'raw.jsonl').read_text())['path'],'mosquitto')
            self.assertEqual(campaign.config['path'],'mqtt_to_mqtt')
            self.assertTrue(campaign.config['reference'])
        campaign = self.campaign()
        campaign.children = {'publisher':mock.Mock()}
        campaign.expect = mock.Mock(return_value={'publisher':{'kind':'closed'}})
        self.assertEqual(campaign.close_clients(['publisher']),{'publisher':{'kind':'closed'}})
        self.assertFalse(campaign.children)

    def test_real_child_protocol_captures_logs_observes_eof_and_closes_pipes(self):
        with tempfile.TemporaryDirectory() as temporary:
            events=queue.Queue()
            program="import sys,json; print(json.dumps({'kind':'ready'}),flush=True); line=sys.stdin.readline(); print(json.dumps({'kind':'progress'}),flush=True); print('malformed',flush=True); print('[]',flush=True)"
            child=gate.Child('peer',[sys.executable,'-c',program],events,Path(temporary),os.environ)
            self.assertEqual(events.get(timeout=5),('peer',{'kind':'ready'}))
            child.send({'op':'sample'})
            kinds=[events.get(timeout=5)[1]['kind'] for _ in range(4)]
            self.assertEqual(kinds,['progress','error','error','eof'])
            child.process.wait(timeout=5)
            child.stop()
            self.assertNotIn('progress',(Path(temporary)/'peer.stdout.jsonl').read_text())
            self.assertTrue(child.process.stdout.closed)
        for platform in ['posix','nt']:
            with tempfile.TemporaryDirectory() as temporary:
                process=mock.Mock(stdout=io.StringIO(''),pid=123456)
                process.stdin.close.side_effect=BrokenPipeError()
                process.poll.return_value=None
                process.wait.side_effect=[subprocess.TimeoutExpired('worker',5),0]
                platform_os=SimpleNamespace(name=platform,killpg=mock.Mock())
                with (mock.patch.object(gate.subprocess,'Popen',return_value=process),
                      mock.patch.object(gate,'os',platform_os)):
                    child=gate.Child('hung',['worker'],queue.Queue(),Path(temporary),{})
                    child.stop()
                if platform=='posix': platform_os.killpg.assert_called_once_with(process.pid,gate.signal.SIGKILL)
                else: process.kill.assert_called_once()
        with tempfile.TemporaryDirectory() as temporary:
            opened=[]; original=Path.open
            def open_file(path,*args,**kwargs):
                result=original(path,*args,**kwargs);opened.append(result);return result
            with mock.patch.object(Path,'open',open_file),mock.patch.object(gate.subprocess,'Popen',side_effect=OSError('spawn failed')),self.assertRaises(OSError):
                gate.Child('bad',['worker'],queue.Queue(),Path(temporary),{})
            self.assertTrue(all(file.closed for file in opened))
        campaign=self.campaign()
        first, second=mock.Mock(),mock.Mock()
        first.stop.side_effect=RuntimeError('cleanup failed')
        campaign.children={'first':first,'second':second}
        with self.assertRaises(RuntimeError):campaign.close()
        second.stop.assert_called_once()
        self.assertFalse(campaign.children)

    def test_compile_uses_the_current_package_build_hooks(self):
        with mock.patch.object(gate.subprocess,'run') as run:
            self.assertEqual(gate.compile_worker(Path('/tmp/bundle')),Path('/tmp/bundle/bundle/bin/mqtt_gateway_worker'))
            self.assertIn('build',run.call_args.args[0])
            self.assertEqual(run.call_args.kwargs['env']['CONNECTANUM_SKIP_NATIVE_BUILD'],'1')
        error=subprocess.CalledProcessError(1,['dart'],output='build output',stderr='compiler failure')
        with mock.patch.object(gate.subprocess,'run',side_effect=error),self.assertRaisesRegex(RuntimeError,'compiler failure'):
            gate.compile_worker(Path('/tmp/bundle'))

    def test_cli_preserves_artifacts_metadata_and_returns_the_gate_verdict(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory=Path(temporary)
            library=directory/'native'; library.write_bytes(b'native')
            worker=directory/'worker'; worker.write_bytes(b'worker')
            limits=dict(min_throughput_ratio=.9,max_p95_over_control_sum=1,max_cpu_over_control_sum=1,
                        max_peak_rss_bytes=200,max_drained_rss_bytes=120,max_retained_growth_bytes=0)
            budgets={'profiles':{PROFILE['id']:{d:dict(limits) for d in gate.DIRECTIONS}}}
            budget=directory/'budget.json'; budget.write_text(json.dumps(budgets))
            def metadata(command,**_):
                return 'a'*40 if command[:2]==['git','rev-parse'] else '' if command[0]=='git' else 'Dart test'
            with (mock.patch.dict(gate.os.environ,{'CONNECTANUM_NATIVE_LIB':str(library)}),
                  mock.patch.object(gate,'profiles',return_value=[PROFILE]),
                  mock.patch.object(gate,'Campaign') as campaign,
                  mock.patch.object(gate,'compile_worker',return_value=worker),
                  mock.patch.object(gate.subprocess,'check_output',side_effect=metadata),
                  mock.patch.object(gate.reference,'mosquitto_version',return_value='mosquitto version 2.0.18'),
                  mock.patch.object(gate.reference,'cpu_model',return_value='test CPU'),
                  contextlib.redirect_stdout(io.StringIO())):
                campaign.return_value.run.side_effect=lambda p,path,*_: [sample(p,path)]
                args=['--output',str(directory/'output'),'--runs','1','--messages','2','--warmup','1','--budget',str(budget)]
                self.assertEqual(gate.main(args),0)
                result=json.loads((directory/'output/summary.json').read_text())
                self.assertEqual(result['source_commit'],'a'*40)
                self.assertFalse(result['source_dirty'])
                self.assertEqual(len(result['results']),2)
                for direction in gate.DIRECTIONS:
                    budgets['profiles'][PROFILE['id']][direction]['max_peak_rss_bytes']=1
                budget.write_text(json.dumps(budgets))
                self.assertEqual(gate.main(args+['--output',str(directory/'failed')]),1)
                self.assertEqual(gate.main(args+['--output',str(directory/'diagnostic'),'--record-only','--profile',PROFILE['id'],'--worker',str(worker)]),0)
                campaign.return_value.run.side_effect=RuntimeError('delivery failed')
                with self.assertRaisesRegex(RuntimeError,'delivery failed'):
                    gate.main(args+['--output',str(directory/'incomplete')])
                self.assertTrue(campaign.return_value.close.called)
                self.assertTrue((directory/'incomplete/environment.json').is_file())
                self.assertFalse((directory/'incomplete/summary.json').exists())
                with contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):
                    gate.main(args)
                with mock.patch.object(gate.subprocess,'check_output',return_value='modified'),contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):
                    gate.main(args+['--output',str(directory/'dirty')])
                with contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):
                    gate.main(args+['--worker',str(worker)])

    def test_cli_rejects_missing_native_library_invalid_workloads_and_partial_gates(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with mock.patch.dict(gate.os.environ,{},clear=True), self.assertRaises(SystemExit):
                gate.main(['--output','unused'])
            with tempfile.TemporaryDirectory() as temporary:
                library=Path(temporary)/'native';library.write_bytes(b'native')
                with mock.patch.dict(gate.os.environ,{'CONNECTANUM_NATIVE_LIB':str(library)}):
                    for extra in [['--runs','0'],['--messages','0'],['--warmup','0'],['--drain-seconds','-1'],['--profile','missing'],['--profile',PROFILE['id']]]:
                        with self.subTest(extra=extra),self.assertRaises(SystemExit):
                            gate.main(['--output',temporary,*extra])
                with mock.patch.dict(gate.os.environ,{'CONNECTANUM_NATIVE_LIB':str(library)+'missing'}),self.assertRaises(SystemExit):
                    gate.main(['--output',temporary])
            with mock.patch.object(sys,'argv',['run_mqtt_gateway_benchmark.py','--help']),contextlib.redirect_stdout(io.StringIO()),self.assertRaises(SystemExit):
                runpy.run_path(str(gate.ROOT/'tool/run_mqtt_gateway_benchmark.py'),run_name='__main__')


if __name__ == '__main__':
    unittest.main()
