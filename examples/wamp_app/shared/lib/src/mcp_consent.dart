abstract final class WampAppMcpConsentLimits {
  static const maxRevision = 0x7fffffff;
}

final class WampAppMcpConsent {
  WampAppMcpConsent({
    required this.profileReadAllowed,
    required this.revision,
    required this.updatedAt,
  }) {
    _validateRevision(revision, 'revision');
  }

  static final denied = WampAppMcpConsent(
    profileReadAllowed: false,
    revision: 0,
    updatedAt: null,
  );

  final bool profileReadAllowed;
  final int revision;
  final DateTime? updatedAt;

  Map<String, dynamic> toWampKeywords() => {
    'profile_read_allowed': profileReadAllowed,
    'revision': revision,
    if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
  };

  factory WampAppMcpConsent.fromWampKeywords(Map<String, dynamic>? value) {
    final profileReadAllowed = value?['profile_read_allowed'];
    final revision = value?['revision'];
    final updatedAtValue = value?['updated_at'];
    if (profileReadAllowed is! bool || revision is! int) {
      throw const FormatException('MCP consent is malformed.');
    }
    final updatedAt = switch (updatedAtValue) {
      null => null,
      final String value => DateTime.tryParse(value)?.toUtc(),
      _ => null,
    };
    if (updatedAtValue != null && updatedAt == null) {
      throw const FormatException('MCP consent updated_at is invalid.');
    }
    if (revision == 0 && updatedAt != null ||
        revision > 0 && updatedAt == null) {
      throw const FormatException('MCP consent revision metadata is invalid.');
    }
    return WampAppMcpConsent(
      profileReadAllowed: profileReadAllowed,
      revision: revision,
      updatedAt: updatedAt,
    );
  }
}

final class WampAppMcpConsentUpdate {
  WampAppMcpConsentUpdate({
    required this.expectedRevision,
    required this.profileReadAllowed,
  }) {
    _validateRevision(expectedRevision, 'expected_revision');
  }

  final int expectedRevision;
  final bool profileReadAllowed;

  Map<String, dynamic> toWampKeywords() => {
    'expected_revision': expectedRevision,
    'profile_read_allowed': profileReadAllowed,
  };

  factory WampAppMcpConsentUpdate.fromWampKeywords(
    Map<String, dynamic>? value,
  ) {
    final expectedRevision = value?['expected_revision'];
    final profileReadAllowed = value?['profile_read_allowed'];
    if (expectedRevision is! int || profileReadAllowed is! bool) {
      throw const FormatException('MCP consent update is malformed.');
    }
    return WampAppMcpConsentUpdate(
      expectedRevision: expectedRevision,
      profileReadAllowed: profileReadAllowed,
    );
  }
}

void _validateRevision(int value, String name) {
  if (value < 0 || value > WampAppMcpConsentLimits.maxRevision) {
    throw FormatException('$name is outside the supported range.');
  }
}
