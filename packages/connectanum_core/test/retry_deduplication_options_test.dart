import 'dart:convert';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/json/serializer.dart';
import 'package:test/test.dart';

void main() {
  group('retry deduplication options', () {
    test('encode Java-compatible throttle and caller hash fields', () {
      final registration = RegisterOptions(
        autoDeduplication: RetryDeduplication.throttle(
          capacity: 4,
          expiry: const Duration(minutes: 2),
        ),
      );
      final call = CallOptions(transactionHash: 'checkout:42');

      expect(registration.custom, {
        'auto_deduplication': 0,
        'auto_deduplication_capacity': 4,
        'auto_deduplication_expiry': 120000,
      });
      expect(registration.autoDeduplication?.isThrottle, isTrue);
      expect(registration.autoDeduplication?.capacity, 4);
      expect(
        registration.autoDeduplication?.expiry,
        const Duration(minutes: 2),
      );
      expect(call.custom, {'transaction_hash': 'checkout:42'});
      expect(call.transactionHash, 'checkout:42');
      expect(registration.verify(), isTrue);
      expect(call.verify(), isTrue);
    });

    test('encode and decode trailing-edge debounce settings', () {
      final options = RegisterOptions(
        autoDeduplication: RetryDeduplication.debounce(
          const Duration(milliseconds: 75),
          capacity: 8,
          expiry: const Duration(seconds: 3),
        ),
      );

      final decoded = RegisterOptions(custom: Map.of(options.custom));
      expect(decoded.autoDeduplication?.isDebounce, isTrue);
      expect(
        decoded.autoDeduplication?.debounce,
        const Duration(milliseconds: 75),
      );
      expect(decoded.autoDeduplication?.capacity, 8);
      expect(decoded.autoDeduplication?.expiry, const Duration(seconds: 3));
    });

    test('serialize proprietary fields without changing standard framing', () {
      final serializer = Serializer();
      final encodedCall =
          jsonDecode(
                serializer.serializeToString(
                  Call(
                    41,
                    'com.example.checkout',
                    options: CallOptions(transactionHash: 'checkout:42'),
                  ),
                ),
              )
              as List<dynamic>;
      final encodedRegister =
          jsonDecode(
                serializer.serializeToString(
                  Register(
                    42,
                    'com.example.checkout',
                    options: RegisterOptions(
                      autoDeduplication: RetryDeduplication.debounce(
                        const Duration(milliseconds: 25),
                      ),
                    ),
                  ),
                ),
              )
              as List<dynamic>;

      expect(encodedCall[2], {'transaction_hash': 'checkout:42'});
      expect((encodedRegister[2] as Map)['auto_deduplication'], 25);
      expect(
        (encodedRegister[2] as Map)['auto_deduplication_capacity'],
        RetryDeduplication.defaultCapacity,
      );
      expect(
        (encodedRegister[2] as Map)['auto_deduplication_expiry'],
        RetryDeduplication.defaultExpiry.inMilliseconds,
      );
    });

    test('reject invalid bounds and transaction hashes', () {
      expect(
        () => RetryDeduplication.debounce(Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => RetryDeduplication.throttle(capacity: 0),
        throwsArgumentError,
      );
      expect(
        () => RetryDeduplication.debounce(
          const Duration(seconds: 2),
          expiry: const Duration(seconds: 1),
        ),
        throwsArgumentError,
      );
      expect(() => CallOptions(transactionHash: ''), throwsArgumentError);
      expect(
        () => CallOptions(
          transactionHash: List.filled(
            CallOptions.maxTransactionHashBytes + 1,
            'a',
          ).join(),
        ),
        throwsArgumentError,
      );
      expect(
        utf8.encode(CallOptions(transactionHash: 'order:42').transactionHash!),
        isNotEmpty,
      );
    });
  });
}
