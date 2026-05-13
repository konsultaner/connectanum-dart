import 'session.dart';
import 'subscription.dart';
import 'procedure.dart';

/// Immutable snapshot of the router state for a realm.
class RealmSnapshot {
  RealmSnapshot({
    required this.realmUri,
    required this.version,
    required this.sessions,
    required this.subscriptions,
    required this.registrations,
  });

  final String realmUri;
  final int version;
  final List<SessionInfo> sessions;
  final List<SubscriptionSnapshot> subscriptions;
  final List<RegistrationSnapshot> registrations;
}

/// Response wrapper returned by the state store when serving snapshot queries.
class RealmSnapshotResponse {
  RealmSnapshotResponse({required this.snapshot, required this.isNew});

  final RealmSnapshot snapshot;
  final bool isNew;
}
