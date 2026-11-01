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
                       'broker_connected_peers', 'cancellation_listeners', 'errors', 'denied',
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
    return dict(gate.delivery_row(profile, path, run, 2, reports, processes, queues),warmup_messages=200,warmup_seconds=1)


def budget_limits(**changes):
    return dict(max_rate_cv=0,max_p99_cv=0,max_cpu_cv=0,min_delivered_per_sec=1,max_p95_us=20,max_p99_us=20,max_broker_cpu_seconds_per_million=5000,
                min_throughput_ratio=.9,max_p95_over_control_sum=.6,max_p99_over_control_sum=.6,
                max_cpu_over_control_sum=.6,max_peak_rss_bytes=200,max_drained_rss_bytes=120,
                max_retained_growth_bytes=0,max_rss_growth_bytes_per_cycle=0,
                processes={role:dict(max_peak_rss_bytes=200,max_drained_rss_bytes=120,max_retained_bytes=20,max_cpu_seconds_per_million_messages=5000)
                           for role in ['broker','publisher','subscriber']},**changes)


def overload_sample(profile=PROFILE,path='mqtt_to_wamp',run=1):
    row=sample(profile=dict(profile,subscribers=1),path=path,run=run)
    row['processes']['subscriber-1']=dict(MEMORY,cpu_seconds=.01)
    return dict(row,slow_received=1,recovery_received=64,stalled_peak_rss_bytes=150,recovery_queues=dict(QUEUES))


def overload_limits():
    return dict(max_rate_cv=0,max_p99_cv=0,max_cpu_cv=0,min_delivered_per_sec=1,max_p99_us=20,max_retained_growth_bytes=0,
                processes={role:dict(max_peak_rss_bytes=200,max_drained_rss_bytes=120,max_retained_bytes=20)
                           for role in ['broker','publisher','subscriber-0','subscriber-1']})


class GatewayAccountingTest(unittest.TestCase):
    def test_overload_retention_is_separate_complete_and_preserves_absolute_memory(self):
        rows=[overload_sample(path=d,run=n) for d in gate.DIRECTIONS for n in (1,2)]
        retained=[dict(copy.deepcopy(r),memory_protocol='bounded_nursery_v1') for r in rows]
        budget=dict(retention_protocol='bounded_nursery_v1',overload={PROFILE['id']:{d:overload_limits() for d in gate.DIRECTIONS}})
        with self.assertRaisesRegex(ValueError,'budget protocol'):gate.summarize_overload(rows,[PROFILE],2,budget)
        with self.assertRaisesRegex(ValueError,'budget protocol'):
            gate.summarize_overload(rows,[PROFILE],2,dict(budget,retention_protocol='raw_rss_v1'),retention_rows=retained)
        self.assertTrue(all(r['passed'] for r in gate.summarize_overload(rows,[PROFILE],2,budget,retention_rows=retained)))
        bad=copy.deepcopy(retained);bad[0]['memory_protocol']='raw_rss_v1'
        with self.assertRaisesRegex(ValueError,'collected'):gate.summarize_overload(rows,[PROFILE],2,budget,retention_rows=bad)
        with self.assertRaises(ValueError):gate.summarize_overload(rows,[PROFILE],2,budget,retention_rows=retained[:-1])
        bad=copy.deepcopy(retained)
        for r in bad:
            if r['run']==2:
                r['processes']['broker']['drained_rss_bytes']+=32*1048576
                r['processes']['broker']['peak_rss_bytes']+=32*1048576
        self.assertTrue(all(not r['checks']['retained_growth'] and not r['checks']['broker_retained_bytes']
                            for r in gate.summarize_overload(rows,[PROFILE],2,budget,retention_rows=bad)))

    def test_collected_retention_is_complete_and_keeps_raw_rss_and_leak_guards(self):
        rows=[sample(path=d,run=n) for d in gate.ALL_PATHS for n in (1,2)]
        retained=[dict(sample(path=d,run=n),memory_protocol='bounded_nursery_v1') for d in gate.DIRECTIONS for n in (1,2)]
        budgets=dict(profiles={PROFILE['id']:{d:budget_limits() for d in gate.DIRECTIONS}},retention_protocol='bounded_nursery_v1')
        with self.assertRaisesRegex(ValueError,'separate retention'):gate.summarize(rows,[PROFILE],2,budgets)
        with self.assertRaisesRegex(ValueError,'budget protocol'):
            gate.summarize(rows,[PROFILE],2,dict(budgets,retention_protocol='raw_rss_v1'),retention_rows=retained)
        results=gate.summarize(rows,[PROFILE],2,budgets,retention_rows=retained)
        self.assertTrue(all(r['passed'] for r in results))
        self.assertTrue(all(r['retention']['protocol']=='bounded_nursery_v1' for r in results))
        for defect in ['missing','duplicate','protocol','process','run']:
            bad=copy.deepcopy(retained)
            if defect=='missing':bad.pop()
            if defect=='duplicate':bad.append(copy.deepcopy(bad[0]))
            if defect=='protocol':bad[0]['memory_protocol']='raw_rss_v1'
            if defect=='process':bad[0]['processes'].pop('publisher')
            if defect=='run':bad[0]['run']=3
            with self.subTest(defect=defect),self.assertRaises(ValueError):gate.retention_summary(bad,[PROFILE],2)
        self.assertEqual(len(gate.retention_summary([r for r in retained if r['run']==1],[PROFILE],1)),2)
        # Raw absolute RSS is still blocking even if post-GC retention is flat.
        raw_leak=copy.deepcopy(rows)
        for r in raw_leak:
            if r['path'] in gate.DIRECTIONS:r['processes']['broker']['peak_rss_bytes']=201
        self.assertTrue(all(not r['checks']['peak_rss'] for r in gate.summarize(raw_leak,[PROFILE],2,budgets,retention_rows=retained)))
        # A genuine live allocation survives collection and fails unchanged caps.
        leaked=copy.deepcopy(retained)
        for r in leaked:
            if r['run']==2:
                for p in r['processes'].values():
                    p['drained_rss_bytes']+=32*1048576;p['peak_rss_bytes']+=32*1048576
        failed=gate.summarize(rows,[PROFILE],2,budgets,retention_rows=leaked)
        self.assertTrue(all(not r['checks']['retained_growth'] and not r['checks']['lifecycle_slope'] and not r['checks']['publisher_retained_bytes'] for r in failed))

    def test_cpu_signature_is_stable_across_core_order_and_clock_changes(self):
        first='processor: 0\nCPU implementer: 0x41\nCPU part: 0xd49\nFeatures: asimd aes fp\nBogoMIPS: 100\n'
        second='processor: 3\nFeatures: fp asimd aes\nCPU part:  0xd49\nCPU implementer:\t0x41\nBogoMIPS: 200\n'
        self.assertEqual(gate.cpu_signature_sha256(first),gate.cpu_signature_sha256(second+first))
        self.assertNotEqual(gate.cpu_signature_sha256(first),gate.cpu_signature_sha256(first.replace('0xd49','0xd40')))
        self.assertIsNone(gate.cpu_signature_sha256('processor: 0\nBogoMIPS: 100'))
        with mock.patch.object(gate.Path,'read_text',return_value=first):
            self.assertEqual(gate.cpu_signature_sha256(),gate.cpu_signature_sha256(first))
        with mock.patch.object(gate.Path,'read_text',side_effect=OSError('unavailable')):
            self.assertIsNone(gate.cpu_signature_sha256())

    def test_numeric_hardware_qualification_rejects_missing_or_different_hosts(self):
        selected=gate.profiles('release')
        models={p['id']:'test CPU' for p in selected}
        wanted=dict(architecture='x86_64',logical_cpus=4,profile_cpu_models=models)
        host=dict(architecture='x86_64',logical_cpus=4,cpu_model='test CPU',cpu_signature_sha256='a'*64)
        gate.check_hardware(dict(hardware=wanted),host,selected)
        for field,value in [('architecture','arm64'),('logical_cpus',True),('logical_cpus',0),
                            ('profile_cpu_models',None),('profile_cpu_models',{}),
                            ('profile_cpu_models',dict(models,extra='test CPU')),
                            ('profile_cpu_models',dict(models,**{selected[0]['id']:''})),
                            ('cpu_signature_sha256',123),('cpu_signature_sha256','z'*64)]:
            with self.subTest(field=field,value=value),self.assertRaises(ValueError):
                gate.check_hardware(dict(hardware=dict(wanted,**{field:value})),host,selected)
        for missing in [{},dict(hardware=None)]:
            with self.assertRaises(ValueError):gate.check_hardware(missing,host,selected)
        for field,value in [('architecture','aarch64'),('logical_cpus',2),('cpu_model','other CPU')]:
            with self.subTest(field=field),self.assertRaises(ValueError):
                gate.check_hardware(dict(hardware=wanted),dict(host,**{field:value}),selected)
        models=dict(models,**{selected[1]['id']:'second CPU'})
        gate.check_hardware(dict(hardware=dict(wanted,profile_cpu_models=models)),host,selected[:1])
        with self.assertRaises(ValueError):
            gate.check_hardware(dict(hardware=dict(wanted,profile_cpu_models=models)),host,selected[1:2])
        wanted=dict(wanted,architecture='aarch64',cpu_signature_sha256='a'*64)
        host=dict(host,architecture='aarch64')
        gate.check_hardware(dict(hardware=wanted),host,selected)
        with self.assertRaises(ValueError):
            gate.check_hardware(dict(hardware=dict(wanted,cpu_signature_sha256=None)),host,selected)
        with self.assertRaises(ValueError):
            gate.check_hardware(dict(hardware=wanted),dict(host,cpu_signature_sha256='b'*64),selected)

    def test_matrix_covers_real_directions_controls_and_independent_peers(self):
        for matrix, count in [('smoke', 16), ('release', 32)]:
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
        self.assertEqual({p['transport'] for p in gate.overload_profiles()}, {'tcp','wss'})

    def test_shards_cover_every_profile_once_and_budget_validation_is_fail_closed(self):
        profiles=gate.profiles('release')
        for total in [1,4,16,32]:
            shards=[gate.shard_profiles(profiles,f'{i}/{total}') for i in range(total)]
            self.assertEqual(sorted(p['id'] for shard in shards for p in shard),sorted(p['id'] for p in profiles))
            self.assertTrue(all(shards))
            overload=[gate.shard_profiles(gate.overload_profiles(),f'{i}/{total}') for i in range(total)]
            self.assertEqual(sorted(p['id'] for shard in overload for p in shard),sorted(p['id'] for p in gate.overload_profiles()))
        self.assertEqual({len(gate.shard_profiles(profiles,f'{i}/16')) for i in range(16)},{2})
        self.assertEqual([p for i in range(4) for p in gate.shard_profiles(profiles,f'{i}/4')],
                         [p for i in range(4) for p in profiles[i::4]])
        self.assertEqual(len({p['id'] for i in range(4) for p in gate.shard_profiles(profiles,f'{i}/4')}),32)
        workload=dict(runs=5,messages=5000,warmup=200,warmup_seconds=1,overload_runs=3,overload_messages=2048,overload_stall_ms=20000,drain_seconds=.5)
        budget=dict(schema_version=1,baseline_source_commit='a'*40,platform=sys.platform,workload=workload,
                    profiles={p['id']:{d:budget_limits() for d in gate.DIRECTIONS} for p in profiles},
                    overload={p['id']:{d:overload_limits() for d in gate.DIRECTIONS} for p in gate.overload_profiles()})
        args=SimpleNamespace(matrix='release',**workload)
        gate.validate_budget(budget,args)
        for invalid in ['schema','commit','platform','workload','warmup_duration','matrix','profiles','directions','processes','scalar','memory','retention']:
            bad=copy.deepcopy(budget);arguments=copy.deepcopy(args)
            if invalid=='schema':bad['schema_version']=2
            if invalid=='commit':bad['baseline_source_commit']='short'
            if invalid=='platform':bad['platform']='not-this-platform'
            if invalid=='workload':arguments.messages=4999
            if invalid=='warmup_duration':arguments.warmup_seconds=.5
            if invalid=='matrix':arguments.matrix='smoke'
            if invalid=='profiles':bad['profiles'].pop(PROFILE['id'])
            if invalid=='directions':bad['profiles'][PROFILE['id']].pop('mqtt_to_wamp')
            if invalid=='processes':bad['profiles'][PROFILE['id']]['mqtt_to_wamp']['processes'].pop('broker')
            if invalid=='scalar':bad['profiles'][PROFILE['id']]['mqtt_to_wamp']['max_peak_rss_bytes']=-1
            if invalid=='memory':bad['profiles'][PROFILE['id']]['mqtt_to_wamp']['processes']['broker']['max_peak_rss_bytes']=-1
            if invalid=='retention':bad['retention_protocol']='unknown'
            with self.subTest(invalid=invalid),self.assertRaises(ValueError):gate.validate_budget(bad,arguments)

    def test_missing_short_or_invalid_warmup_fails_closed(self):
        good=dict(warmup_messages=200,warmup_seconds=1)
        gate.check_warmup(good,200,1)
        for missing in good:
            with self.assertRaises(KeyError):gate.check_warmup({k:v for k,v in good.items() if k!=missing},200,1)
        for field,values in [('warmup_messages',[True,0,199,200.0]),('warmup_seconds',[-1,True,float('nan'),float('inf'),.99])]:
            for value in values:
                with self.subTest(field=field,value=value),self.assertRaises(ValueError):
                    gate.check_warmup(dict(good,**{field:value}),200,1)

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

    def test_publication_counters_reject_missing_loss_rebroadcast_and_invalid_types(self):
        for direction in gate.DIRECTIONS:
            own='mqtt_publications' if direction=='mqtt_to_wamp' else 'wamp_publications'
            other='wamp_publications' if direction=='mqtt_to_wamp' else 'mqtt_publications'
            good={own:10,other:0}
            gate.check_publications(good,direction,10)
            for key,value in [(own,9),(own,True),(other,1),(other,False)]:
                with self.assertRaises(ValueError):gate.check_publications(dict(good,**{key:value}),direction,10)
            with self.assertRaises(KeyError):gate.check_publications({},direction,10)

    def test_complete_matched_matrix_and_every_numeric_regression_budget(self):
        rows = [sample(path=path, run=run) for path in gate.ALL_PATHS for run in (1, 2)]
        summary = gate.summarize(rows, [PROFILE], 2)
        self.assertEqual({r['direction'] for r in summary}, set(gate.DIRECTIONS))
        self.assertTrue(all(r['throughput_ratio'] == 1 for r in summary))
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            gate.summarize(rows + rows[:1], [PROFILE], 2)
        with self.assertRaisesRegex(ValueError, 'Incomplete'):
            gate.summarize(rows[:-1], [PROFILE], 2)
        limits = budget_limits()
        budget = {'profiles': {PROFILE['id']: {d: dict(limits) for d in gate.DIRECTIONS}}}
        self.assertTrue(all(r['passed'] for r in gate.summarize(rows, [PROFILE], 2, budget)))
        for key in limits:
            if key=='processes':continue
            broken = copy.deepcopy(budget)
            broken['profiles'][PROFILE['id']]['mqtt_to_wamp'][key] = 1e9 if key.startswith('min_') else -1
            self.assertFalse(gate.summarize(rows, [PROFILE], 2, broken)[0]['passed'])
        for role in limits['processes']:
            for field in limits['processes'][role]:
                broken=copy.deepcopy(budget)
                broken['profiles'][PROFILE['id']]['mqtt_to_wamp']['processes'][role][field]=-1
                self.assertFalse(gate.summarize(rows,[PROFILE],2,broken)[0]['passed'])
        growing=copy.deepcopy(rows)
        next(row for row in growing if row['path']=='mqtt_to_wamp' and row['run']==2)['processes']['broker']['drained_rss_bytes']=150
        measured=gate.summarize(growing,[PROFILE],2)[0]
        self.assertEqual(measured['rss_growth_bytes_per_cycle'],30)
        self.assertEqual(measured['retained_growth_bytes'],30)
        self.assertEqual(measured['processes']['broker']['retained_bytes'],50)
        self.assertEqual(measured['processes']['publisher']['cpu_seconds_per_million_messages'],5000)
        self.assertEqual(gate.coefficient_of_variation([0,0]),0)
        for metric,field in [('delivered_per_sec','max_rate_cv'),('p99_us','max_p99_cv'),('cpu','max_cpu_cv')]:
            noisy=copy.deepcopy(rows)
            row=next(r for r in noisy if r['path']=='wamp_to_wamp' and r['run']==2)
            if metric=='cpu':row['processes']['broker']['cpu_seconds']*=2
            else:row[metric]*=2
            self.assertAlmostEqual(gate.summarize(noisy,[PROFILE],2)[0][field],1/3)
            self.assertFalse(gate.summarize(noisy,[PROFILE],2,budget)[0]['passed'])
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

    def test_stalled_receiver_cpu_uses_received_messages_and_zero_delivery_is_unavailable(self):
        row=overload_sample()
        result=gate.process_summary([row])
        self.assertEqual(result['subscriber-1']['cpu_seconds_per_million_messages'],10000)
        row['slow_received']=0
        self.assertIsNone(gate.process_summary([row])['subscriber-1']['cpu_seconds_per_million_messages'])

    def test_overload_matrix_and_every_memory_performance_budget(self):
        rows=[overload_sample(path=d,run=r) for d in gate.DIRECTIONS for r in (1,2)]
        budgets={'overload':{PROFILE['id']:{d:overload_limits() for d in gate.DIRECTIONS}}}
        self.assertTrue(all(row['passed'] for row in gate.summarize_overload(rows,[PROFILE],2,budgets)))
        self.assertEqual(gate.summarize_overload(rows,[PROFILE],2)[0]['slow_received_max'],1)
        for broken in [rows[:-1],rows+rows[:1]]:
            with self.assertRaises(ValueError):gate.summarize_overload(broken,[PROFILE],2)
        for field,value in [('slow_received',2),('recovery_received',63)]:
            bad=copy.deepcopy(rows);bad[0][field]=value
            with self.assertRaises(ValueError):gate.summarize_overload(bad,[PROFILE],2)
        for field,value in [('min_delivered_per_sec',1e9),('max_p99_us',19),('max_retained_growth_bytes',-1)]:
            bad=copy.deepcopy(budgets);bad['overload'][PROFILE['id']]['mqtt_to_wamp'][field]=value
            self.assertFalse(gate.summarize_overload(rows,[PROFILE],2,bad)[0]['passed'])
        for role in overload_limits()['processes']:
            for field in ('max_peak_rss_bytes','max_drained_rss_bytes','max_retained_bytes'):
                bad=copy.deepcopy(budgets);bad['overload'][PROFILE['id']]['mqtt_to_wamp']['processes'][role][field]=0
                self.assertFalse(gate.summarize_overload(rows,[PROFILE],2,bad)[0]['passed'])


class GatewayControlTest(unittest.TestCase):
    def test_only_retention_children_receive_the_bounded_nursery(self):
        with mock.patch.dict(gate.os.environ,{'DART_VM_OPTIONS':'--verbose_gc'}):
            normal=self.campaign()
            config=dict(normal.config,retention_protocol='bounded_nursery_v1')
            retained=gate.Campaign(Path('/worker'),Path('/out'),config)
            self.assertEqual(normal.env['DART_VM_OPTIONS'],'--verbose_gc')
            self.assertEqual(retained.env['DART_VM_OPTIONS'],'--new_gen_semi_max_size=1')
            self.assertEqual(gate.os.environ['DART_VM_OPTIONS'],'--verbose_gc')

    def campaign(self, **changes):
        return gate.Campaign(Path('worker'), Path('.'), dict(PROFILE, native_library='native',
            path='mqtt_to_wamp', paho_python='python', **changes), timeout=.01)

    def test_eof_errors_duplicates_and_expired_deadlines_fail_closed(self):
        campaign = self.campaign()
        self.assertEqual(campaign.load_timeout,.01)
        explicit=gate.Campaign(Path('worker'),Path('.'),dict(PROFILE,native_library='native'),load_timeout=300)
        self.assertEqual(explicit.load_timeout,300)
        campaign.events.put(('old', {'kind': 'eof'}))
        campaign.events.put(('broker', {'kind': 'ready'}))
        self.assertEqual(campaign.expect(['broker'], 'ready'), {'broker': {'kind': 'ready'}})
        for message in [{'kind': 'error'}, {'kind': 'eof'}]:
            campaign.children['bad'] = mock.Mock(closing=False)
            campaign.events.put(('bad', message))
            with self.assertRaises(RuntimeError):
                campaign.event()
        campaign.events.put(('bad',dict(kind='error',message='MqttProtocolException: MQTT connection closed')))
        campaign.events.put(('bad',dict(kind='disconnected')))
        self.assertEqual(campaign.event(expected_disconnect='bad')[1]['kind'],'disconnected')
        with self.assertRaises(TimeoutError):
            campaign.event(0)
        campaign.events.put(('bad', {'kind': 'ready'}))
        with self.assertRaises(ValueError):
            campaign.expect(['broker'], 'ready')
        with self.assertRaises(queue.Empty):
            campaign.event()

    def test_quiescence_rejects_late_duplicates_and_unexpected_disconnects(self):
        campaign=self.campaign()
        campaign.settle(0)
        campaign.settle(.001)
        for kind in ['progress','received','disconnected']:
            campaign.events.put(('subscriber-0',dict(kind=kind)))
            with self.assertRaisesRegex(ValueError,'after complete delivery'):campaign.settle(.01)
        campaign.event=mock.Mock(side_effect=TimeoutError())
        campaign.settle(.01)

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

    def test_timed_warmup_keeps_every_message_and_uses_unique_phases(self):
        campaign=self.campaign();campaign.phase=mock.Mock()
        with mock.patch.object(gate.time,'monotonic',side_effect=[10,10.2,11.1]):
            messages,seconds=campaign.warm_up(2,200,1,['publisher','subscriber-0'],mock.Mock())
        self.assertEqual(messages,400)
        self.assertAlmostEqual(seconds,1.1)
        phases=[call.args[0] for call in campaign.phase.call_args_list]
        self.assertEqual(phases[0],2)
        self.assertEqual(len(set(phases)),2)
        self.assertGreater(phases[1],0x7fffffff)
        with mock.patch.object(gate.time,'monotonic',side_effect=[20,20.1]):
            self.assertEqual(campaign.warm_up(4,200,0,[],mock.Mock())[0],200)

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
                rows = campaign.run(PROFILE,'mosquitto',1,2,1,0,0)
            self.assertEqual(len(rows),1)
            self.assertEqual(campaign.phase.call_args_list[0].args[1],1)
            self.assertEqual(json.loads((Path(temporary)/'raw.jsonl').read_text())['path'],'mosquitto')
            self.assertEqual(campaign.config['path'],'mqtt_to_mqtt')
            self.assertTrue(campaign.config['reference'])
            campaign.expect.side_effect=[{'broker':dict(pid=1,port=1234)}, {},
                {'broker':dict(memory=MEMORY,queues=dict(QUEUES,mqtt_publications=3,wamp_publications=0))}]
            campaign.phase.side_effect=[({}, {}), ({'subscriber-0':report},row['processes'])]
            with mock.patch.object(gate.time,'sleep'):
                self.assertEqual(len(campaign.run(PROFILE,'mqtt_to_wamp',1,2,1,0,0)),1)
            campaign.expect.side_effect=[{'broker':dict(pid=1,port=1234)}, {},
                {'broker':dict(memory=MEMORY,queues=dict(QUEUES,mqtt_publications=6,wamp_publications=0))}]
            campaign.warm_up=mock.Mock(return_value=(4,1.1))
            campaign.phase.side_effect=[({'subscriber-0':report},row['processes'])]
            with mock.patch.object(gate.time,'sleep'):
                measured=campaign.run(PROFILE,'mqtt_to_wamp',1,2,4,0)
            campaign.warm_up.assert_called_once_with(2,4,1,['publisher','subscriber-0'],server)
            self.assertEqual(measured[0]['warmup_messages'],4)
            self.assertEqual(measured[0]['warmup_seconds'],1.1)
        campaign = self.campaign()
        campaign.children = {'publisher':mock.Mock()}
        campaign.expect = mock.Mock(return_value={'publisher':{'kind':'closed'}})
        self.assertEqual(campaign.close_clients(['publisher']),{'publisher':{'kind':'closed'}})
        self.assertFalse(campaign.children)

    def test_retention_campaign_samples_collection_before_load_and_after_release(self):
        with tempfile.TemporaryDirectory() as temporary:
            campaign=self.campaign();campaign.output=Path(temporary)
            server=mock.Mock(label='broker')
            labels=['broker','publisher','subscriber-0']
            campaign.children={label:mock.Mock() for label in labels}
            campaign.spawn=mock.Mock(return_value=server)
            campaign.warm_up=mock.Mock(return_value=(2,1.1))
            baseline={label:dict(memory=dict(MEMORY,drained_rss_bytes=90)) for label in labels}
            final=dict(memory=dict(MEMORY,drained_rss_bytes=110,peak_rss_bytes=250),
                       queues=dict(QUEUES,mqtt_publications=4,wamp_publications=0))
            campaign.expect=mock.Mock(side_effect=[{'broker':dict(pid=1,port=1234)}, {},baseline,{'broker':final}])
            row=sample()
            report=dict(received=2,duplicates=0,payload_bytes=128,ordered=True,order_errors=0,
                        latency_histogram_us=[[10,2]],first_sent_us=100,last_received_us=200)
            campaign.phase=mock.Mock(return_value=({'subscriber-0':report},row['processes']))
            campaign.close_clients=mock.Mock(return_value={label:dict(memory=MEMORY) for label in labels[1:]})
            with mock.patch.object(gate.time,'sleep'):
                measured=campaign.run(PROFILE,'mqtt_to_wamp',1,2,1,0,retention=True)[0]
            for label in labels:campaign.children[label].send.assert_called_once_with(dict(op='collect'))
            server.send.assert_called_once_with(dict(op='collect'))
            campaign.close_clients.assert_called_once_with(labels[1:],collect=True)
            self.assertEqual(measured['memory_protocol'],'bounded_nursery_v1')
            self.assertEqual(measured['processes']['broker']['warm_rss_bytes'],90)
            self.assertEqual(measured['processes']['broker']['drained_rss_bytes'],110)
            self.assertEqual(measured['processes']['broker']['peak_rss_bytes'],250)
            self.assertEqual(measured['uncollected_load_memory']['broker']['warm_rss_bytes'],100)
            self.assertEqual(json.loads((Path(temporary)/'raw.jsonl').read_text()),measured)
        campaign=self.campaign();child=mock.Mock();campaign.children={'publisher':child}
        campaign.expect=mock.Mock(return_value={'publisher':dict(kind='closed')})
        campaign.close_clients(['publisher'],collect=True)
        child.send.assert_called_once_with(dict(op='close',collect=True))

    def test_overload_enforces_slow_disconnect_fast_exact_delivery_and_recovery(self):
        for invalid in [None,'retention','phase','progress','kind','full_slow','no_stall_sample','recovery']:
            with self.subTest(invalid=invalid),tempfile.TemporaryDirectory() as temporary:
                campaign=self.campaign()
                campaign.output=Path(temporary)
                labels=['broker','publisher','subscriber-0','subscriber-1']
                campaign.children={name:mock.Mock(label=name,measurement_pid=1) for name in labels}
                campaign.spawn=mock.Mock(side_effect=lambda label,_:campaign.children[label])
                campaign.expect=mock.Mock(side_effect=[{'broker':dict(pid=1,port=1234)}, {},{}, {},
                    {label:dict(memory=MEMORY) for label in labels}, {'broker':dict(memory=MEMORY,queues=dict(QUEUES,mqtt_publications=66,wamp_publications=0))},
                    {},{'broker':dict(memory=MEMORY,queues=dict(QUEUES,mqtt_publications=130,wamp_publications=0))}])
                if invalid=='retention':
                    responses=list(campaign.expect.side_effect)
                    responses.insert(2,{label:dict(memory=dict(MEMORY,drained_rss_bytes=90)) for label in labels})
                    campaign.expect.side_effect=responses
                report=dict(kind='received',phase=4,received=2,duplicates=0,payload_bytes=128,
                            ordered=True,order_errors=0,latency_histogram_us=[[10,2]],first_sent_us=100,last_received_us=200)
                events=[('subscriber-0',dict(kind='progress',phase=4,received=2)),
                        ('subscriber-1',dict(kind='progress',phase=4,received=1)),
                        ('publisher',dict(kind='sent',phase=4,sent=2)),('subscriber-0',report),
                        ('subscriber-1',dict(kind='disconnected',phase=4,received=1)),
                        ('subscriber-1',dict(kind='resumed',phase=4))]
                if invalid=='phase':events[0][1]['phase']=5
                if invalid=='progress':events[0][1]['received']=True
                if invalid=='kind':events[0][1]['kind']='unexpected'
                if invalid=='full_slow':events[4][1]['received']=2
                if invalid=='no_stall_sample':events.insert(0,events.pop())
                campaign.event=mock.Mock(side_effect=events)
                campaign.phase=mock.Mock(side_effect=[({},{}),({'subscriber-0':dict(received=63 if invalid=='recovery' else 64)}, {})])
                campaign.close_clients=mock.Mock(return_value={label:dict(memory=MEMORY) for label in labels[1:]})
                with mock.patch.object(gate.time,'sleep'),mock.patch.object(gate.reference,'process_metrics',return_value=(1,150,200)):
                    if invalid in (None,'retention'):
                        rows=campaign.run_overload(PROFILE,'mqtt_to_wamp',1,2,1,0,retention=invalid=='retention')
                        if invalid=='retention':
                            self.assertEqual(rows[0]['memory_protocol'],'bounded_nursery_v1')
                            self.assertEqual(rows[0]['processes']['broker']['warm_rss_bytes'],90)
                            self.assertEqual(rows[0]['uncollected_load_memory']['broker']['warm_rss_bytes'],100)
                        self.assertEqual(rows[0]['slow_received'],1)
                        self.assertEqual(rows[0]['recovery_received'],64)
                        self.assertTrue((campaign.output/'raw.jsonl').is_file())
                    else:
                        with self.assertRaises(ValueError):campaign.run_overload(PROFILE,'mqtt_to_wamp',1,2,1,0)

    def test_real_child_protocol_captures_logs_observes_eof_and_closes_pipes(self):
        with tempfile.TemporaryDirectory() as temporary:
            events=queue.Queue()
            program="import sys,json; print('first-cycle',file=sys.stderr); print(json.dumps({'kind':'ready'}),flush=True); line=sys.stdin.readline(); print(json.dumps({'kind':'progress'}),flush=True); print('malformed',flush=True); print('[]',flush=True)"
            child=gate.Child('peer',[sys.executable,'-c',program],events,Path(temporary),os.environ)
            self.assertEqual(events.get(timeout=5),('peer',{'kind':'ready'}))
            child.send({'op':'sample'})
            kinds=[events.get(timeout=5)[1]['kind'] for _ in range(4)]
            self.assertEqual(kinds,['progress','error','error','eof'])
            child.process.wait(timeout=5)
            child.stop()
            self.assertNotIn('progress',(Path(temporary)/'peer.stdout.jsonl').read_text())
            self.assertTrue(child.process.stdout.closed)
            next_program="import sys,json; print('second-cycle',file=sys.stderr); print(json.dumps({'kind':'next-cycle'}),flush=True)"
            next_child=gate.Child('peer',[sys.executable,'-c',next_program],events,Path(temporary),os.environ)
            self.assertEqual(events.get(timeout=5),('peer',{'kind':'next-cycle'}))
            self.assertEqual(events.get(timeout=5),('peer',{'kind':'eof'}))
            next_child.stop()
            self.assertIn('malformed',(Path(temporary)/'peer.stdout.jsonl').read_text())
            self.assertIn('next-cycle',(Path(temporary)/'peer.stdout.jsonl').read_text())
            self.assertEqual((Path(temporary)/'peer.stderr.log').read_text(),'first-cycle\nsecond-cycle\n')
        for platform in ['posix','nt']:
            with tempfile.TemporaryDirectory() as temporary:
                process=mock.Mock(stdout=io.StringIO(''),pid=123456,returncode=-9)
                process.stdin.close.side_effect=BrokenPipeError()
                process.poll.return_value=None
                process.wait.side_effect=[subprocess.TimeoutExpired('worker',5),0]
                platform_os=SimpleNamespace(name=platform,killpg=mock.Mock())
                with (mock.patch.object(gate.subprocess,'Popen',return_value=process),
                      mock.patch.object(gate,'os',platform_os)):
                    child=gate.Child('hung',['worker'],queue.Queue(),Path(temporary),{})
                    with self.assertRaisesRegex(RuntimeError,'exited with code -9'):child.stop()
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

    def test_nonzero_child_teardown_fails_after_all_logs_and_pipes_are_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            child=gate.Child('broken-close',[sys.executable,'-c','import sys; sys.stdin.read(); sys.exit(7)'],queue.Queue(),Path(temporary),os.environ)
            with self.assertRaisesRegex(RuntimeError,'exited with code 7'):child.stop()
            self.assertTrue(child.process.stdout.closed)
            self.assertTrue(child.log.closed)
            self.assertTrue(child.stdout_log.closed)

    def test_compile_uses_the_current_package_build_hooks(self):
        with mock.patch.object(gate.subprocess,'run') as run:
            self.assertEqual(gate.compile_worker(Path('/tmp/bundle')),Path('/tmp/bundle/bundle/bin/mqtt_gateway_worker'))
            self.assertIn('build',run.call_args.args[0])
            self.assertEqual(run.call_args.kwargs['env']['CONNECTANUM_SKIP_NATIVE_BUILD'],'1')
        error=subprocess.CalledProcessError(1,['dart'],output='build output',stderr='compiler failure')
        with mock.patch.object(gate.subprocess,'run',side_effect=error),self.assertRaisesRegex(RuntimeError,'compiler failure'):
            gate.compile_worker(Path('/tmp/bundle'))

    def test_retention_worker_requires_the_real_aot_self_test(self):
        good=dict(kind='retention-self-test',protocol='bounded_nursery_v1',collections=12,live_and_released_witnesses_verified=True,
                  rooted_witness_bytes=32*1048576,rooted_witness_rss_growth_bytes=32*1048576,native_witness_bytes=32*1048576,
                  native_witness_rss_growth_bytes=32*1048576,native_witness_rss_drop_bytes=32*1048576,max_young_capacity_bytes=524288)
        with tempfile.TemporaryDirectory() as temporary, mock.patch.object(gate,'compile_worker',return_value=Path('/worker')) as compile:
            output=Path(temporary)/'self-test.json'
            with mock.patch.object(gate.subprocess,'run',return_value=SimpleNamespace(stdout=json.dumps(good),stderr='')) as run:
                self.assertEqual(gate.compile_retention_worker(Path('/bundle'),output),Path('/worker'))
                self.assertEqual(json.loads(output.read_text()),good)
                compile.assert_called_once_with(Path('/bundle'),'test/support/mqtt_gateway_retention_worker.dart')
                self.assertTrue(run.call_args.kwargs['check'])
            for field in good:
                output.unlink(missing_ok=True)
                bad=dict(good,**{field:None})
                with mock.patch.object(gate.subprocess,'run',return_value=SimpleNamespace(stdout=json.dumps(bad),stderr='')),self.assertRaises(ValueError):
                    gate.compile_retention_worker(Path('/bundle'),output)
                self.assertFalse(output.exists())
            with mock.patch.object(gate.subprocess,'run',return_value=SimpleNamespace(stdout=json.dumps(dict(good,rooted_witness_rss_growth_bytes=1)),stderr='')),self.assertRaises(ValueError):
                gate.compile_retention_worker(Path('/bundle'),output)
            for error in [subprocess.CalledProcessError(1,['worker'],output='partial proof',stderr='hook unavailable'),
                          subprocess.TimeoutExpired(['worker'],30,output=b'partial proof',stderr=b'hook unavailable')]:
                with mock.patch.object(gate.subprocess,'run',side_effect=error),self.assertRaisesRegex(RuntimeError,'hook unavailable'):
                    gate.compile_retention_worker(Path('/bundle'),output)
                failure=json.loads(output.with_suffix('.failure.json').read_text())
                self.assertIn('partial proof',failure['stdout'])
                self.assertIn('hook unavailable',failure['stderr'])

    def test_cli_preserves_artifacts_metadata_and_returns_the_gate_verdict(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory=Path(temporary)
            library=directory/'native'; library.write_bytes(b'native')
            worker=directory/'worker'; worker.write_bytes(b'worker')
            limits=budget_limits()
            budgets={'schema_version':1,'baseline_source_commit':'b'*40,'platform':sys.platform,
                     'hardware':dict(architecture='x86_64',logical_cpus=4,profile_cpu_models={PROFILE['id']:'test CPU'}),
                     'workload':dict(runs=1,messages=2,warmup=1,warmup_seconds=1,overload_runs=1,overload_messages=2,overload_stall_ms=1,drain_seconds=.5),
                     'profiles':{PROFILE['id']:{d:dict(limits) for d in gate.DIRECTIONS}},
                     'overload':{PROFILE['id']:{d:overload_limits() for d in gate.DIRECTIONS}}}
            budget=directory/'budget.json'; budget.write_text(json.dumps(budgets))
            def metadata(command,**_):
                return 'a'*40 if command[:2]==['git','rev-parse'] else '' if command[0]=='git' else 'Dart test'
            with (mock.patch.dict(gate.os.environ,{'CONNECTANUM_NATIVE_LIB':str(library)}),
                  mock.patch.object(gate,'profiles',return_value=[PROFILE]),
                  mock.patch.object(gate,'overload_profiles',return_value=[PROFILE]),
                  mock.patch.object(gate,'Campaign') as campaign,
                  mock.patch.object(gate,'compile_worker',return_value=worker),
                  mock.patch.object(gate,'compile_retention_worker',return_value=worker),
                  mock.patch.object(gate.subprocess,'check_output',side_effect=metadata),
                  mock.patch.object(gate.reference,'mosquitto_version',return_value='mosquitto version 2.0.18'),
                  mock.patch.object(gate.reference,'cpu_model',return_value='test CPU'),
                  mock.patch.object(gate.platform,'platform',return_value='test OS'),
                  mock.patch.object(gate.platform,'machine',return_value='x86_64'),
                  mock.patch.object(gate.os,'cpu_count',return_value=4),
                  contextlib.redirect_stdout(io.StringIO()) as output):
                campaign.return_value.run.side_effect=lambda p,path,*_: [dict(sample(p,path),warmup_messages=2)]
                campaign.return_value.run_overload.side_effect=lambda p,path,runs,*_,**opts: [dict(overload_sample(p,path,r),**({'memory_protocol':'bounded_nursery_v1'} if opts.get('retention') else {})) for r in range(1,runs+1)]
                args=['--output',str(directory/'output'),'--matrix','release','--runs','1','--messages','2','--warmup','1','--budget',str(budget)]
                self.assertEqual(gate.main(args),0)
                with mock.patch.dict(gate.os.environ,{'DART_VM_OPTIONS':'--new_gen_semi_max_size=1'}),contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):
                    gate.main(args+['--output',str(directory/'tuned-performance')])
                result=json.loads((directory/'output/summary.json').read_text())
                self.assertEqual(result['source_commit'],'a'*40)
                self.assertFalse(result['source_dirty'])
                self.assertIn('openssl_version',result)
                self.assertIn('tls_ca_sha256',result)
                self.assertEqual(len(result['results']),2)
                self.assertEqual(result['normal_warmup_messages_min'],1)
                with contextlib.redirect_stderr(io.StringIO()),self.assertRaises(SystemExit):
                    gate.main(args+['--output',str(directory/'wrong-protocol'),'--retention'])
                budgets['retention_protocol']='bounded_nursery_v1';budget.write_text(json.dumps(budgets))
                def complete(p,path,*_,**options):
                    return [dict(sample(p,path),warmup_messages=2,
                                 **({'memory_protocol':'bounded_nursery_v1'} if options.get('retention') else {}))]
                campaign.return_value.run.side_effect=complete
                self.assertEqual(gate.main(args+['--output',str(directory/'retention')]),0)
                collected=json.loads((directory/'retention/summary.json').read_text())
                self.assertEqual(collected['retention_protocol'],'bounded_nursery_v1')
                self.assertTrue(all(r['retention']['protocol']=='bounded_nursery_v1' for r in collected['results']))
                with mock.patch.object(campaign.return_value,'run',side_effect=lambda p,path,*_,**opts: [] if opts.get('retention') else complete(p,path)),self.assertRaisesRegex(ValueError,'retention matrix'):
                    gate.main(args+['--output',str(directory/'missing-retention')])
                self.assertFalse((directory/'missing-retention/summary.json').exists())
                with mock.patch.object(campaign.return_value,'run',side_effect=lambda p,path,*_,**opts: [dict(complete(p,path,**opts)[0],warmup_messages=1)] if opts.get('retention') else complete(p,path)),self.assertRaisesRegex(ValueError,'warm-up'):
                    gate.main(args+['--output',str(directory/'cold-retention')])
                with mock.patch.object(campaign.return_value,'run',side_effect=lambda p,path,*_: [dict(sample(p,path),warmup_messages=0)]),self.assertRaisesRegex(ValueError,'warm-up'):
                    gate.main(args+['--output',str(directory/'underwarmed')])
                calls=campaign.call_count
                with mock.patch.object(gate.platform,'machine',return_value='aarch64'),self.assertRaisesRegex(ValueError,'architecture/CPU count'):
                    gate.main(args+['--output',str(directory/'wrong-hardware')])
                self.assertEqual(campaign.call_count,calls)
                for direction in gate.DIRECTIONS:
                    budgets['profiles'][PROFILE['id']][direction]['max_peak_rss_bytes']=1
                budget.write_text(json.dumps(budgets))
                self.assertEqual(gate.main(args+['--output',str(directory/'failed')]),1)
                self.assertIn('FAIL: peak_rss',output.getvalue())
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
                    for extra in [['--runs','0'],['--messages','0'],['--warmup','0'],['--warmup-seconds','-1'],['--warmup-seconds','nan'],['--warmup-seconds','inf'],['--warmup-seconds','61'],['--shard','bad'],['--shard','1/1'],['--shard','0/33'],['--shard','-1/2'],['--overload-runs','0'],['--overload-messages','0'],['--overload-stall-ms','0'],['--overload-stall-ms','60001'],['--drain-seconds','-1'],['--profile','missing'],['--profile',PROFILE['id']]]:
                        with self.subTest(extra=extra),self.assertRaises(SystemExit):
                            gate.main(['--output',temporary,*extra])
                with mock.patch.dict(gate.os.environ,{'CONNECTANUM_NATIVE_LIB':str(library)+'missing'}),self.assertRaises(SystemExit):
                    gate.main(['--output',temporary])
            with mock.patch.object(sys,'argv',['run_mqtt_gateway_benchmark.py','--help']),contextlib.redirect_stdout(io.StringIO()),self.assertRaises(SystemExit):
                runpy.run_path(str(gate.ROOT/'tool/run_mqtt_gateway_benchmark.py'),run_name='__main__')


if __name__ == '__main__':
    unittest.main()
