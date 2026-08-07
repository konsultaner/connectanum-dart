import 'package:connectanum_router/src/router/router_instance.dart';
import 'package:test/test.dart';

void main() {
  group('router-hosted MCP SSE sequence reservations', () {
    test('failed batches restore only the sequence reservation they own', () {
      final freshStreamSequences = <String, int>{'s1': 2};
      restoreMcpSseSequenceReservationsForTest(
        streamSequences: freshStreamSequences,
        previousSequences: <String, int?>{'s1': null},
        reservedSequences: const <String, int>{'s1': 2},
      );
      expect(freshStreamSequences, isEmpty);

      final existingStreamSequences = <String, int>{'s1': 4};
      restoreMcpSseSequenceReservationsForTest(
        streamSequences: existingStreamSequences,
        previousSequences: const <String, int?>{'s1': 2},
        reservedSequences: const <String, int>{'s1': 4},
      );
      expect(existingStreamSequences, equals(const <String, int>{'s1': 2}));

      final overlappingStreamSequences = <String, int>{'s1': 5};
      restoreMcpSseSequenceReservationsForTest(
        streamSequences: overlappingStreamSequences,
        previousSequences: const <String, int?>{'s1': 2},
        reservedSequences: const <String, int>{'s1': 4},
      );
      expect(overlappingStreamSequences, equals(const <String, int>{'s1': 5}));

      restoreMcpSseSequenceReservationsForTest(
        streamSequences: overlappingStreamSequences,
        previousSequences: const <String, int?>{'s1': 4},
        reservedSequences: const <String, int>{'s1': 5},
      );
      restoreMcpSseSequenceReservationsForTest(
        streamSequences: overlappingStreamSequences,
        previousSequences: const <String, int?>{'s1': 2},
        reservedSequences: const <String, int>{'s1': 4},
      );
      expect(overlappingStreamSequences, equals(const <String, int>{'s1': 2}));
    });
  });
}
