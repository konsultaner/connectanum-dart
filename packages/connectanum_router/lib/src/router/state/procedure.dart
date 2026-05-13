import 'dart:collection';
import 'dart:math';

/// Invocation policies for shared registrations.
enum InvocationPolicy { single, roundRobin, random, first, last, load }

/// Matching policies for procedure registrations.
enum ProcedureMatchPolicy { exact, prefix, wildcard }

/// Metadata describing a procedure registration.
class RegistrationRecord {
  RegistrationRecord({
    required this.registrationId,
    required this.procedure,
    required this.sessionId,
    required this.authRole,
    required this.details,
    required this.matchPolicy,
  });

  final int registrationId;
  final String procedure;
  final int sessionId;
  final String? authRole;
  final Map<String, Object?> details;
  final ProcedureMatchPolicy matchPolicy;
  DateTime lastInvocation = DateTime.fromMillisecondsSinceEpoch(0);
}

/// Snapshot sent to workers containing currently registered callees.
class RegistrationSnapshot {
  RegistrationSnapshot({
    required this.registrationId,
    required this.procedure,
    required this.policy,
    required this.matchPolicy,
    required this.callees,
  });

  final int registrationId;
  final String procedure;
  final InvocationPolicy policy;
  final ProcedureMatchPolicy matchPolicy;
  final List<RegistrationRecord> callees;
}

/// Represents a procedure entry (possibly with multiple callees).
class ProcedureEntry {
  factory ProcedureEntry({
    required int registrationId,
    required String procedure,
    required ProcedureMatchPolicy matchPolicy,
    InvocationPolicy policy = InvocationPolicy.single,
    Iterable<RegistrationRecord>? callees,
  }) {
    final orderedCallees = SplayTreeMap<int, RegistrationRecord>.fromIterable(
      callees ?? const <RegistrationRecord>[],
      key: (record) => record.registrationId,
    );
    final wildcardSegments = matchPolicy == ProcedureMatchPolicy.wildcard
        ? procedure.split('.')
        : null;
    final wildcardBlocks = wildcardSegments != null
        ? _computeLiteralBlocks(wildcardSegments)
        : const <int>[];
    final prefixLength = matchPolicy == ProcedureMatchPolicy.prefix
        ? procedure.length
        : 0;
    return ProcedureEntry._(
      registrationId: registrationId,
      procedure: procedure,
      matchPolicy: matchPolicy,
      policy: policy,
      callees: orderedCallees,
      wildcardSegments: wildcardSegments,
      wildcardSegmentCount: wildcardSegments?.length ?? 0,
      wildcardLiteralBlocks: wildcardBlocks,
      prefixLength: prefixLength,
      cacheVersion: orderedCallees.length,
    );
  }

  ProcedureEntry._({
    required this.registrationId,
    required this.procedure,
    required this.matchPolicy,
    required this.policy,
    required this.callees,
    required List<String>? wildcardSegments,
    required this.wildcardSegmentCount,
    required this.wildcardLiteralBlocks,
    required this.prefixLength,
    required int cacheVersion,
  }) : _wildcardSegments = wildcardSegments,
       _cacheVersion = cacheVersion;

  final int registrationId;
  final String procedure;
  final ProcedureMatchPolicy matchPolicy;
  final InvocationPolicy policy;
  final Map<int, RegistrationRecord> callees;
  final List<String>? _wildcardSegments;
  final int wildcardSegmentCount;
  final List<int> wildcardLiteralBlocks;
  final int prefixLength;

  int _cursor = 0;
  int _cacheVersion;
  int _cachedVersion = -1;
  List<RegistrationRecord>? _cachedCallees;
  static final Random _random = Random();

  RegistrationRecord? nextCallee() {
    if (callees.isEmpty) {
      return null;
    }
    switch (policy) {
      case InvocationPolicy.single:
        return callees.values.first;
      case InvocationPolicy.roundRobin:
        final entries = _orderedCallees();
        if (entries.isEmpty) {
          return null;
        }
        final callee = entries[_cursor % entries.length];
        _cursor = (_cursor + 1) % entries.length;
        return callee;
      case InvocationPolicy.random:
        final entries = _orderedCallees();
        if (entries.isEmpty) {
          return null;
        }
        return entries[_random.nextInt(entries.length)];
      case InvocationPolicy.first:
        return _orderedCallees().isNotEmpty ? _orderedCallees().first : null;
      case InvocationPolicy.last:
        return _orderedCallees().isNotEmpty ? _orderedCallees().last : null;
      case InvocationPolicy.load:
        RegistrationRecord? candidate;
        DateTime? bestTimestamp;
        for (final record in callees.values) {
          if (candidate == null ||
              record.lastInvocation.isBefore(bestTimestamp!)) {
            candidate = record;
            bestTimestamp = record.lastInvocation;
          }
        }
        return candidate;
    }
  }

  void addCallee(RegistrationRecord record) {
    callees[record.registrationId] = record;
    _invalidateCache();
  }

  RegistrationRecord? removeCallee(int registrationId) {
    final removed = callees.remove(registrationId);
    if (removed != null) {
      _invalidateCache();
      if (callees.isEmpty) {
        _cursor = 0;
      } else if (_cursor >= callees.length) {
        _cursor %= callees.length;
      }
    }
    return removed;
  }

  bool matchesProcedure(String candidate) {
    switch (matchPolicy) {
      case ProcedureMatchPolicy.exact:
        return procedure == candidate;
      case ProcedureMatchPolicy.prefix:
        if (!candidate.startsWith(procedure)) {
          return false;
        }
        if (candidate.length == procedure.length) {
          return true;
        }
        if (procedure.endsWith('.')) {
          return true;
        }
        return candidate.length > procedure.length &&
            candidate[procedure.length] == '.';
      case ProcedureMatchPolicy.wildcard:
        return _wildcardMatches(candidate);
    }
  }

  bool _wildcardMatches(String candidate) {
    final segments = _wildcardSegments;
    if (segments == null) {
      return false;
    }
    final topicParts = candidate.split('.');
    if (segments.length != topicParts.length) {
      return false;
    }
    for (var i = 0; i < segments.length; i += 1) {
      final patternPart = segments[i];
      if (patternPart.isEmpty) {
        continue;
      }
      if (patternPart != topicParts[i]) {
        return false;
      }
    }
    return true;
  }

  List<RegistrationRecord> _orderedCallees() {
    if (_cachedCallees == null || _cachedVersion != _cacheVersion) {
      _cachedCallees = List<RegistrationRecord>.unmodifiable(callees.values);
      _cachedVersion = _cacheVersion;
    }
    return _cachedCallees!;
  }

  void _invalidateCache() {
    _cacheVersion += 1;
  }

  static List<int> _computeLiteralBlocks(List<String> segments) {
    final blocks = <int>[];
    var current = 0;
    for (final segment in segments) {
      if (segment.isEmpty) {
        if (current > 0) {
          blocks.add(current);
          current = 0;
        }
      } else {
        current += 1;
      }
    }
    if (current > 0) {
      blocks.add(current);
    }
    return List<int>.unmodifiable(blocks);
  }
}

/// Maintains indexed procedure registrations for invocation matching.
class ProcedureAtlas {
  final Map<String, ProcedureEntry> _exact = {};
  final Map<String, ProcedureEntry> _prefixes = {};
  final Map<String, ProcedureEntry> _wildcards = {};
  final Map<int, ProcedureEntry> _registrations = {};

  Iterable<ProcedureEntry> get values =>
      _exact.values.followedBy(_prefixes.values).followedBy(_wildcards.values);

  ProcedureEntry findOrCreate({
    required String procedure,
    required ProcedureMatchPolicy matchPolicy,
    required int registrationId,
    required InvocationPolicy invocationPolicy,
  }) {
    ProcedureEntry? entry;
    switch (matchPolicy) {
      case ProcedureMatchPolicy.exact:
        entry = _exact[procedure];
        break;
      case ProcedureMatchPolicy.prefix:
        entry = _prefixes[procedure];
        break;
      case ProcedureMatchPolicy.wildcard:
        entry = _wildcards[procedure];
        break;
    }
    if (entry != null) {
      return entry;
    }
    final created = ProcedureEntry(
      registrationId: registrationId,
      procedure: procedure,
      matchPolicy: matchPolicy,
      policy: invocationPolicy,
    );
    switch (matchPolicy) {
      case ProcedureMatchPolicy.exact:
        _exact[procedure] = created;
        break;
      case ProcedureMatchPolicy.prefix:
        _prefixes[procedure] = created;
        break;
      case ProcedureMatchPolicy.wildcard:
        _wildcards[procedure] = created;
        break;
    }
    return created;
  }

  void indexRegistration(int registrationId, ProcedureEntry entry) {
    _registrations[registrationId] = entry;
  }

  ProcedureEntry? findByRegistrationId(int registrationId) =>
      _registrations[registrationId];

  void removeRegistration(int registrationId) {
    final entry = _registrations.remove(registrationId);
    if (entry == null) {
      return;
    }
    if (entry.callees.isNotEmpty) {
      return;
    }
    switch (entry.matchPolicy) {
      case ProcedureMatchPolicy.exact:
        _exact.remove(entry.procedure);
        break;
      case ProcedureMatchPolicy.prefix:
        _prefixes.remove(entry.procedure);
        break;
      case ProcedureMatchPolicy.wildcard:
        _wildcards.remove(entry.procedure);
        break;
    }
  }

  ProcedureEntry? match(String procedure) {
    final exactMatch = _exact[procedure];
    if (exactMatch != null) {
      return exactMatch;
    }

    ProcedureEntry? bestPrefix;
    for (final entry in _prefixes.values) {
      if (!entry.matchesProcedure(procedure)) {
        continue;
      }
      if (bestPrefix == null ||
          entry.prefixLength > bestPrefix.prefixLength ||
          (entry.prefixLength == bestPrefix.prefixLength &&
              entry.registrationId < bestPrefix.registrationId)) {
        bestPrefix = entry;
      }
    }
    if (bestPrefix != null) {
      return bestPrefix;
    }

    ProcedureEntry? bestWildcard;
    for (final entry in _wildcards.values) {
      if (!entry.matchesProcedure(procedure)) {
        continue;
      }
      if (bestWildcard == null) {
        bestWildcard = entry;
        continue;
      }
      if (_compareWildcard(entry, bestWildcard) < 0) {
        bestWildcard = entry;
      }
    }
    return bestWildcard;
  }

  static int _compareWildcard(ProcedureEntry a, ProcedureEntry b) {
    final lengthsA = a.wildcardLiteralBlocks;
    final lengthsB = b.wildcardLiteralBlocks;
    final maxBlocks = max(lengthsA.length, lengthsB.length);
    for (var i = 0; i < maxBlocks; i += 1) {
      final blockA = i < lengthsA.length ? lengthsA[i] : 0;
      final blockB = i < lengthsB.length ? lengthsB[i] : 0;
      if (blockA > blockB) {
        return -1;
      }
      if (blockA < blockB) {
        return 1;
      }
    }
    if (a.wildcardSegmentCount > b.wildcardSegmentCount) {
      return -1;
    }
    if (a.wildcardSegmentCount < b.wildcardSegmentCount) {
      return 1;
    }
    return a.registrationId.compareTo(b.registrationId);
  }
}
