#!/usr/bin/env python3
"""Retain Dart and optional Linux perf CPU profiles; never performance acceptance."""
from __future__ import annotations
import argparse
import fcntl
import hashlib
import json
import os
import platform
from pathlib import Path
import signal
import socket
import ssl
import subprocess
import threading
import urllib.request

import run_wamp_serializer_campaign as campaign

CPU_PROBE = r'''
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  final services = {
    'router': await vmServiceConnectUri(Uri.parse(args[1]).replace(scheme: 'ws').resolve('ws').toString()),
    'client': await vmServiceConnectUri(Uri.parse(args[2]).replace(scheme: 'ws').resolve('ws').toString()),
  };
  final output = Directory(args[3]);
  final http = HttpClient()..badCertificateCallback = ((cert, host, port) => host == 'localhost');
  Future<Map<String, dynamic>> run(String codec, int milliseconds, String label) async {
    final scenario = {'transport': 'rawsocket', 'serializer': codec, 'client_impl': 'native',
      'secure_transport': false, 'mode': 'rpc', 'uri': 'bench.rpc.echo',
      'iterations': 1000, 'minimum_duration_ms': milliseconds, 'concurrency': 1,
      'payload_bytes': 65536, 'payload_construction': 'native_buffer',
      'ppt_scheme': 'x_connectanum_bench_typed', 'ppt_serializer': codec};
    final request = await http.postUrl(Uri.parse(args[0]));
    request.headers.contentType = ContentType.json;
    final bodyBytes = utf8.encode(jsonEncode(scenario));
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
      final pending = run(codec, 30000, 'profiled');
      pending.ignore();
      await Future<void>.delayed(const Duration(seconds: 3));
      final starts = <String, int>{};
      for (final entry in services.entries) {
        for (final id in ids[entry.key]!) await entry.value.clearCpuSamples(id);
        starts[entry.key] = (await entry.value.getVMTimelineMicros()).timestamp!;
      }
      final samplingStartedAtUs = DateTime.now().microsecondsSinceEpoch;
      if (args[4].isNotEmpty) {
        final data = '${output.path}/$codec-native.perf';
        final result = await Process.run('sudo', ['-n', args[4], 'record', '-e', 'cpu-clock',
          '-F', '999', '--call-graph', 'dwarf', '-p', pids.values.join(','), '-o', data, '--', 'sleep', '5']);
        File('${output.path}/$codec-perf-record.log').writeAsStringSync('${result.stdout}\n${result.stderr}');
        if (result.exitCode != 0) throw StateError('perf record exit ${result.exitCode}');
      } else {
        await Future<void>.delayed(const Duration(seconds: 5));
      }
      for (final entry in services.entries) {
        final end = (await entry.value.getVMTimelineMicros()).timestamp!;
        for (final id in ids[entry.key]!) {
          final cpu = await entry.value.getCpuSamples(id, starts[entry.key]!, end - starts[entry.key]!);
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
      }
      final samplingCompletedAtUs = DateTime.now().microsecondsSinceEpoch;
      final report = await pending;
      final samples = report['samples'] as List;
      final dataStartedAtUs = samples.map((s) => s['started_at_us'] as int).reduce((a, b) => a < b ? a : b);
      final dataCompletedAtUs = samples.map((s) => s['completed_at_us'] as int).reduce((a, b) => a > b ? a : b);
      final covered = dataStartedAtUs <= samplingStartedAtUs && dataCompletedAtUs >= samplingCompletedAtUs;
      File('${output.path}/$codec-sampling-window.json').writeAsStringSync(jsonEncode({
        'sampling_started_at_us': samplingStartedAtUs, 'sampling_completed_at_us': samplingCompletedAtUs,
        'data_started_at_us': dataStartedAtUs, 'data_completed_at_us': dataCompletedAtUs,
        'sampling_inside_actual_data_window': covered,
      }));
      if (!covered) throw StateError('CPU sampling was outside the actual operation window');
      if (args[4].isNotEmpty) {
        final data = '${output.path}/$codec-native.perf';
        for (final children in [false, true]) {
          final report = await Process.run('sudo', ['-n', args[4], 'report', '--stdio',
            if (!children) '--no-children', '--percent-limit', '0.5', '-i', data]);
          File('${output.path}/$codec-native-${children ? 'inclusive' : 'leaf'}.txt')
            .writeAsStringSync('${report.stdout}\n${report.stderr}');
          if (report.exitCode != 0) throw StateError('perf report exit ${report.exitCode}');
        }
      }
    }
  } finally {
    http.close(force: true);
    for (final service in services.values) await service.dispose();
  }
}
'''
WORKER = r'''
import 'dart:developer';
import 'dart:io';
import __WORKER_URI__ as worker;
Future<void> main(List<String> args) async {
  final uri = (await Service.getInfo()).serverUri!;
  File(Platform.environment['CONNECTANUM_BENCH_PROFILE_WORKER_URI']!).writeAsStringSync(uri.toString());
  await worker.main(args);
}
'''


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--native-lib', required=True, type=Path)
    parser.add_argument('--perf', default='', help='Absolute Linux perf executable; omitted native sampling is labelled unmeasured')
    parser.add_argument('--dart', default='dart')
    args = parser.parse_args()
    with campaign.LOCK.open('a') as lease:
        fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if campaign.interfering_jobs():
            raise RuntimeError('Build/test/mutation jobs are running; CPU profiling was not started')
        return profile(args)


def profile(args):
    root = Path(__file__).resolve().parents[1]
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=False)
    library = args.native_lib.resolve(strict=True)
    library_digest = digest(library)
    paths = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=root).decode().split('\0')
    inputs = {p: digest(root/p) for p in paths if p and (root/p).is_file()}
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    config = json.loads((root/'native/bench/bench_router.json').read_text()); ports = []
    for listener in config['router']['listeners']:
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
        ports.append(port); listener['endpoint'] = f'127.0.0.1:{port}'
        if 'http3' in listener['protocols']:
            listener['protocols'].remove('http3'); listener['http'].pop('http3', None)
    (output/'router.json').write_text(json.dumps(config, indent=2)+'\n')
    (output/'probe.dart').write_text(CPU_PROBE)
    worker_uri = (root/'packages/connectanum_bench/tool/wamp_client_main.dart').as_uri()
    (output/'worker.dart').write_text(WORKER.replace('__WORKER_URI__', json.dumps(worker_uri)))
    env = {**os.environ, 'CONNECTANUM_SKIP_NATIVE_BUILD': '1', 'CONNECTANUM_BENCH_WAMP_REUSE_WORKER': '1',
           'CONNECTANUM_BENCH_WAMP_VM_METRICS': '1', 'CONNECTANUM_NATIVE_LIB': str(library),
           'CONNECTANUM_BENCH_PROFILE_WORKER_URI': str(output/'worker-uri.txt')}
    command = [args.dart, '--observe=0/127.0.0.1', '--profiler', '--no-pause-isolates-on-exit',
               'run', 'packages/connectanum_bench/tool/bench_main.dart', '--router-config', str(output/'router.json'),
               '--wamp-worker', str(output/'worker.dart')]
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
        scenario = dict(transport='rawsocket', serializer='flatbuffers', client_impl='native', secure_transport=False,
                        mode='rpc', uri='bench.rpc.echo', iterations=10, concurrency=1, payload_bytes=65536,
                        payload_construction='native_buffer', ppt_scheme='x_connectanum_bench_typed', ppt_serializer='flatbuffers')
        request = urllib.request.Request(control, data=json.dumps(scenario).encode(), headers={'content-type': 'application/json'})
        with urllib.request.urlopen(request, context=ssl.create_default_context(cafile=str(root/'native/bench/bench_tls.crt')), timeout=120) as response:
            (output/'initial-http.json').write_bytes(response.read())
        interference.extend(campaign.interfering_jobs(process.pid))
        monitoring = threading.Thread(target=watch, daemon=True); monitoring.start()
        with (output/'cpu-summary.jsonl').open('w') as log:
            result = subprocess.run([args.dart, '--packages='+str(root/'.dart_tool/package_config.json'), str(output/'probe.dart'),
                control, (output/'server-uri.txt').read_text(), (output/'worker-uri.txt').read_text(), str(output), args.perf],
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
        audit = {'kind': 'cpu_profile_only_never_acceptance', 'head': head, 'inputs': inputs,
                 'inputs_unchanged': not changed and head == after, 'changed': changed,
                 'native_library_sha256': library_digest, 'native_library_unchanged': digest(library) == library_digest,
                 'platform': platform.uname()._asdict(), 'perf': args.perf or 'not_measured',
                 'perf_version': subprocess.check_output([args.perf, '--version'], text=True).strip() if args.perf else None,
                 'interference_detection': 'linux_proc' if Path('/proc').is_dir() else 'not_measured',
                 'probe_exit': status, 'server_exit': process.returncode, 'command': command,
                 'process_group_stopped': group_stopped, 'interference_observations': interference,
                 'dart_version': subprocess.check_output([args.dart, '--version'], text=True).strip(),
                 'rust_flags': os.environ.get('RUSTFLAGS'),
                 'limitation': 'Profiling perturbs execution; native perf may leave Dart JIT addresses unresolved. Dart CPU samples are retained separately.'}
        (output/'source-audit.json').write_text(json.dumps(audit, indent=2)+'\n')
    return status or process.returncode or (0 if audit['inputs_unchanged'] and audit['native_library_unchanged'] and group_stopped and not interference else 1)


if __name__ == '__main__':
    raise SystemExit(main())
