import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

void main() {
  group('Invocation', () {
    test('respondWith throws when no response handler is attached', () {
      final invocation = Invocation(1, 2, InvocationDetails(null, null, false));

      expect(
        () => invocation.respondWith(arguments: const ['payload']),
        throwsStateError,
      );
    });

    test('respondWith forwards yield and error responses directly', () {
      final invocation = Invocation(1, 2, InvocationDetails(null, null, true));
      final responses = <AbstractMessageWithPayload>[];
      invocation.onResponse(responses.add);

      invocation.respondWith(
        arguments: const ['progress'],
        options: YieldOptions(progress: true),
      );
      invocation.respondWith(
        isError: true,
        errorUri: Error.notAuthorized,
        arguments: const ['denied'],
      );

      expect(responses, hasLength(2));
      expect(responses.first, isA<Yield>());
      expect((responses.first as Yield).options?.progress, isTrue);
      expect(responses.last, isA<Error>());
      expect((responses.last as Error).error, Error.notAuthorized);
    });

    test('respondWith closes after a final response', () {
      final invocation = Invocation(1, 2, InvocationDetails(null, null, false));
      final responses = <AbstractMessageWithPayload>[];
      invocation.onResponse(responses.add);

      invocation.respondWith(arguments: const ['done']);

      expect(invocation.responseClosed, isTrue);
      expect(
        () => invocation.respondWith(arguments: const ['again']),
        throwsStateError,
      );
      expect(responses, hasLength(1));
      expect((responses.single as Yield).arguments, equals(const ['done']));
    });
  });
}
