@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:connectanum_bench/connectanum_bench.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  final library = _nativeLibrary();
  final skip = library == null || !File(library).existsSync()
      ? 'Native library unavailable; build ct_ffi and run serially.'
      : false;

  test(
    'sequential RPC and pubsub summaries use deltas and measured means',
    () async {
      final fixture = await _Fixture.create();
      final scenarios = <BenchmarkScenario>[
        BenchmarkScenario(
          name: 'prime_publications',
          type: 'wamp_rawsocket_pubsub',
          duration: const Duration(milliseconds: 17),
          extra: {
            'uri': 'bench.events',
            'iterations': 100,
            'payload_bytes': 13,
          },
        ),
        for (final mode in ['rpc', 'pubsub'])
          for (final iterations in [2, 3])
            BenchmarkScenario(
              name: '${mode}_$iterations',
              type: 'wamp_rawsocket_$mode',
              duration: const Duration(milliseconds: 17),
              concurrency: 2,
              extra: {
                'uri': mode == 'rpc' ? 'bench.rpc.echo' : 'bench.events',
                'iterations': iterations,
                'payload_bytes': 13,
                'serializer': 'json',
              },
            ),
      ];
      await fixture.run(library!, BenchmarkConfig(scenarios: scenarios));
      expect(fixture.timers, isNot(contains(const Duration(milliseconds: 17))));
      expect(
        fixture.messages.where((line) => line.startsWith(' Warm-up')),
        isEmpty,
      );
      expect(
        fixture.messages.where((line) => line.startsWith('Dry run')),
        isEmpty,
      );

      // Publication totals include asynchronous WAMP lifecycle meta events.
      // Budget every session join/leave and subscription lifecycle in the run,
      // not a timing-dependent assumption about when that queue has drained.
      final metadataBudget =
          4 +
          scenarios.fold<int>(
            0,
            (sum, scenario) =>
                sum +
                scenario.concurrency * (scenario.type.endsWith('_rpc') ? 2 : 8),
          );

      for (final scenario in scenarios) {
        final lines = fixture.scenarioMessages(scenario.name);
        final iterations = scenario.extra['iterations']! as int;
        final expectedCount = iterations * scenario.concurrency;
        final rpc = scenario.type.endsWith('_rpc');
        expect(
          lines,
          contains(' Total invocations dispatched: ${rpc ? expectedCount : 0}'),
        );
        final publicationLine = lines.singleWhere(
          (line) => line.startsWith(' Total publications routed:'),
        );
        final publications = int.parse(publicationLine.split(': ').last);
        final userPublications = rpc ? 0 : expectedCount;
        expect(
          publications,
          inInclusiveRange(
            userPublications,
            userPublications + metadataBudget,
          ),
        );
        expect(lines, contains(' WAMP samples: $expectedCount'));
        expect(lines, contains(' WAMP request bytes: ${expectedCount * 13}'));
        expect(lines, contains(' WAMP response bytes: ${expectedCount * 13}'));
        expect(lines, contains(' Pending invocations: 0'));
        final prefix = rpc ? 'RPC call done ' : 'PUBSUB publish done ';
        final observations = lines.where((line) => line.startsWith(prefix)).map(
          (line) {
            final match = RegExp(r'latency_ms=([0-9.eE+-]+)').firstMatch(line);
            expect(match, isNotNull, reason: line);
            return double.parse(match!.group(1)!);
          },
        ).toList();
        expect(observations, hasLength(expectedCount));
        final total = observations.reduce((a, b) => a + b);
        expect(total, greaterThan(0));
        final expectedMean = total / expectedCount;
        final meanLines = lines.where(
          (line) => line.startsWith(' WAMP mean latency:'),
        );
        expect(meanLines, hasLength(1));
        final meanMatch = RegExp(
          r'^ WAMP mean latency: ([0-9.]+) ms$',
        ).firstMatch(meanLines.single);
        expect(meanMatch, isNotNull, reason: meanLines.single);
        final actualMean = double.parse(meanMatch!.group(1)!);
        expect(actualMean, closeTo(expectedMean, 0.000501));
      }
      expect(
        fixture.records.where((record) => record.level >= Level.WARNING),
        isEmpty,
      );
    },
    skip: skip,
  );

  for (final wamp in [false, true]) {
    for (final dryRun in [false, true]) {
      test(
        'duration scheduling is explicit for WAMP=$wamp dryRun=$dryRun',
        () async {
          final fixture = await _Fixture.create();
          final scenario = BenchmarkScenario(
            name: 'duration_control',
            type: wamp ? 'wamp_rawsocket_rpc' : 'http',
            duration: const Duration(milliseconds: 17),
            warmup: const Duration(milliseconds: 11),
            extra: wamp ? {'uri': 'bench.rpc.echo', 'iterations': 2} : null,
          );
          await fixture.run(
            library!,
            BenchmarkConfig(scenarios: [scenario]),
            dryRun: dryRun,
          );
          expect(
            fixture.timers.where(
              (value) => value == const Duration(milliseconds: 11),
            ),
            hasLength(1),
          );
          expect(
            fixture.timers.where(
              (value) => value == const Duration(milliseconds: 17),
            ),
            hasLength(!wamp || dryRun ? 1 : 0),
          );
          expect(
            fixture.messages.where((line) => line.startsWith('Dry run')),
            hasLength(dryRun ? 1 : 0),
          );
          expect(
            fixture.messages.where((line) => line.startsWith(' WAMP samples:')),
            hasLength(wamp && !dryRun ? 1 : 0),
          );
          expect(
            fixture.messages,
            contains('Scenario "duration_control" complete.'),
          );
        },
        skip: skip,
      );
    }
  }

  test(
    'secure dry run rejects a cleartext-only listener without fallback',
    () async {
      final fixture = await _Fixture.create();
      await expectLater(
        fixture.run(
          library!,
          BenchmarkConfig(
            scenarios: [
              BenchmarkScenario(
                name: 'secure_no_fallback',
                type: 'wamp_rawsocket_pubsub',
                duration: const Duration(milliseconds: 17),
                extra: {'uri': 'bench.events', 'secure_transport': true},
              ),
            ],
          ),
          dryRun: true,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'No secure bench listener configured for WAMP transport rawsocket',
          ),
        ),
      );
      expect(
        fixture.messages.where((line) => line.startsWith('Scenario ')),
        isEmpty,
      );
      expect(
        fixture.messages.where((line) => line.startsWith(' WAMP ')),
        isEmpty,
      );
    },
    skip: skip,
  );
}

String? _nativeLibrary() {
  final configured = Platform.environment['CONNECTANUM_NATIVE_LIB'];
  if (configured != null && File(configured).existsSync()) return configured;
  final name = switch (Platform.operatingSystem) {
    'macos' => 'libct_ffi.dylib',
    'linux' => 'libct_ffi.so',
    'windows' => 'ct_ffi.dll',
    _ => null,
  };
  if (name == null) return null;
  for (final root in [
    '../../native/transport/target',
    'native/transport/target',
  ]) {
    for (final profile in ['ffi-test/release', 'release']) {
      final library = File('$root/$profile/$name');
      if (library.existsSync()) return library.absolute.path;
    }
  }
  return null;
}

class _Fixture {
  _Fixture(this.configFile);
  final File configFile;
  final records = <LogRecord>[];
  final timers = <Duration>[];
  final logger = Logger('BenchmarkRunner');

  Iterable<String> get messages => records.map((record) => record.message);

  static Future<_Fixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'connectanum-runner-accounting-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final portReservation = await ServerSocket.bind('127.0.0.1', 0);
    final port = portReservation.port;
    await portReservation.close();
    final config = File('${directory.path}/router.yaml');
    await config.writeAsString('''
router:
  realms:
    - name: bench.control
      auth:
        authmethods: [anonymous]
      roles:
        - name: anonymous
          permissions:
            - uri: bench.
              match: prefix
              allow: [register, unregister, subscribe, unsubscribe, publish, call]
        - name: bench
          permissions:
            - uri: bench.
              match: prefix
              allow: [register, unregister, subscribe, unsubscribe, publish, call]
  listeners:
    - endpoint: 127.0.0.1:$port
      authmethods: [anonymous]
      protocols: [rawsocket]
      tls:
        mode: disabled
  worker_pool:
    min_workers: 1
  authenticators:
    anonymous:
      type: anonymous
''');
    final fixture = _Fixture(config);
    final previousRootLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    final subscription = fixture.logger.onRecord
        .where((record) => record.loggerName == 'BenchmarkRunner')
        .listen(fixture.records.add);
    addTearDown(() async {
      await subscription.cancel();
      Logger.root.level = previousRootLevel;
    });
    return fixture;
  }

  Future<void> run(
    String library,
    BenchmarkConfig config, {
    bool dryRun = false,
  }) => runZoned(
    () => BenchmarkRunner(
      nativeLibraryPath: library,
      routerConfigPath: configFile.path,
      config: config,
      dryRun: dryRun,
    ).run(),
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        timers.add(duration);
        return parent.createTimer(zone, duration, callback);
      },
    ),
  );

  List<String> scenarioMessages(String name) {
    final result = <String>[];
    var active = false;
    for (final line in messages) {
      if (line.startsWith('Running scenario ')) {
        if (active) break;
        active = line == 'Running scenario "$name"';
      }
      if (active) result.add(line);
    }
    expect(result, isNotEmpty, reason: name);
    return result;
  }
}
