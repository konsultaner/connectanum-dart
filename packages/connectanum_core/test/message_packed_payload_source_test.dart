import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/owned_copy_metrics.dart';
import 'package:test/test.dart';

final class _Source implements PackedPayloadSource {
  _Source(this.load);
  final Uint8List Function() load;
  var reads = 0;
  @override
  Uint8List get bytes {
    reads++;
    return load();
  }
}

final class _ForgedPayload implements LazyMessagePayload {
  _ForgedPayload(this.source);
  final PackedPayloadSource source;
  var claims = 0;
  @override
  PackedPayloadSource get packedPayloadSource {
    claims++;
    return source;
  }

  @override
  dynamic noSuchMethod(dynamic invocation) => super.noSuchMethod(invocation);
}

void main() {
  const context = WampE2eeRuntimeContext(
    direction: WampE2eeDirection.outbound,
    messageType: WampE2eeMessageType.call,
    realm: 'realm',
    uri: 'app.source',
  );

  LazyMessagePayload packed(_Source source, {PackedPayloadDecoder? decoder}) =>
      LazyMessagePayload.packedSource(
        encoding: LazyPayloadEncoding.flatbuffers,
        source: source,
        packedPayloadDecoder:
            decoder ??
            (bytes) => (arguments: <dynamic>[bytes], argumentsKeywords: null),
      );

  test('source identity, metadata and cloned views do not export bytes', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final source = _Source(() => bytes);
    var decodes = 0;
    final payload = packed(
      source,
      decoder: (bytes) {
        decodes++;
        return (arguments: <dynamic>[bytes], argumentsKeywords: null);
      },
    );
    final provider = WampCborXsalsa20Poly1305Provider.single(
      keyId: 'test',
      key: Uint8List(32),
    );
    final anchor = Object();
    final clones = [
      payload,
      payload.withAnchor(anchor),
      payload.withE2eeProvider(provider).withE2eeRuntimeContext(context),
    ];
    for (final view in clones) {
      expect(view.packedPayloadSource, same(source));
      expect(packedPayloadSourceOf(view), same(source));
      expect(view.storageOwner, same(source));
      expect(view.hasPackedPayloadBytes, isTrue);
    }
    expect(source.reads, 0);
    expect(decodes, 0);
    expect(clones[1].anchor, same(anchor));
    expect(clones[2].e2eeProvider, same(provider));
    expect(clones[2].e2eeRuntimeContext, same(context));
    for (final view in clones) {
      expect(view.packedPayloadBytes, same(bytes));
    }
    expect(source.reads, 1);
    expect(decodes, 0);
    expect(payload.arguments, [bytes]);
    expect(payload.argumentsKeywords, isNull);
    expect(decodes, 1);
  });

  test(
    'source lookup rejects a public interface forgery without invoking getters',
    () {
      final source = _Source(() => throw StateError('must not read bytes'));
      final forged = _ForgedPayload(source);
      expect(() => packedPayloadSourceOf(forged), returnsNormally);
      expect(packedPayloadSourceOf(forged), isNull);
      expect(packedPayloadSourceOf(null), isNull);
      expect(forged.claims, 0);
      expect(source.reads, 0);
    },
  );

  test('legacy metadata views retain their original concrete type', () {
    final provider = WampCborXsalsa20Poly1305Provider.single(
      keyId: 'test',
      key: Uint8List(32),
    );
    final legacy = LazyMessagePayload.packed(
      encoding: LazyPayloadEncoding.flatbuffers,
      packedPayloadBytes: Uint8List.fromList([1]),
      packedPayloadDecoder: (bytes) =>
          (arguments: <dynamic>[bytes], argumentsKeywords: null),
    );
    for (final view in [
      legacy.withAnchor(Object()),
      legacy.withE2eeProvider(provider),
      legacy.withE2eeRuntimeContext(context),
    ]) {
      expect(view.runtimeType, legacy.runtimeType);
      expect(packedPayloadSourceOf(view), isNull);
    }
  });

  test('owned copy materializes bytes once and drops the source and owner', () {
    final bytes = Uint8List.fromList([7, 8]);
    final source = _Source(() => bytes);
    var decodes = 0;
    final payload = packed(
      source,
      decoder: (bytes) {
        decodes++;
        return (arguments: <dynamic>[bytes], argumentsKeywords: null);
      },
    );
    final owned = payload.withAnchor(Object()).toOwned();
    expect(source.reads, 1);
    expect(decodes, 0);
    expect(owned.packedPayloadSource, isNull);
    expect(owned.storageOwner, isNull);
    expect(owned.anchor, isNull);
    expect(owned.packedPayloadBytes, [7, 8]);
    expect(owned.packedPayloadBytes, isNot(same(bytes)));
    bytes[0] = 99;
    expect(owned.arguments, [
      [7, 8],
    ]);
    expect(decodes, 1);
  });

  test(
    'failed source read is retryable and success is shared across views',
    () {
      var fail = true;
      final bytes = Uint8List.fromList([3]);
      final source = _Source(() {
        if (fail) throw StateError('not ready');
        return bytes;
      });
      final payload = packed(source);
      final clone = payload.withAnchor(Object());
      expect(() => payload.packedPayloadBytes, throwsStateError);
      expect(source.reads, 1);
      fail = false;
      expect(clone.packedPayloadBytes, same(bytes));
      expect(payload.packedPayloadBytes, same(bytes));
      expect(source.reads, 2);
    },
  );

  test('recursive source read fails without poisoning a later read', () {
    late LazyMessagePayload payload;
    var recurse = true;
    final source = _Source(
      () => recurse
          ? payload.withAnchor(Object()).packedPayloadBytes!
          : Uint8List.fromList([5]),
    );
    payload = packed(source);
    expect(() => payload.packedPayloadBytes, throwsStateError);
    recurse = false;
    expect(payload.packedPayloadBytes, [5]);
    expect(source.reads, 2);
  });

  test('an empty decoded packed source is still decoded only once', () {
    final source = _Source(() => Uint8List(0));
    var decodes = 0;
    final payload = packed(
      source,
      decoder: (_) {
        decodes++;
        return (arguments: null, argumentsKeywords: null);
      },
    );
    expect(payload.arguments, isNull);
    expect(payload.argumentsKeywords, isNull);
    expect(payload.arguments, isNull);
    expect(source.reads, 1);
    expect(decodes, 1);
  });

  for (final decodeFirst in [false, true]) {
    test('detaching source accounts for one body copy decode=$decodeFirst', () {
      OwnedCopyMetrics.enable();
      final source = _Source(() => Uint8List.fromList([1, 2, 3]));
      final before = OwnedCopyMetrics.snapshot()!;
      final payload = packed(source).withAnchor(Object());
      expect(source.reads, 0);
      if (decodeFirst) {
        expect(payload.arguments, [
          [1, 2, 3],
        ]);
      }
      final owned = payload.toOwned();
      final after = OwnedCopyMetrics.snapshot()!;
      expect(after['clone_copy_bytes']! - before['clone_copy_bytes']!, 3);
      expect(owned.packedPayloadSource, isNull);
      expect(owned.arguments, [
        [1, 2, 3],
      ]);
      expect(source.reads, 1);
    });
  }

  for (final keywordsFirst in [false, true]) {
    test(
      'restoration exposes outer bytes and drops authority keywords=$keywordsFirst',
      () {
        final bytes = Uint8List.fromList([1, 2]);
        final source = _Source(() => bytes);
        final message = Call(1, 'app.source')
          ..restoreLazyPayload(packed(source));
        expect(message.toLazyPayload().packedPayloadSource, same(source));
        expect(source.reads, 0);
        if (keywordsFirst) expect(message.argumentsKeywords, isNull);
        expect(message.arguments, [bytes]);
        expect(source.reads, 1);
        expect(message.toLazyPayload().packedPayloadSource, isNull);
        message.arguments![0] = 'edited';
        expect(message.wireArguments, ['edited']);
        expect(message.toLazyPayload().arguments, ['edited']);
      },
    );
  }

  for (final keywordsFirst in [false, true]) {
    test(
      'wire getter exports once and cannot retain stale source keywords=$keywordsFirst',
      () {
        final source = _Source(() => Uint8List.fromList([9]));
        final message = Call(1, 'app.source')
          ..restoreLazyPayload(packed(source));
        if (keywordsFirst) expect(message.wireArgumentsKeywords, isNull);
        expect(message.wireArguments, [
          [9],
        ]);
        expect(source.reads, 1);
        expect(message.toLazyPayload().packedPayloadSource, isNull);
      },
    );
  }

  test(
    'detached message copy materializes and owns its outer packed bytes',
    () {
      final bytes = Uint8List.fromList([4, 5]);
      final source = _Source(() => bytes);
      final original = Call(1, 'app.source')
        ..restoreLazyPayload(packed(source));
      final target = Call(2, 'app.copy');
      original.copyPayloadTo(target);
      expect(source.reads, 1);
      expect(target.toLazyPayload().packedPayloadSource, isNull);
      bytes[0] = 99;
      expect(target.arguments, [
        [4, 5],
      ]);
      expect(original.toLazyPayload().packedPayloadSource, same(source));
    },
  );

  test('replacing transparent bytes drops the source without reading it', () {
    final source = _Source(() => throw StateError('must not export old body'));
    final message = Call(1, 'app.source')..restoreLazyPayload(packed(source));
    final replacement = Uint8List.fromList([9, 8]);
    message.transparentBinaryPayload = replacement;
    final view = message.toLazyPayload();
    expect(view.packedPayloadSource, isNull);
    expect(view.transparentBinaryPayload, same(replacement));
    expect(source.reads, 0);
  });

  test(
    'classic PPT decode materializes source and preserves edited values',
    () {
      final source = _Source(() => Uint8List.fromList([4, 5]));
      final message = Call(
        1,
        'app.source',
        options: CallOptions(
          pptScheme: 'x_app',
          pptSerializer: 'flatbuffers',
        ),
      )..restoreLazyPayload(packed(source));
      message.ensureDecodedPayloadView(
        pptScheme: 'x_app',
        pptSerializer: 'flatbuffers',
        pptCipher: null,
        pptKeyId: null,
      );
      expect(message.arguments, [
        [4, 5],
      ]);
      expect(message.hasDecodedPptPayload, isTrue);
      expect(source.reads, 1);
      expect(message.toLazyPayload().packedPayloadSource, isNull);
    },
  );
}
