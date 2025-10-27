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
  PublicationRouting({
    required this.publicationId,
    required this.matches,
  });

  final int publicationId;
  final List<SubscriptionMatch> matches;
}

/// Topic→subscription index supporting exact/prefix/wildcard matching.
class SubscriptionAtlas {
  final Map<String, SubscriptionEntry> exact = {};
  final Map<String, SubscriptionEntry> prefixes = {};
  final Map<String, SubscriptionEntry> wildcards = {};

  Iterable<SubscriptionEntry> match(String topic) sync* {
    final exactMatch = exact[topic];
    if (exactMatch != null) {
      yield exactMatch;
    }
    for (final entry in prefixes.entries) {
      if (topic.startsWith(entry.key)) {
        yield entry.value;
      }
    }
    for (final entry in wildcards.entries) {
      if (_wildcardMatches(entry.key, topic)) {
        yield entry.value;
      }
    }
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
