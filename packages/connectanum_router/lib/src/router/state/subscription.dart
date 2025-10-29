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
       options = options ?? {};

  final int id;
  final String topic;
  final TopicMatchPolicy matchPolicy;
  final Map<int, SubscriberRecord> subscribers;
  final Map<String, Object?> options;

  int get subscriberCount => subscribers.length;
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
      candidates.add(
        _MatchCandidate(
          entry: exactMatch,
          priority: 0,
          specificity: exactMatch.topic.length,
          secondarySpecificity: exactMatch.topic.length,
        ),
      );
    }
    for (final entry in prefixes.entries) {
      if (topic.startsWith(entry.key)) {
        candidates.add(
          _MatchCandidate(
            entry: entry.value,
            priority: 1,
            specificity: entry.key.length,
            secondarySpecificity: -entry.value.id,
          ),
        );
      }
    }
    for (final entry in wildcards.entries) {
      if (_wildcardMatches(entry.key, topic)) {
        final parts = entry.key.split('.');
        final literalSegments = parts.where((segment) => segment != '*').length;
        candidates.add(
          _MatchCandidate(
            entry: entry.value,
            priority: 2,
            specificity: literalSegments,
            secondarySpecificity: parts.length,
          ),
        );
      }
    }
    candidates.sort(_matchComparator);
    return candidates.map((candidate) => candidate.entry);
  }

  static bool _wildcardMatches(String pattern, String topic) {
    if (pattern == '*') {
      return true;
    }
    final parts = pattern.split('.');
    final topicParts = topic.split('.');
    if (parts.length != topicParts.length) {
      return false;
    }
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part != '*' && part != topicParts[i]) {
        return false;
      }
    }
    return true;
  }
}

class _MatchCandidate {
  _MatchCandidate({
    required this.entry,
    required this.priority,
    required this.specificity,
    required this.secondarySpecificity,
  });

  final SubscriptionEntry entry;
  final int priority;
  final int specificity;
  final int secondarySpecificity;
}

int _matchComparator(_MatchCandidate a, _MatchCandidate b) {
  final priorityComparison = a.priority.compareTo(b.priority);
  if (priorityComparison != 0) {
    return priorityComparison;
  }
  final specificityComparison = b.specificity.compareTo(a.specificity);
  if (specificityComparison != 0) {
    return specificityComparison;
  }
  final secondaryComparison = b.secondarySpecificity.compareTo(
    a.secondarySpecificity,
  );
  if (secondaryComparison != 0) {
    return secondaryComparison;
  }
  return a.entry.id.compareTo(b.entry.id);
}
