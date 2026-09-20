import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:test/test.dart';

void main() {
  group('scenario JSON validation', () {
    for (final field in ['mode', 'uri']) {
      for (final value in <Object?>[null, '', '  ', 1, true, [], {}]) {
        test('rejects invalid required $field=$value', () {
          expect(
            () => WampScenario.fromJson({..._json(), field: value}),
            throwsFormatException,
          );
        });
      }
      test('requires $field', () {
        final json = _json()..remove(field);
        expect(() => WampScenario.fromJson(json), throwsFormatException);
      });
    }

    test(
      'preserves supported numeric strings without substituting defaults',
      () {
        final values = {
          'iterations': 23,
          'concurrency': 3,
          'in_flight_per_session': 4,
          'peer_count': 5,
          'payload_bytes': 1024,
          'websocket_fragment_size': 64,
          'file_chunk_bytes': 4096,
          'event_timeout_ms': 2000,
          'call_timeout_ms': 900,
        };
        final scenario = WampScenario.fromJson({
          ..._json(),
          for (final entry in values.entries) entry.key: '${entry.value}',
        });
        final encoded = scenario.toJson();
        for (final entry in values.entries) {
          expect(encoded[entry.key], entry.value, reason: entry.key);
        }
        expect(scenario.iterations, 23);
        expect(scenario.concurrency, 3);
        expect(scenario.inFlightPerSession, 4);
        expect(scenario.peerCount, 5);
        expect(scenario.payloadBytes, 1024);
        expect(scenario.websocketFragmentSize, 64);
        expect(scenario.fileChunkBytes, 4096);
        expect(scenario.eventTimeoutMs, 2000);
        expect(scenario.callTimeoutMs, 900);
      },
    );

    for (final field in [
      'iterations',
      'concurrency',
      'in_flight_per_session',
      'peer_count',
      'payload_bytes',
      'websocket_fragment_size',
      'file_chunk_bytes',
      'event_timeout_ms',
      'call_timeout_ms',
    ]) {
      for (final value in <Object>[true, 1.5, [], {}]) {
        test('rejects non-integer configuration $field=$value', () {
          expect(
            () => WampScenario.fromJson({..._json(), field: value}),
            throwsFormatException,
          );
        });
      }
    }

    for (final field in [
      'ppt_scheme',
      'ppt_serializer',
      'ppt_cipher',
      'ppt_keyid',
    ]) {
      for (final value in <Object>['', '  ', 1, false, [], {}]) {
        test('rejects malformed optional PPT field $field=$value', () {
          expect(
            () => WampScenario.fromJson({..._json(), field: value}),
            throwsFormatException,
          );
        });
      }
    }

    for (final field in [
      'transport',
      'serializer',
      'peer_serializer',
      'client_impl',
    ]) {
      for (final value in <Object>['unsupported', '', 1, false, [], {}]) {
        test('rejects unsupported $field=$value without a silent fallback', () {
          expect(
            () => WampScenario.fromJson({..._json(), field: value}),
            throwsFormatException,
          );
        });
      }
    }
  });

  group('scenario aliases', () {
    for (final alias in ['cancel_cycle', 'cancelcycle', 'wamp_cancel_cycle']) {
      test('$alias selects cancel cycle case-insensitively', () {
        final scenario = WampScenario.fromJson({
          ..._json(),
          'mode': alias.toUpperCase(),
        });
        expect(scenario.mode, WampMode.cancelCycle);
        expect(scenario.toJson()['mode'], 'cancel_cycle');
      });
    }
    for (final (alias, expected) in [
      ('rawsocket', WampTransport.rawsocket),
      ('raw', WampTransport.rawsocket),
      ('socket', WampTransport.rawsocket),
      ('websocket', WampTransport.websocket),
      ('ws', WampTransport.websocket),
    ]) {
      test('transport alias $alias preserves secure selection', () {
        final scenario = WampScenario.fromJson({
          ..._json(),
          'transport': alias.toUpperCase(),
          'secure_transport': true,
        });
        expect(scenario.transport, expected);
        expect(scenario.secureTransport, isTrue);
      });
    }
  });
}

Map<String, Object?> _json() => {'mode': 'rpc', 'uri': 'bench.echo'};
