@TestOn('vm')
library;

import 'package:connectanum_client/native_message_handles.dart';
import 'package:test/test.dart';

void main() {
  test('unadvertised libraries remain entirely legacy', () {
    expect(
      NativeMessageHandleAbi.negotiate(
        version: null,
        providesSymbol: (_) => throw StateError('Must not guess a wide ABI'),
      ),
      NativeMessageHandleAbi.legacy,
    );
  });

  test('version 1 requires the entire family, including owner cleanup', () {
    final checked = <String>{};
    expect(
      NativeMessageHandleAbi.negotiate(
        version: 1,
        providesSymbol: (symbol) => checked.add(symbol),
      ),
      NativeMessageHandleAbi.wide,
    );
    expect(checked, contains('ct_message_buffer_free'));
    expect(checked.length, 19);
  });

  for (final missing in NativeMessageHandleAbi.requiredWideSymbols) {
    test('incomplete family rejects missing $missing', () {
      expect(
        () => NativeMessageHandleAbi.negotiate(
          version: 1,
          providesSymbol: (symbol) => symbol != missing,
        ),
        throwsUnsupportedError,
      );
    });
  }

  for (final version in [0, 2, 0xffffffff]) {
    test('unknown advertised version $version fails closed', () {
      expect(
        () => NativeMessageHandleAbi.negotiate(
          version: version,
          providesSymbol: (_) => true,
        ),
        throwsUnsupportedError,
      );
    });
  }

  test('legacy callbacks reject signed overflow instead of truncating', () {
    for (final value in [-0x100000001, -0x80000001, 0x80000000, 0x100000001]) {
      expect(() => checkedLegacyMessageHandle(value), throwsRangeError);
    }
    for (final value in [-0x80000000, -1, 0, 1, 0x7fffffff]) {
      expect(checkedLegacyMessageHandle(value), value);
    }
  });
}
