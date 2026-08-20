import 'abstract_message.dart';
import 'custom_fields.dart';
import 'message_types.dart';

/// Bounded router-side handling for application retry transaction hashes.
class RetryDeduplication {
  static const String wireField = 'auto_deduplication';
  static const String capacityWireField = 'auto_deduplication_capacity';
  static const String expiryWireField = 'auto_deduplication_expiry';

  static const int defaultCapacity = 1024;
  static const int maximumCapacity = 4096;
  static const Duration defaultExpiry = Duration(minutes: 5);
  static const Duration maximumExpiry = Duration(hours: 24);
  static const Duration maximumDebounce = Duration(hours: 1);

  RetryDeduplication._({
    required this.debounce,
    required this.capacity,
    required this.expiry,
  });

  /// Rejects a duplicate hash while the first invocation is active.
  factory RetryDeduplication.throttle({
    int capacity = defaultCapacity,
    Duration expiry = defaultExpiry,
  }) {
    return _validated(debounce: null, capacity: capacity, expiry: expiry);
  }

  /// Dispatches only the latest matching call after [debounce] is quiet.
  factory RetryDeduplication.debounce(
    Duration debounce, {
    int capacity = defaultCapacity,
    Duration expiry = defaultExpiry,
  }) {
    return _validated(
      debounce: debounce,
      capacity: capacity,
      expiry: expiry,
    );
  }

  /// Decodes the Java-compatible value and Connectanum bound fields.
  factory RetryDeduplication.fromWire({
    required Object autoDeduplication,
    Object? capacity,
    Object? expiryMilliseconds,
  }) {
    if (autoDeduplication is! int || autoDeduplication < 0) {
      throw ArgumentError.value(
        autoDeduplication,
        wireField,
        'must be a non-negative integer',
      );
    }
    if (capacity != null && capacity is! int) {
      throw ArgumentError.value(
        capacity,
        capacityWireField,
        'must be an integer',
      );
    }
    if (expiryMilliseconds != null && expiryMilliseconds is! int) {
      throw ArgumentError.value(
        expiryMilliseconds,
        expiryWireField,
        'must be an integer',
      );
    }
    return _validated(
      debounce: autoDeduplication == 0
          ? null
          : Duration(milliseconds: autoDeduplication),
      capacity: capacity as int? ?? defaultCapacity,
      expiry: expiryMilliseconds == null
          ? defaultExpiry
          : Duration(milliseconds: expiryMilliseconds as int),
    );
  }

  final Duration? debounce;
  final int capacity;
  final Duration expiry;

  bool get isThrottle => debounce == null;
  bool get isDebounce => debounce != null;

  Map<String, int> toWireFields() => {
    wireField: debounce?.inMilliseconds ?? 0,
    capacityWireField: capacity,
    expiryWireField: expiry.inMilliseconds,
  };

  static RetryDeduplication _validated({
    required Duration? debounce,
    required int capacity,
    required Duration expiry,
  }) {
    if (capacity < 1 || capacity > maximumCapacity) {
      throw ArgumentError.value(
        capacity,
        'capacity',
        'must be between 1 and $maximumCapacity',
      );
    }
    if (debounce != null &&
        (debounce <= Duration.zero || debounce > maximumDebounce)) {
      throw ArgumentError.value(
        debounce,
        'debounce',
        'must be greater than zero and at most $maximumDebounce',
      );
    }
    if (expiry <= Duration.zero || expiry > maximumExpiry) {
      throw ArgumentError.value(
        expiry,
        'expiry',
        'must be greater than zero and at most $maximumExpiry',
      );
    }
    if (debounce != null && expiry < debounce) {
      throw ArgumentError.value(
        expiry,
        'expiry',
        'must be greater than or equal to debounce',
      );
    }
    return RetryDeduplication._(
      debounce: debounce,
      capacity: capacity,
      expiry: expiry,
    );
  }
}

class Register extends AbstractMessage {
  int requestId;
  RegisterOptions? options;
  String procedure;

  Register(this.requestId, this.procedure, {this.options}) {
    id = MessageTypes.codeRegister;
  }
}

class RegisterOptions with CustomFieldContainer {
  static final String? matchExact = null;
  static final String matchPrefix = 'prefix';
  static final String matchWildcard = 'wildcard';

  static final String invocationPolicySingle = 'single';
  static final String invocationPolicyFirst = 'first';
  static final String invocationPolicyLast = 'last';
  static final String invocationPolicyRoundRobin = 'roundrobin';
  static final String invocationPolicyRandom = 'random';

  // caller_identification == true
  bool? discloseCaller;

  // pattern_based_registration == true
  String? match;

  // shared_registration
  String? invoke;

  // call_timeout == true
  bool? forwardTimeout;

  RegisterOptions({
    this.discloseCaller,
    this.match,
    this.invoke,
    this.forwardTimeout,
    RetryDeduplication? autoDeduplication,
    Map<String, dynamic>? custom,
  }) {
    if (custom != null) {
      this.custom.addAll(custom);
    }
    if (autoDeduplication != null) {
      this.autoDeduplication = autoDeduplication;
    }
  }

  RetryDeduplication? get autoDeduplication {
    final value = custom[RetryDeduplication.wireField];
    final capacity = custom[RetryDeduplication.capacityWireField];
    final expiry = custom[RetryDeduplication.expiryWireField];
    if (value == null) {
      if (capacity != null || expiry != null) {
        throw ArgumentError(
          'deduplication bounds require '
          '${RetryDeduplication.wireField}',
        );
      }
      return null;
    }
    return RetryDeduplication.fromWire(
      autoDeduplication: value,
      capacity: capacity,
      expiryMilliseconds: expiry,
    );
  }

  set autoDeduplication(RetryDeduplication? value) {
    custom.remove(RetryDeduplication.wireField);
    custom.remove(RetryDeduplication.capacityWireField);
    custom.remove(RetryDeduplication.expiryWireField);
    if (value != null) {
      custom.addAll(value.toWireFields());
    }
  }

  bool verify() {
    autoDeduplication;
    return true;
  }
}
