@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectanum_bench/src/dart_vm_metrics.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service_io.dart';

const rss = DartVmMetricsRssSnapshot(currentRssBytes: 1024, peakRssBytes: 2048);

void main() {
  test(
    'direct observer preserves allocation history in a real child VM',
    () async {
      var root = Directory.current.absolute;
      while (!File(
        '${root.path}/packages/connectanum_bench/pubspec.yaml',
      ).existsSync()) {
        if (root.parent.path == root.path) {
          throw StateError('Workspace missing');
        }
        root = root.parent;
      }
      final process = await Process.start(Platform.resolvedExecutable, [
        '--packages=${root.path}/.dart_tool/package_config.json',
        '--timeline_streams=Dart',
        '--observe=0/127.0.0.1',
        '--no-pause-isolates-on-exit',
        '${root.path}/packages/connectanum_bench/test/support/dart_vm_metrics_target.dart',
      ]);
      final uri = Completer<Uri>();
      final ready = Completer<void>();
      final allocated = Completer<void>();
      final output = StringBuffer();
      final stdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            output.writeln(line);
            if (line.contains('The Dart VM service is listening on ')) {
              uri.complete(
                Uri.parse(
                  line.split('The Dart VM service is listening on ').last,
                ),
              );
            }
            if (line == 'READY') ready.complete();
            if (line == 'ALLOCATED') allocated.complete();
          });
      final stderrSub = process.stderr
          .transform(utf8.decoder)
          .listen(output.write);
      var exited = false;
      final exit = process.exitCode.then((code) {
        exited = true;
        return code;
      });
      addTearDown(() async {
        if (!exited) process.kill(ProcessSignal.sigkill);
        await exit;
        await stdoutSub.cancel();
        await stderrSub.cancel();
      });
      await ready.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw StateError('$output'),
      );
      final serviceUri = await uri.future;
      await expectLater(
        DartVmMetricsCollector.connect(
          serviceUri: serviceUri,
          pid: process.pid + 1,
        ),
        throwsStateError,
      );
      final collector = await DartVmMetricsCollector.connect(
        serviceUri: serviceUri,
        pid: process.pid,
        allIsolates: true,
      );
      addTearDown(collector.close);
      final control = await vmServiceConnectUri(
        serviceUri.replace(scheme: 'ws').resolve('ws').toString(),
      );
      addTearDown(control.dispose);
      expect(
        (await control.getVMTimelineFlags()).recordedStreams,
        containsAll(['Dart', 'GC']),
      );
      final window = await collector.beginWindow();
      process.stdin.writeln('allocate');
      await process.stdin.flush();
      await allocated.future.timeout(const Duration(seconds: 10));
      for (final id in window.profiledIsolateIds!) {
        await control.getAllocationProfile(id, gc: true);
      }
      final metrics = await collector.endWindow(window, rssSnapshot: rss);
      expect(metrics.allocatedBytes, greaterThanOrEqualTo(80 * 1024 * 1024));
      expect(metrics.allocatedBytes, lessThan(160 * 1024 * 1024));
      expect(metrics.gcCount, greaterThan(0));
      expect(metrics.gcPauseMicros, greaterThan(0));
      expect(metrics.allocationMeasurement!['observer_pid'], pid);
      expect(metrics.allocationMeasurement!['observed_pid'], process.pid);
      if (Platform.isLinux) {
        expect(metrics.cpuUserMicros, isNotNull);
        expect(metrics.cpuSystemMicros, isNotNull);
      }
      final missing = await collector.endWindow(
        DartVmMetricsWindow(
          cpuUserTicks: null,
          cpuSystemTicks: null,
          isolateIds: window.isolateIds,
        ),
        rssSnapshot: rss,
      );
      expect(missing.allocatedBytes, isNull);
      expect(missing.gcCount, isNull);
      final rewound = await collector.endWindow(
        DartVmMetricsWindow(
          cpuUserTicks: 1 << 62,
          cpuSystemTicks: 1 << 62,
          isolateIds: window.isolateIds,
          profiledIsolateIds: window.profiledIsolateIds,
          gcSnapshots: window.gcSnapshots,
          allocationSnapshot: window.allocationSnapshot,
        ),
        rssSnapshot: rss,
      );
      expect(rewound.cpuUserMicros, isNull);
      expect(rewound.cpuSystemMicros, isNull);
      await collector.close();
      await control.dispose();
      process.stdin.writeln('stop');
      await process.stdin.close();
      expect(
        await exit.timeout(const Duration(seconds: 5)),
        0,
        reason: '$output',
      );
    },
  );

  test('failed timeline clearing aborts the allocation window', () async {
    final vm = await _VmFixture.start(unavailable: 'clearVMTimeline');
    addTearDown(vm.close);
    final collector = await DartVmMetricsCollector.connect(
      serviceUri: vm.uri,
      pid: vm.targetPid,
    );
    addTearDown(collector.close);
    await expectLater(collector.beginWindow(), throwsA(isA<Exception>()));
  });

  for (final unavailable in [
    'flags_disabled',
    'getVMTimelineFlags',
    'setVMTimelineFlags',
    'getVMTimelineMicros',
    'getVMTimeline',
    'heaps',
    'used',
    'full_group',
  ]) {
    test('unsupported VM evidence stays unavailable: $unavailable', () async {
      final vm = await _VmFixture.start(unavailable: unavailable);
      addTearDown(vm.close);
      final collector = await DartVmMetricsCollector.connect(
        serviceUri: vm.uri,
        pid: vm.targetPid,
      );
      addTearDown(collector.close);
      final result = await collector.endWindow(
        await collector.beginWindow(),
        rssSnapshot: rss,
      );
      expect(result.allocatedBytes, isNull);
      expect(result.allocationMeasurement!['status'], 'not_measured');
    });
  }
  for (final missing in ['applications', 'group']) {
    test('missing application $missing is rejected', () async {
      final vm = await _VmFixture.start();
      addTearDown(vm.close);
      vm.noApplications = missing == 'applications';
      vm.noReferenceGroup = missing == 'group';
      if (vm.noApplications) {
        await expectLater(
          DartVmMetricsCollector.connect(serviceUri: vm.uri, pid: vm.targetPid),
          throwsStateError,
        );
      } else {
        final collector = await DartVmMetricsCollector.connect(
          serviceUri: vm.uri,
          pid: vm.targetPid,
        );
        addTearDown(collector.close);
        await expectLater(collector.beginWindow(), throwsStateError);
      }
    });
  }
  test('isolate disappearance and replacement invalidate collection', () async {
    final vm = await _VmFixture.start();
    addTearDown(vm.close);
    final collector = await DartVmMetricsCollector.connect(
      serviceUri: vm.uri,
      pid: vm.targetPid,
    );
    addTearDown(collector.close);
    final window = await collector.beginWindow();
    vm.isolateId = 'isolates/replaced';
    await expectLater(
      collector.endWindow(window, rssSnapshot: rss),
      throwsStateError,
    );
    vm.noApplications = true;
    await expectLater(collector.beginWindow(), throwsStateError);
  });
  test(
    'GC chatter cannot become a fabricated zero collection window',
    () async {
      final vm = await _VmFixture.start();
      addTearDown(vm.close);
      final collector = await DartVmMetricsCollector.connect(
        serviceUri: vm.uri,
        pid: vm.targetPid,
      );
      addTearDown(collector.close);
      final window = await collector.beginWindow();
      vm.chatter();
      final result = await collector.endWindow(window, rssSnapshot: rss);
      expect(result.gcCount, isNull);
      expect(result.allocatedBytes, isNull);
    },
  );
  test('failed stream registration is propagated and disposed', () async {
    final vm = await _VmFixture.start(unavailable: 'streamListen');
    addTearDown(vm.close);
    await expectLater(
      DartVmMetricsCollector.connect(serviceUri: vm.uri, pid: vm.targetPid),
      throwsA(isA<Exception>()),
    );
  });
}

// Protocol fixture for missing/unsupported SDK responses, not numeric evidence.
class _VmFixture {
  _VmFixture(this.server, this.unavailable);
  final HttpServer server;
  final String? unavailable;
  final targetPid = 2147483646;
  WebSocket? socket;
  Timer? timer;
  var noApplications = false, noReferenceGroup = false;
  var isolateId = 'isolates/1';
  var clock = 1000;
  List<String> recorded = ['Dart'];
  Uri get uri => Uri.parse('http://127.0.0.1:${server.port}/');
  static Future<_VmFixture> start({String? unavailable}) async {
    final fixture = _VmFixture(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      unavailable,
    );
    fixture.server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      fixture.socket = socket;
      socket.listen((raw) {
        final request = jsonDecode(raw as String) as Map;
        final method = request['method'];
        if (method == unavailable) {
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': request['id'],
              'error': {'code': -32601, 'message': 'unsupported'},
            }),
          );
          return;
        }
        final result = fixture.response(
          method as String,
          request['params'] as Map? ?? {},
        );
        socket.add(
          jsonEncode({'jsonrpc': '2.0', 'id': request['id'], 'result': result}),
        );
      });
    });
    return fixture;
  }

  Map<String, Object?> reference() => {
    'type': '@Isolate',
    'id': isolateId,
    'name': 'main',
    'number': '1',
    'isSystemIsolate': false,
    if (!noReferenceGroup) 'isolateGroupId': 'isolateGroups/1',
  };
  Object response(String method, Map params) {
    switch (method) {
      case 'getVM':
        return {
          'type': 'VM',
          'pid': targetPid,
          'version': 'test-sdk',
          'isolates': [if (!noApplications) reference()],
        };
      case 'streamListen':
      case 'streamCancel':
      case 'clearVMTimeline':
        return {'type': 'Success'};
      case 'getVMTimelineFlags':
        return {
          'type': 'TimelineFlags',
          'recorderName': 'Endless',
          'recordedStreams': recorded,
          'availableStreams': ['Dart', 'GC'],
        };
      case 'setVMTimelineFlags':
        recorded = List<String>.from(params['recordedStreams'] as List);
        if (unavailable == 'flags_disabled') recorded.remove('GC');
        return {'type': 'Success'};
      case 'getVMTimelineMicros':
        return {'type': 'Timestamp', 'timestamp': clock += 100};
      case 'getVMTimeline':
        return {
          'type': 'Timeline',
          'traceEvents': [],
          'timeOriginMicros': 0,
          'timeExtentMicros': 1000000,
        };
      case 'getIsolate':
        return {
          ...reference(),
          'type': 'Isolate',
          'isolateGroupId': unavailable == 'full_group'
              ? null
              : 'isolateGroups/1',
          if (unavailable != 'heaps')
            '_heaps': {
              for (final space in ['new', 'old'])
                space: {
                  'collections': 0,
                  'time': 0,
                  if (unavailable != 'used') 'used': 1000000,
                },
            },
        };
      default:
        throw StateError('Unexpected VM RPC $method');
    }
  }

  void chatter() {
    timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      socket?.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'streamNotify',
          'params': {
            'streamId': 'GC',
            'event': {'type': 'Event', 'kind': 'GC', 'timestamp': 1},
          },
        }),
      );
    });
  }

  Future<void> close() async {
    timer?.cancel();
    await socket?.close();
    await server.close(force: true);
  }
}
