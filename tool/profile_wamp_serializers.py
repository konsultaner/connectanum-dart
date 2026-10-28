#!/usr/bin/env python3
"""Retain CPU profiles and optional memory diagnostics; never acceptance."""
from __future__ import annotations
import argparse
import fcntl
import hashlib
import json
import os
import platform
from pathlib import Path
import re
import signal
import socket
import ssl
import subprocess
import threading
import urllib.request

import run_wamp_serializer_campaign as campaign
import wamp_serializer_extensions as extensions

PROFILE_CASES = {
    case['id']: {'client_impl': case['client_impl'], 'payload_construction': case['construction']}
    for case in campaign.primary_cases()
    if case['id'] in {
        'rpc_rawsocket_clear_dart_values',
        'rpc_rawsocket_clear_native_native_buffer',
        'rpc_rawsocket_clear_native_pre_encoded_span',
    }
}
PROFILE_CASES.update({
    case['id']: {'client_impl': case['client_impl'],
                 'payload_construction': case['construction'],
                 'payload_bytes': case['fields']['request_bytes']}
    for case in extensions.cases_for_shard('payload_sizes')
    if case['id'] == 'ext_08_payload_sizes'
})
PROFILE_CASES.update({
    case['id']: {'client_impl': case['client_impl'],
                 'payload_construction': case['construction'], 'mode': case['mode'],
                 'payload_bytes': case['fields']['request_bytes'], 'event_timeout_ms': 300000,
                 **{key: case['fields'][key] for key in
                    ('peer_serializer', 'ppt_scheme', 'ppt_serializer', 'ppt_cipher', 'ppt_keyid')}}
    for case in extensions.cases_for_shard('encrypted_progressive_results')
    if case['id'] == 'ext_44_encrypted_progressive_results'
})
PROFILE_CASES.update({
    case['id']: {
        'client_impl': case['client_impl'],
        'payload_construction': case['construction'],
        'mode': case['mode'],
        'payload_bytes': case['fields']['request_bytes'],
        'transport': case['transport'],
        'secure_transport': case['secure_transport'],
        'uri': case['fields']['path'],
        'peer_count': case['fields']['peer_count'],
        'ppt_scheme': case['fields'].get('ppt_scheme'),
        'ppt_serializer': case['fields'].get('ppt_serializer'),
        'ppt_cipher': case['fields'].get('ppt_cipher'),
        'ppt_keyid': case['fields'].get('ppt_keyid'),
    }
    for case in extensions.extension_cases()
    if case['id'] in {'ext_07_small_control', 'ext_22_progressive'}
})
DEFAULT_CASE = 'rpc_rawsocket_clear_native_native_buffer'
NATIVE_RUNTIME_THREADS = 1


def profile_target(case_id):
    if case_id not in PROFILE_CASES:
        raise ValueError(f'Unsupported CPU profile case: {case_id}')
    return dict(PROFILE_CASES[case_id])


CPU_PROBE = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  // Args: control URL, router service, client service, output, perf, target JSON.
  final services = {
    'router': await vmServiceConnectUri(Uri.parse(args[1]).replace(scheme: 'ws').resolve('ws').toString()),
    'client': await vmServiceConnectUri(Uri.parse(args[2]).replace(scheme: 'ws').resolve('ws').toString()),
  };
  final output = Directory(args[3]);
  final memory = args.length > 6 && args[6] == 'memory';
  final target = (jsonDecode(args[5]) as Map).cast<String, dynamic>();
  final windowTool = Uri.parse(__PROFILE_WINDOW_TOOL_URI__).toFilePath();
  Future<Map<String, int>> clockAnchor(VmService service) async {
    final before = DateTime.now().microsecondsSinceEpoch;
    final clock = (await service.getVMTimelineMicros()).timestamp!;
    final after = DateTime.now().microsecondsSinceEpoch;
    return {'wall_before_us': before, 'clock_us': clock, 'wall_after_us': after};
  }
  Future<Map<String, dynamic>> nativeClock() async {
    final result = await Process.run('python3', [windowTool, '--clock']);
    if (result.exitCode != 0) throw StateError('Native clock observation failed: ${result.stderr}');
    return (jsonDecode(result.stdout as String) as Map).cast<String, dynamic>();
  }
  final http = HttpClient()..badCertificateCallback = ((cert, host, port) => host == 'localhost');
  Future<Map<String, dynamic>> run(String codec, int milliseconds, String label) async {
    final scenario = {'transport': 'rawsocket', 'serializer': codec,
      'secure_transport': false, 'mode': 'rpc', 'uri': 'bench.rpc.echo',
      'iterations': 1000, 'minimum_duration_ms': milliseconds, 'concurrency': 1,
      'payload_bytes': 65536,
      'ppt_scheme': 'x_connectanum_bench_typed', 'ppt_serializer': codec, ...target};
    final request = await http.postUrl(Uri.parse(args[0]));
    request.headers.contentType = ContentType.json;
    final bodyBytes = utf8.encode(jsonEncode(scenario));
    File('${output.path}/$codec-$label-request.json').writeAsBytesSync(bodyBytes);
    request.contentLength = bodyBytes.length;
    request.add(bodyBytes);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    File('${output.path}/$codec-$label-http.json').writeAsStringSync(body);
    if (response.statusCode != 200) throw StateError('HTTP ${response.statusCode}: $body');
    return jsonDecode(body) as Map<String, dynamic>;
  }
  try {
    for (final codec in ['msgpack', 'flatbuffers', 'cbor']) {
      for (var pass = 0; pass < 3; pass++) await run(codec, 1000, 'warmup-$pass');
      final ids = <String, List<String>>{};
      final pids = <String, int>{};
      for (final entry in services.entries) {
        final vm = await entry.value.getVM();
        pids[entry.key] = vm.pid!;
        ids[entry.key] = [for (final isolate in vm.isolates!) if (isolate.isSystemIsolate != true) isolate.id!];
        await entry.value.setFlag('profiler', 'true');
      }
      if (pids.values.toSet().length != 2) throw StateError('Client/router profiling PIDs must differ');
      Future<void> captureMemory(String stage) async {
        if (!memory) return;
        for (final entry in services.entries) {
          final vm = await entry.value.getVM();
          final currentIds = [for (final isolate in vm.isolates!) if (isolate.isSystemIsolate != true) isolate.id!]..sort();
          final expectedIds = ids[entry.key]!.toList()..sort();
          if (vm.pid != pids[entry.key] || jsonEncode(currentIds) != jsonEncode(expectedIds) || currentIds.isEmpty) {
            throw StateError('Memory snapshot process or isolate set changed');
          }
          final isolates = <Map<String, dynamic>>[];
          for (final id in currentIds) {
            // Forced collections occur only after the diagnostic workload and
            // CPU sampling have finished. These are never acceptance metrics.
            final allocation = await entry.value.getAllocationProfile(id, gc: stage == 'after_gc_request');
            final usage = await entry.value.getMemoryUsage(id);
            final isolate = vm.isolates!.singleWhere((value) => value.id == id);
            isolates.add({'id': id, 'group_id': isolate.isolateGroupId!,
              'allocation': allocation.toJson(), 'usage': usage.toJson()});
          }
          final pid = pids[entry.key]!;
          File('${output.path}/$codec-${entry.key}-memory-$stage.json').writeAsStringSync(jsonEncode({
            'kind': 'diagnostic_memory_never_acceptance', 'codec': codec,
            'process': entry.key, 'pid': pid, 'stage': stage,
            'captured_at_us': DateTime.now().microsecondsSinceEpoch,
            'gc_requested': stage == 'after_gc_request', 'isolates': isolates,
            'linux_smaps_rollup': Platform.isLinux ? await File('/proc/$pid/smaps_rollup').readAsString() : null,
          }));
        }
      }
      await captureMemory('before_workload');
      final beforeClocks = <String, Map<String, int>>{};
      for (final entry in services.entries) {
        for (final id in ids[entry.key]!) await entry.value.clearCpuSamples(id);
        beforeClocks[entry.key] = await clockAnchor(entry.value);
      }
      Process? perf;
      Future<void>? perfOutput, perfErrors, perfStopping;
      final perfLog = StringBuffer();
      Future<void> stopPerf() => perfStopping ??= () async {
        final child = perf;
        if (child == null) return;
        try { await child.stdin.close(); } catch (error) { perfLog.writeln(error); }
        late int code;
        try {
          code = await child.exitCode.timeout(const Duration(seconds: 10));
        } on TimeoutException {
          child.kill(ProcessSignal.sigterm);
          try {
            code = await child.exitCode.timeout(const Duration(seconds: 5));
          } on TimeoutException {
            child.kill(ProcessSignal.sigkill);
            code = await child.exitCode.timeout(const Duration(seconds: 5));
          }
        }
        await Future.wait([if (perfOutput != null) perfOutput!, if (perfErrors != null) perfErrors!]);
        File('${output.path}/$codec-perf-record.log').writeAsStringSync(perfLog.toString());
        if (code != 0) throw StateError('perf record exit $code');
      }();
      final nativeBefore = args[4].isEmpty ? null : await nativeClock();
      final afterClocks = <String, Map<String, int>>{};
      Map<String, dynamic>? nativeAfter;
      late Map<String, dynamic> report;
      late int captureStartedAtUs, captureCompletedAtUs;
      try {
        if (args[4].isNotEmpty) {
          final ready = Completer<void>();
          final child = await Process.start('sudo', ['-n', args[4], 'record',
            '--clockid', 'CLOCK_MONOTONIC', '-e', 'cpu-clock', '-F', '999', '--call-graph', 'dwarf',
            '-p', pids.values.join(','), '-o', '${output.path}/$codec-native.perf', '--',
            'python3', '-c', "import sys; print('PERF_READY', flush=True); sys.stdin.buffer.read(1)"]);
          perf = child;
          perfOutput = child.stdout.transform(utf8.decoder).transform(const LineSplitter()).forEach((line) {
            perfLog.writeln(line);
            if (line.trim() == 'PERF_READY' && !ready.isCompleted) ready.complete();
          });
          perfErrors = child.stderr.transform(utf8.decoder).forEach(perfLog.write);
          unawaited(child.exitCode.then((code) {
            if (!ready.isCompleted) ready.completeError(StateError('perf exited before readiness: $code'));
          }));
          await ready.future.timeout(const Duration(seconds: 15));
        }
        captureStartedAtUs = DateTime.now().microsecondsSinceEpoch;
        report = await run(codec, 30000, 'profiled');
        for (final entry in services.entries) {
          afterClocks[entry.key] = await clockAnchor(entry.value);
        }
        nativeAfter = args[4].isEmpty ? null : await nativeClock();
        captureCompletedAtUs = DateTime.now().microsecondsSinceEpoch;
      } finally {
        await stopPerf();
      }
      final samples = report['samples'] as List;
      final dataStartedAtUs = samples.map((s) => s['started_at_us'] as int).reduce((a, b) => a < b ? a : b);
      final dataCompletedAtUs = samples.map((s) => s['completed_at_us'] as int).reduce((a, b) => a > b ? a : b);
      final requestFile = File('${output.path}/$codec-window-request.json');
      requestFile.writeAsStringSync(jsonEncode({
        'capture_started_at_us': captureStartedAtUs, 'capture_completed_at_us': captureCompletedAtUs,
        'data_started_at_us': dataStartedAtUs, 'data_completed_at_us': dataCompletedAtUs,
        'vm_before': beforeClocks, 'vm_after': afterClocks,
        'native_before': nativeBefore, 'native_after': nativeAfter,
      }));
      final windowFile = File('${output.path}/$codec-sampling-window.json');
      final selection = await Process.run('python3', [windowTool, '--input', requestFile.path, '--output', windowFile.path]);
      if (selection.exitCode != 0) throw StateError('CPU window selection failed: ${selection.stderr}');
      final window = (jsonDecode(windowFile.readAsStringSync()) as Map).cast<String, dynamic>();
      final ranges = window['vm_clock_ranges'] as Map;
      for (final entry in services.entries) {
        final range = ranges[entry.key] as Map;
        final origin = range['origin_us'] as int, extent = range['extent_us'] as int;
        var roleSamples = 0;
        for (final id in ids[entry.key]!) {
          final cpu = await entry.value.getCpuSamples(id, origin, extent);
          if (cpu.samples == null || cpu.sampleCount != cpu.samples!.length) {
            throw StateError('CPU sample inventory is incomplete');
          }
          for (final sample in cpu.samples!) {
            final timestamp = sample.timestamp;
            if (timestamp == null || timestamp < origin || timestamp > origin + extent) {
              throw StateError('CPU sample is outside the selected operation interval');
            }
          }
          roleSamples += cpu.sampleCount ?? 0;
          File('${output.path}/$codec-${entry.key}-${id.replaceAll('/', '_')}.json')
            .writeAsStringSync(jsonEncode(cpu.toJson()));
          final functions = (cpu.functions ?? []).toList()
            ..sort((a, b) => (b.exclusiveTicks ?? 0).compareTo(a.exclusiveTicks ?? 0));
          print(jsonEncode({'codec': codec, 'process': entry.key, 'pid': pids[entry.key],
            'isolate': id, 'sample_count': cpu.sampleCount,
            'native_perf': args[4].isNotEmpty ? 'collected' : 'not_measured',
            'top': [for (final f in functions.take(25)) {'name': f.function?.name,
              'kind': f.kind, 'url': f.resolvedUrl, 'exclusive': f.exclusiveTicks, 'inclusive': f.inclusiveTicks}]}));
        }
        if (roleSamples == 0) throw StateError('No CPU samples inside the operation interval for ${entry.key}');
      }
      await captureMemory('after_workload');
      await captureMemory('after_gc_request');
      if (args[4].isNotEmpty) {
        final data = '${output.path}/$codec-native.perf';
        final header = await Process.run('sudo', ['-n', args[4], 'report', '--header-only', '-i', data]);
        File('${output.path}/$codec-native-header.txt').writeAsStringSync('${header.stdout}\n${header.stderr}');
        if (header.exitCode != 0) throw StateError('perf header exit ${header.exitCode}');
        if (Platform.isLinux) {
          for (final role in ['router', 'client']) {
            final pid = pids[role]!;
            final source = File('/tmp/perf-$pid.map');
            if (!source.existsSync()) throw StateError('$role JIT symbol map missing for PID $pid');
            final mapping = source.readAsBytesSync();
            if (mapping.isEmpty) throw StateError('$role JIT symbol map empty for PID $pid');
            File('${output.path}/$codec-$role.perf-map').writeAsBytesSync(mapping);
            File('${output.path}/$codec-$role-perf-symbols.json').writeAsStringSync(jsonEncode({
              'pid': pid, 'source': source.path, 'status': 'retained',
              'captured_at_us': DateTime.now().microsecondsSinceEpoch,
            }));
          }
        }
        for (final scope in ['combined', 'router', 'client']) {
          for (final children in [false, true]) {
            final report = await Process.run('sudo', ['-n', args[4], 'report', '--stdio',
              '--time', (window['native_clock_range'] as Map)['perf_time_range'] as String,
              if (scope != 'combined') ...['--pid', '${pids[scope]}'],
              if (!children) '--no-children', '--percent-limit', '0.1', '-i', data]);
            final suffix = scope == 'combined' ? '' : '-$scope';
            File('${output.path}/$codec-native$suffix-${children ? 'inclusive' : 'leaf'}.txt')
              .writeAsStringSync('${report.stdout}\n${report.stderr}');
            if (report.exitCode != 0) throw StateError('perf report $scope exit ${report.exitCode}');
            if (scope == 'combined') {
              final count = RegExp(r'#\s*Samples:\s*([0-9.]+)').firstMatch(report.stdout as String);
              final rows = RegExp(r'^\s*([0-9.]+)%\s+\S', multiLine: true)
                .allMatches(report.stdout as String)
                .any((row) => (double.tryParse(row.group(1)!) ?? 0) > 0);
              if (count == null || (double.tryParse(count.group(1)!) ?? 0) <= 0 || !rows) {
                throw StateError('Native perf has no samples inside the operation interval');
              }
            }
          }
          if (scope != 'combined') {
            final trace = await Process.run('sudo', ['-n', args[4], 'script',
              '--time', (window['native_clock_range'] as Map)['perf_time_range'] as String,
              '--pid', '${pids[scope]}', '-F', 'pid,tid,time,ip,sym,dso', '-i', data]);
            File('${output.path}/$codec-native-$scope-script.txt')
              .writeAsStringSync('${trace.stdout}\n${trace.stderr}');
            if (trace.exitCode != 0 || (trace.stdout as String).trim().isEmpty) {
              throw StateError('Native perf script $scope is missing or failed (${trace.exitCode})');
            }
          }
        }
      }
      window['native_perf_scope'] = args[4].isEmpty ? 'not_measured' : 'whole-request raw capture; reports filtered to interior data interval';
      window['profiles_verified'] = true;
      windowFile.writeAsStringSync(jsonEncode(window));
    }
  } finally {
    http.close(force: true);
    for (final service in services.values) await service.dispose();
  }
}
'''
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--native-lib', required=True, type=Path)
    parser.add_argument('--perf', default='', help='Absolute Linux perf executable; omitted native sampling is labelled unmeasured')
    parser.add_argument('--dart', default='dart')
    parser.add_argument('--memory', action='store_true',
                        help='Diagnostic-only class heaps and Linux smaps before/after workload and post-GC; never acceptance')
    parser.add_argument('--case', dest='profile_case', choices=sorted(PROFILE_CASES), default=DEFAULT_CASE,
                        help='Canonical diagnostic case to profile; never parity acceptance')
    return parser.parse_args(argv)


def main():
    args = parse_args()
    with campaign.LOCK.open('a') as lease:
        fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if campaign.interfering_jobs():
            raise RuntimeError('Build/test/mutation jobs are running; CPU profiling was not started')
        return profile(args)


def memory_snapshot_audit(output: Path, router_pid: int, requested: bool, linux: bool) -> dict:
    """Validate attribution of diagnostic snapshots; do not sum isolate heaps."""
    result = {'requested': requested, 'status': 'not_requested', 'snapshots': [], 'findings': [],
              'scope': 'Diagnostic only. Isolate heaps can share a group and must not be summed. '
                       'A GC request does not guarantee collection or finalizer completion.'}
    if not requested:
        return result
    identities = {}
    for codec in ('msgpack', 'flatbuffers', 'cbor'):
        for process in ('router', 'client'):
            previous = 0
            for stage in ('before_workload', 'after_workload', 'after_gc_request'):
                path = output / f'{codec}-{process}-memory-{stage}.json'
                try:
                    data = json.loads(path.read_text())
                    if (data['kind'], data['codec'], data['process'], data['stage']) != (
                            'diagnostic_memory_never_acceptance', codec, process, stage):
                        raise ValueError('snapshot attribution differs')
                    pid, timestamp = data['pid'], data['captured_at_us']
                    if type(pid) is not int or pid <= 0 or (pid == router_pid) != (process == 'router'):
                        raise ValueError('invalid or foreign process PID')
                    if type(timestamp) is not int or timestamp <= previous:
                        raise ValueError('snapshot timestamps must increase')
                    previous = timestamp
                    if type(data['gc_requested']) is not bool or data['gc_requested'] != (stage == 'after_gc_request'):
                        raise ValueError('GC request attribution differs')
                    isolates = data['isolates']
                    if not isinstance(isolates, list) or not isolates:
                        raise ValueError('missing application isolates')
                    ids = []
                    for item in isolates:
                        if not isinstance(item['id'], str) or not item['id'].startswith('isolates/'):
                            raise ValueError('invalid isolate ID')
                        if not isinstance(item['group_id'], str) or not item['group_id'].startswith('isolateGroups/'):
                            raise ValueError('missing isolate group attribution')
                        ids.append((item['id'], item['group_id']))
                        for key in ('externalUsage', 'heapCapacity', 'heapUsage'):
                            value = item['usage'][key]
                            if type(value) is not int or value < 0:
                                raise ValueError('unmeasured heap usage')
                        members = item['allocation']['members']
                        if not isinstance(members, list) or not members:
                            raise ValueError('missing class heap records')
                        for member in members:
                            if not isinstance(member['class']['name'], str):
                                raise ValueError('missing class attribution')
                            for key in ('bytesCurrent', 'instancesCurrent'):
                                if type(member[key]) is not int or member[key] < 0:
                                    raise ValueError('unmeasured class heap')
                    if len({item[0] for item in ids}) != len(ids):
                        raise ValueError('duplicate isolate ID')
                    identity = (pid, tuple(sorted(ids)))
                    if identity != identities.setdefault(process, identity):
                        raise ValueError('process or application isolate set changed')
                    smaps = data['linux_smaps_rollup']
                    if linux:
                        fields = {}
                        for line in smaps.splitlines():
                            if match := re.fullmatch(r'(Rss|Anonymous|Private_Dirty|Private_Clean|Shared_Clean|Swap):\s+(\d+) kB', line):
                                key, value = match.groups()
                                if key in fields:
                                    raise ValueError('duplicate smaps field')
                                fields[key] = int(value) * 1024
                        if len(fields) != 6 or fields['Rss'] <= 0:
                            raise ValueError('missing Linux smaps fields or unsupported units')
                    elif smaps is not None:
                        raise ValueError('unexpected Linux memory attribution')
                    else:
                        fields = None
                    result['snapshots'].append({'file': path.name, 'sha256': digest(path), 'pid': pid,
                                                'isolates': ids, 'linux_smaps_bytes': fields})
                except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
                    result['findings'].append(f'{path.name}: {error}')
    result['status'] = 'incomplete' if result['findings'] else 'retained'
    return result


def _symbol_map_audit(output: Path, pid: int, requested: bool, role: str) -> dict:
    result = {'requested': requested, 'status': 'not_requested', 'maps': [], 'findings': [],
              'limitation': 'A perf map snapshot does not guarantee complete unwinding or unique JIT address history.'}
    if not requested:
        return result
    for codec in ('cbor', 'msgpack', 'flatbuffers'):
        path = output / f'{codec}-{role}.perf-map'
        metadata = output / f'{codec}-{role}-perf-symbols.json'
        try:
            info = json.loads(metadata.read_text())
            if not isinstance(info, dict):
                raise ValueError('symbol attribution must be an object')
            if type(info.get('pid')) is not int or info['pid'] != pid or info.get('source') != f'/tmp/perf-{pid}.map' or info.get('status') != 'retained':
                raise ValueError('foreign PID or invalid symbol-map attribution')
            raw = path.read_bytes()
            if not raw:
                raise ValueError('empty symbol map')
            symbols = {}
            ambiguous = set()
            count = 0
            for line in raw.decode('utf-8').splitlines():
                address, size, name = line.split(maxsplit=2)
                start, length = int(address, 16), int(size, 16)
                if start <= 0 or length <= 0 or not name or '\x00' in name:
                    raise ValueError('invalid symbol map record')
                if start in symbols and symbols[start] != (length, name):
                    ambiguous.add(start)
                symbols[start] = (length, name)
                count += 1
            if not count:
                raise ValueError('no symbol records')
            result['maps'].append({'codec': codec, 'pid': pid, 'path': path.name,
                'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw), 'entries': count,
                'ambiguous_start_addresses': len(ambiguous)})
        except (OSError, ValueError, TypeError, KeyError) as error:
            result['findings'].append(f'{codec}: {error}')
    result['status'] = 'retained' if not result['findings'] else 'incomplete'
    return result


def router_symbol_map_audit(output: Path, pid: int, requested: bool) -> dict:
    return {**_symbol_map_audit(output, pid, requested, 'router'),
            'client_jit_symbols': 'not_requested'}


def client_symbol_map_audit(output: Path, router_pid: int, requested: bool) -> dict:
    if not requested:
        return _symbol_map_audit(output, 0, False, 'client')
    try:
        pids = [json.loads((output / f'{codec}-client-perf-symbols.json').read_text())['pid']
                for codec in ('cbor', 'msgpack', 'flatbuffers')]
        if any(type(pid) is not int or pid <= 0 or pid == router_pid for pid in pids) or len(set(pids)) != 1:
            raise ValueError('client PID must be stable, positive and distinct from router PID')
    except (OSError, ValueError, KeyError, TypeError) as error:
        return {'requested': True, 'status': 'incomplete', 'maps': [], 'findings': [str(error)]}
    return _symbol_map_audit(output, pids[0], True, 'client')


def write_profile_worker_launcher(output: Path, dart: str) -> Path:
    launcher = output / 'profile-client'
    launcher.write_text('''#!/usr/bin/env python3
import os, sys
dart = ''' + repr(dart) + '''
args = sys.argv[1:]
split = args.index('--realm')
prefixes = ('--timeline_streams=', '--timeline_recorder=', '--observe=')
if any(not (flag.startswith(prefixes) or flag == '--no-pause-isolates-on-exit') for flag in args[:split]):
    raise SystemExit('Unexpected diagnostic worker VM flag')
os.execvp(dart, [dart, '--generate-perf-events-symbols', *args[:split],
               'run', 'connectanum_bench:wamp_client_worker', *args[split:]])
''')
    launcher.chmod(0o700)
    return launcher


def profile(args):
    root = Path(__file__).resolve().parents[1]
    target = profile_target(args.profile_case)
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=False)
    library = args.native_lib.resolve(strict=True)
    library_digest = digest(library)
    paths = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root).decode().split('\0')
    inputs = {p: digest(root/p) for p in paths if p and (root/p).is_file()}
    # These ignored files select the actual resolved dependencies and package
    # roots; tracked-source invariance alone does not freeze the execution.
    resolved_files = {}
    # The controller and workload driver here are Dart; native/bench's Rust
    # driver is not built or executed and has no resolved lock on fresh runners.
    for p in ('pubspec.lock', 'native/transport/Cargo.lock',
              '.dart_tool/package_config.json'):
        data = (root/p).read_bytes()
        retained = output / 'resolved-inputs' / p.replace('/', '__').lstrip('.')
        retained.parent.mkdir(exist_ok=True)
        retained.write_bytes(data)
        inputs[p] = hashlib.sha256(data).hexdigest()
        resolved_files[p] = str(retained.relative_to(output))
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    config = json.loads((root/'native/bench/bench_router.json').read_text()); ports = []
    for listener in config['router']['listeners']:
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
        ports.append(port); listener['endpoint'] = f'127.0.0.1:{port}'
        if 'http3' in listener['protocols']:
            listener['protocols'].remove('http3'); listener['http'].pop('http3', None)
    (output/'router.json').write_text(json.dumps(config, indent=2)+'\n')
    (output/'probe.dart').write_text(CPU_PROBE.replace('__PROFILE_WINDOW_TOOL_URI__',
                                                   json.dumps((root/'tool/wamp_profile_window.py').as_uri())))
    env = {**os.environ, 'CONNECTANUM_SKIP_NATIVE_BUILD': '1', 'CONNECTANUM_BENCH_WAMP_REUSE_WORKER': '1',
           'CONNECTANUM_BENCH_WAMP_VM_METRICS': '1', 'CONNECTANUM_NATIVE_LIB': str(library),
           'CONNECTANUM_NATIVE_RUNTIME_THREADS': str(NATIVE_RUNTIME_THREADS),
           'CONNECTANUM_BENCH_PROFILE_WORKER_URI': str(output/'worker-uri.txt')}
    router_symbols = bool(args.perf and platform.system() == 'Linux')
    worker = write_profile_worker_launcher(output, args.dart) if router_symbols else None
    worker_hash = digest(worker) if worker else None
    command = [args.dart, *(['--generate-perf-events-symbols'] if router_symbols else []), '--observe=0/127.0.0.1', '--profiler', '--no-pause-isolates-on-exit',
               'run', 'packages/connectanum_bench/tool/bench_main.dart', '--router-config', str(output/'router.json'),
               '--wamp-worker', str(worker) if worker else 'connectanum_bench:wamp_client_worker']
    process = subprocess.Popen(command, cwd=root, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, start_new_session=True)
    ready = threading.Event()
    def read():
        with (output/'server.log').open('w') as log:
            for line in process.stdout:
                log.write(line); log.flush()
                if 'The Dart VM service is listening on ' in line and not (output/'server-uri.txt').exists():
                    (output/'server-uri.txt').write_text(line.split('The Dart VM service is listening on ')[1].strip())
                if line.strip().endswith('READY'): ready.set()
    thread = threading.Thread(target=read, daemon=True); thread.start()
    status = 1
    interference = []
    monitoring_stop = threading.Event()
    def watch():
        while not monitoring_stop.wait(2):
            interference.extend(campaign.interfering_jobs(process.pid))
    monitoring = None
    try:
        if not ready.wait(120): raise RuntimeError('profiling server did not become ready')
        control = f'https://localhost:{ports[0]}/bench/wamp'
        scenario = dict(transport='rawsocket', serializer='flatbuffers', secure_transport=False,
                        mode='rpc', uri='bench.rpc.echo', iterations=10, concurrency=1, payload_bytes=65536,
                        ppt_scheme='x_connectanum_bench_typed', ppt_serializer='flatbuffers')
        scenario.update(target)
        (output/'initial-request.json').write_text(json.dumps(scenario, indent=2)+'\n')
        request = urllib.request.Request(control, data=json.dumps(scenario).encode(), headers={'content-type': 'application/json'})
        with urllib.request.urlopen(request, context=ssl.create_default_context(cafile=str(root/'native/bench/bench_tls.crt')), timeout=120) as response:
            (output/'initial-http.json').write_bytes(response.read())
        interference.extend(campaign.interfering_jobs(process.pid))
        monitoring = threading.Thread(target=watch, daemon=True); monitoring.start()
        with (output/'cpu-summary.jsonl').open('w') as log:
            result = subprocess.run([args.dart, '--packages='+str(root/'.dart_tool/package_config.json'), str(output/'probe.dart'),
                control, (output/'server-uri.txt').read_text(), (output/'worker-uri.txt').read_text(), str(output), args.perf, json.dumps(target),
                *(['memory'] if args.memory else [])],
                cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=300)
        status = result.returncode
    finally:
        monitoring_stop.set()
        if monitoring is not None: monitoring.join(timeout=3)
        try:
            process.stdin.write('stop\n'); process.stdin.flush(); process.wait(timeout=30)
        except (OSError, subprocess.TimeoutExpired):
            if process.poll() is None: os.killpg(process.pid, signal.SIGTERM)
            try: process.wait(timeout=10)
            except subprocess.TimeoutExpired: os.killpg(process.pid, signal.SIGKILL); process.wait()
        group_stopped = campaign.stop_process_group(process)
        thread.join(timeout=5)
        changed = [p for p, h in inputs.items() if not (root/p).is_file() or digest(root/p) != h]
        after = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
        symbols = router_symbol_map_audit(output, process.pid, router_symbols)
        client_symbols = client_symbol_map_audit(output, process.pid, router_symbols)
        symbols['client_jit_symbols'] = client_symbols['status']
        launcher_unchanged = worker is None or (worker.is_file() and digest(worker) == worker_hash)
        memory = memory_snapshot_audit(output, process.pid, args.memory, platform.system() == 'Linux')
        audit = {'kind': 'cpu_profile_only_never_acceptance', 'case_id': args.profile_case,
                 'requested_configuration': target, 'head': head, 'inputs': inputs,
                 'native_runtime_threads': NATIVE_RUNTIME_THREADS,
                 'cpu_window_scope': 'posthoc interior data interval; VM clocks calibrated independently; native perf CLOCK_MONOTONIC filtered',
                 'resolved_input_files': resolved_files,
                 'inputs_unchanged': not changed and head == after, 'changed': changed,
                 'native_library_sha256': library_digest, 'native_library_unchanged': digest(library) == library_digest,
                 'router_perf_symbols': symbols,
                 'client_perf_symbols': client_symbols,
                 'client_launcher': {'path': worker.name if worker else None,
                                     'sha256': worker_hash, 'unchanged': launcher_unchanged},
                 'memory_snapshots': memory,
                 'platform': platform.uname()._asdict(), 'perf': args.perf or 'not_measured',
                 'perf_version': subprocess.check_output([args.perf, '--version'], text=True).strip() if args.perf else None,
                 'interference_detection': 'linux_proc' if Path('/proc').is_dir() else 'not_measured',
                 'probe_exit': status, 'server_exit': process.returncode, 'command': command,
                 'process_group_stopped': group_stopped, 'interference_observations': interference,
                 'dart_version': subprocess.check_output([args.dart, '--version'], text=True).strip(),
                 'rust_flags': os.environ.get('RUSTFLAGS'),
                 'limitation': 'Profiling perturbs execution. Router/client JIT maps and per-PID reports are retained for Linux perf; symbols/unwinding may remain incomplete. Dart samples can include native/blocking stacks and are not CPU-cycle attribution.'}
        (output/'source-audit.json').write_text(json.dumps(audit, indent=2)+'\n')
    return status or process.returncode or (0 if audit['inputs_unchanged'] and audit['native_library_unchanged'] and launcher_unchanged and group_stopped and not interference and not symbols['findings'] and not client_symbols['findings'] and not memory['findings'] else 1)


if __name__ == '__main__':
    raise SystemExit(main())
