import 'dart:collection';

/// Subscription matching policies supported by WAMP.
enum TopicMatchPolicy { exact, prefix, wildcard }

/// Holds metadata about a subscriber attached to a subscription.
class SubscriberRecord {
  SubscriberRecord({
    required this.sessionId,
    required this.authRole,
    required this.details,
  });

  final int sessionId;
  final String? authRole;
  final Map<String, Object?> details;
}

/// Represents a subscription entry (topic or pattern).
class SubscriptionEntry {
  SubscriptionEntry({
    required this.id,
    required this.topic,
    required this.matchPolicy,
    Map<int, SubscriberRecord>? subscribers,
    Map<String, Object?>? options,
  }) : subscribers = subscribers ?? SplayTreeMap<int, SubscriberRecord>(),
       options = options ?? {},
       _wildcardSegments = matchPolicy == TopicMatchPolicy.wildcard
           ? topic.split('.')
           : null,
       matchPriority = _priorityForPolicy(matchPolicy),
       matchSpecificity = _specificityForPolicy(
         matchPolicy,
         topic,
         matchPolicy == TopicMatchPolicy.wildcard ? topic.split('.') : null,
       ),
       secondarySpecificity = _secondaryForPolicy(
         matchPolicy,
         topic,
         id,
         matchPolicy == TopicMatchPolicy.wildcard ? topic.split('.') : null,
       );

  final int id;
  final String topic;
  final TopicMatchPolicy matchPolicy;
  final Map<int, SubscriberRecord> subscribers;
  final Map<String, Object?> options;
  final List<String>? _wildcardSegments;
  final int matchPriority;
  final int matchSpecificity;
  final int secondarySpecificity;

  int get subscriberCount => subscribers.length;

  bool matchesTopic(String candidate) => switch (matchPolicy) {
    TopicMatchPolicy.exact => topic == candidate,
    TopicMatchPolicy.prefix => candidate.startsWith(topic),
    TopicMatchPolicy.wildcard => _wildcardMatches(candidate),
  };

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

  static int _priorityForPolicy(TopicMatchPolicy policy) => switch (policy) {
    TopicMatchPolicy.exact => 0,
    TopicMatchPolicy.prefix => 1,
    TopicMatchPolicy.wildcard => 2,
  };

  static int _specificityForPolicy(
    TopicMatchPolicy policy,
    String topic,
    List<String>? wildcardSegments,
  ) => switch (policy) {
    TopicMatchPolicy.exact => topic.length,
    TopicMatchPolicy.prefix => topic.length,
    TopicMatchPolicy.wildcard =>
      (wildcardSegments ?? topic.split('.'))
          .where((segment) => segment.isNotEmpty)
          .length,
  };

  static int _secondaryForPolicy(
    TopicMatchPolicy policy,
    String topic,
    int id,
    List<String>? wildcardSegments,
  ) => switch (policy) {
    TopicMatchPolicy.exact => topic.length,
    TopicMatchPolicy.prefix => -id,
    TopicMatchPolicy.wildcard => (wildcardSegments ?? topic.split('.')).length,
  };
}

/// Immutable snapshot of a subscription for worker consumption.
class SubscriptionSnapshot {
  SubscriptionSnapshot({
    required this.id,
    required this.topic,
    required this.matchPolicy,
    required this.subscribers,
    required this.options,
  });

  final int id;
  final String topic;
  final TopicMatchPolicy matchPolicy;
  final List<SubscriberRecord> subscribers;
  final Map<String, Object?> options;
}

/// Matched subscriber returned by routing logic when dispatching EVENTs.
class SubscriptionMatch {
  SubscriptionMatch({
    required this.subscriptionId,
    required this.sessionId,
    required this.connectionId,
    required this.details,
    this.authRole,
  });

  final int subscriptionId;
  final int sessionId;
  final int connectionId;
  final Map<String, Object?> details;
  final String? authRole;
}

class PublicationRouting {
  PublicationRouting({required this.publicationId, required this.matches});

  final int publicationId;
  final List<SubscriptionMatch> matches;
}

/// Topic→subscription index supporting exact/prefix/wildcard matching.
class SubscriptionAtlas {
  final Map<String, SubscriptionEntry> exact = {};
  final Map<String, SubscriptionEntry> prefixes = {};
  final Map<String, SubscriptionEntry> wildcards = {};

  Iterable<SubscriptionEntry> match(String topic) {
    final candidates = <_MatchCandidate>[];
    final exactMatch = exact[topic];
    if (exactMatch != null) {
      candidates.add(_MatchCandidate(entry: exactMatch));
    }
    for (final entry in prefixes.values) {
      if (entry.matchesTopic(topic)) {
        candidates.add(_MatchCandidate(entry: entry));
      }
    }
    for (final entry in wildcards.values) {
      if (entry.matchesTopic(topic)) {
        candidates.add(_MatchCandidate(entry: entry));
      }
    }
    candidates.sort(_matchComparator);
    return candidates.map((candidate) => candidate.entry);
  }
}

class _MatchCandidate {
  _MatchCandidate({required this.entry});

  final SubscriptionEntry entry;
}

int _matchComparator(_MatchCandidate a, _MatchCandidate b) {
  final priorityComparison = a.entry.matchPriority.compareTo(
    b.entry.matchPriority,
  );
  if (priorityComparison != 0) {
    return priorityComparison;
  }
  final specificityComparison = b.entry.matchSpecificity.compareTo(
    a.entry.matchSpecificity,
  );
  if (specificityComparison != 0) {
    return specificityComparison;
  }
  final secondaryComparison = b.entry.secondarySpecificity.compareTo(
    a.entry.secondarySpecificity,
  );
  if (secondaryComparison != 0) {
    return secondaryComparison;
  }
  return a.entry.id.compareTo(b.entry.id);
}
