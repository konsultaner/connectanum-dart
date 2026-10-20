import 'dart:typed_data';

import 'package:connectanum_core/cbor_serializer.dart' as cbor;
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/message/ppt_copy_metrics.dart';
import 'package:test/test.dart';

void main() {
  tearDown(PptCopyMetrics.endWindow);
  late PptCopyMetricsSnapshot coldSetup;
  setUpAll(() {
    PptCopyMetrics.beginWindow();
    try {
      PptCopyMetrics.measure(
        () => cbor.Serializer().serializePPT(
          PPTPayload(arguments: [Uint8List(0)]),
        ),
      );
    } finally {
      coldSetup = PptCopyMetrics.endWindow();
    }
  });
  test('cold metadata setup is observed once and later buffers are reused', () {
    expect(coldSetup.metadataSetupCopyBytes, 15);
    expect(coldSetup.knownOwnCopyBytes, 32);
    PptCopyMetrics.beginWindow();
    PptCopyMetrics.measure(
      () => cbor.Serializer().serializePPT(
        PPTPayload(arguments: [Uint8List(0)]),
      ),
    );
    final warm = PptCopyMetrics.endWindow();
    expect(warm.metadataSetupCopyBytes, 0);
    expect(warm.knownOwnCopyBytes, 17);
  });

  final key = List<int>.filled(32, 7);
  for (final typed in [false, true]) {
    for (final aes in [false, true]) {
      test('${typed ? 'typed' : 'CBOR'} ${aes ? 'AES' : 'XSalsa'} '
          'observes actual PPT copies around both provider operations', () {
        final provider = _provider(typed, aes, key);
        final body = Uint8List.fromList(List.generate(65, (i) => i));
        final options = PublishOptions(pptScheme: 'wamp');
        PptCopyMetrics.beginWindow();
        final packed = provider.packPayload([body], null, options);
        expect(provider.unpackPayload(packed, options).arguments, [body]);
        final metrics = PptCopyMetrics.endWindow();
        // CBOR: a two-byte binary header plus one 82-byte envelope assembly.
        // Its canonical singleton binary decoder retains a view of plaintext.
        expect(metrics.encodeWrappingCopyBytes, typed ? 0 : 2);
        expect(metrics.coalescingCopyBytes, typed ? 0 : 82);
        expect(metrics.decodedBinaryCopyBytes, 0);
        const setupBytes = 0;
        expect(metrics.metadataSetupCopyBytes, setupBytes);
        expect(metrics.knownOwnCopyBytes, (typed ? 0 : 84) + setupBytes);
      });
    }
  }

  test('general CBOR PPT counts encoded wrapping and nested binary clones', () {
    final provider = _provider(false, true, key);
    final options = PublishOptions(pptScheme: 'wamp');
    final first = Uint8List.fromList([1, 2, 3]);
    final second = Uint8List.fromList([4, 5]);
    final third = Uint8List.fromList([6, 7]);
    PptCopyMetrics.beginWindow();
    final packed = provider.packPayload(
      [first, second],
      {'data': third},
      options,
    );
    final decoded = provider.unpackPayload(packed, options);
    expect(decoded.arguments, [first, second]);
    expect(decoded.argumentsKeywords, {'data': third});
    final metrics = PptCopyMetrics.endWindow();
    expect(metrics.encodeWrappingCopyBytes, 8 + 9);
    expect(metrics.coalescingCopyBytes, 30);
    expect(metrics.decodedBinaryCopyBytes, 3 + 2 + 2);
    expect(metrics.knownOwnCopyBytes, 54);
  });

  test('failed serialization retains copied prefix and restores its scope', () {
    final provider = _provider(false, true, key);
    final body = Uint8List.fromList([1, 2, 3]);
    final failure = StateError('kwargs encoding fixture');
    PptCopyMetrics.beginWindow();
    expect(
      () => provider.packPayload(
        [body],
        {'bad': _ThrowingCborValue(failure)},
        PublishOptions(pptScheme: 'wamp'),
      ),
      throwsA(same(failure)),
    );
    // The encoded args [h'010203'] was copied before invalid kwargs failed.
    // No PPT envelope was assembled, and ordinary work stays outside scope.
    cbor.Serializer().serializePPT(PPTPayload(arguments: [body]));
    final partial = PptCopyMetrics.endWindow();
    expect(partial.encodeWrappingCopyBytes, 5);
    expect(partial.coalescingCopyBytes, 0);
    expect(partial.decodedBinaryCopyBytes, 0);
    PptCopyMetrics.beginWindow();
    PptCopyMetrics.measure(() {
      expect(
        () => PptCopyMetrics.measure(() => throw StateError('nested')),
        throwsStateError,
      );
      cbor.Serializer().serializePPT(PPTPayload(arguments: [body]));
    });
    expect(PptCopyMetrics.endWindow().knownOwnCopyBytes, 20);
  });

  test(
    'scopes restore after exceptions and exclude unrelated serialization',
    () {
      final serializer = cbor.Serializer();
      final payload = PPTPayload(arguments: [Uint8List(65)]);
      PptCopyMetrics.beginWindow();
      expect(PptCopyMetrics.beginWindow, throwsStateError);
      expect(
        () => PptCopyMetrics.measure(() => throw StateError('fixture')),
        throwsStateError,
      );
      serializer.serializePPT(payload);
      expect(PptCopyMetrics.endWindow().knownOwnCopyBytes, 0);
      PptCopyMetrics.beginWindow();
      PptCopyMetrics.measure(() => serializer.serializePPT(payload));
      final captured = PptCopyMetrics.endWindow();
      expect(captured.knownOwnCopyBytes, 84);
      serializer.serializePPT(payload);
      expect(PptCopyMetrics.endWindow().toJson(), captured.toJson());
      PptCopyMetrics.beginWindow();
      expect(PptCopyMetrics.endWindow().knownOwnCopyBytes, 0);
    },
  );
}

WampE2eeProvider _provider(bool typed, bool aes, List<int> key) {
  final keys = {'key': key};
  if (typed) {
    return aes
        ? WampFlatBuffersAes256GcmProvider(keys: keys, defaultKeyId: 'key')
        : WampFlatBuffersXsalsa20Poly1305Provider(
            keys: keys,
            defaultKeyId: 'key',
          );
  }
  return aes
      ? WampCborAes256GcmProvider(keys: keys, defaultKeyId: 'key')
      : WampCborXsalsa20Poly1305Provider(keys: keys, defaultKeyId: 'key');
}

class _ThrowingCborValue {
  _ThrowingCborValue(this.failure);
  final Object failure;
  Object toCbor() => throw failure;
}
