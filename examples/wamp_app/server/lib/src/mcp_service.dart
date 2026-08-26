import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'account_store.dart';
import 'mcp_consent_store.dart';

final class McpConsentRequired implements Exception {
  const McpConsentRequired();
}

final class WampAppMcpService {
  const WampAppMcpService({required this.accounts, required this.consents});

  final AccountStore accounts;
  final McpConsentStore consents;

  Future<WampAppMcpConsent> getConsent(String username) async {
    await _requireAccount(username);
    return consents.get(username);
  }

  Future<WampAppMcpConsent> updateConsent(
    String username,
    WampAppMcpConsentUpdate update,
  ) async {
    await _requireAccount(username);
    return consents.update(username, update);
  }

  Future<Map<String, dynamic>> readProfileSummary(String username) async {
    final consent = await getConsent(username);
    if (!consent.profileReadAllowed) throw const McpConsentRequired();
    final profile = await accounts.getProfile(username);
    return {
      'username': profile.username,
      'display_name': profile.displayName,
      'status': profile.status,
      'profile_revision': profile.revision,
      'profile_updated_at': profile.updatedAt.toUtc().toIso8601String(),
      'consent_revision': consent.revision,
    };
  }

  Future<void> _requireAccount(String username) async {
    final normalized = AccountRegistration.normalizeUsername(username);
    if (await accounts.find(normalized) == null) {
      throw ProfileNotFound(normalized);
    }
  }
}
