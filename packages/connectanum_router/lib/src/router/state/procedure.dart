import 'dart:collection';

/// Invocation policies for shared registrations.
enum InvocationPolicy { single, roundRobin, random, first, last, load }

/// Metadata describing a procedure registration.
class RegistrationRecord {
  RegistrationRecord({
    required this.registrationId,
    required this.procedure,
    required this.sessionId,
    required this.authRole,
    required this.details,
  });

  final int registrationId;
  final String procedure;
  final int sessionId;
  final String? authRole;
  final Map<String, Object?> details;
  DateTime lastInvocation = DateTime.fromMillisecondsSinceEpoch(0);
}

/// Snapshot sent to workers containing currently registered callees.
class RegistrationSnapshot {
  RegistrationSnapshot({
    required this.registrationId,
    required this.procedure,
    required this.policy,
    required this.callees,
  });

  final int registrationId;
  final String procedure;
  final InvocationPolicy policy;
  final List<RegistrationRecord> callees;
}

/// Represents a procedure entry (possibly with multiple callees).
class ProcedureEntry {
  ProcedureEntry({
    required this.registrationId,
    required this.procedure,
    this.policy = InvocationPolicy.single,
    Iterable<RegistrationRecord>? callees,
  }) : callees = SplayTreeMap<int, RegistrationRecord>.fromIterable(
         callees ?? const <RegistrationRecord>[],
         key: (record) => record.registrationId,
       );

  final int registrationId;
  final String procedure;
  final InvocationPolicy policy;
  final Map<int, RegistrationRecord> callees;
  int _cursor = 0;

  RegistrationRecord? nextCallee() {
    if (callees.isEmpty) {
      return null;
    }
    final values = callees.values.toList();
    switch (policy) {
      case InvocationPolicy.single:
        return values.first;
      case InvocationPolicy.roundRobin:
        final callee = values[_cursor % values.length];
        _cursor = (_cursor + 1) % values.length;
        return callee;
      case InvocationPolicy.random:
        values.shuffle();
        return values.first;
      case InvocationPolicy.first:
        return values.first;
      case InvocationPolicy.last:
        return values.last;
      case InvocationPolicy.load:
        values.sort((a, b) => a.lastInvocation.compareTo(b.lastInvocation));
        return values.first;
    }
  }
}
