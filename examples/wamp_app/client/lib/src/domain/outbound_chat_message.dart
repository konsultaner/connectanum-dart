import 'dart:convert';

import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'local_chat_message.dart';

enum OutboundMessageState { queued, accepted, retryable, rejected, conflict }

final class OutboundChatMessage {
  OutboundChatMessage({
    required this.envelope,
    required this.localMessage,
    required this.state,
    required this.attemptCount,
    DateTime? lastAttemptAt,
    this.acceptedCursor,
  }) : lastAttemptAt = lastAttemptAt?.toUtc() {
    validate();
  }

  static const maxEntries = 100;
  static const maxAttemptCount = 1000;

  final EncryptedChatMessage envelope;
  final LocalChatMessage localMessage;
  final OutboundMessageState state;
  final int attemptCount;
  final DateTime? lastAttemptAt;
  final int? acceptedCursor;

  bool get canRetry => state == OutboundMessageState.retryable;

  bool get canDiscard => switch (state) {
    OutboundMessageState.retryable ||
    OutboundMessageState.rejected ||
    OutboundMessageState.conflict => true,
    OutboundMessageState.queued || OutboundMessageState.accepted => false,
  };

  bool matchesEnvelope(EncryptedChatMessage other) =>
      jsonEncode(envelope.toJson()) == jsonEncode(other.toJson());

  void validate() {
    envelope.validate();
    localMessage.validate();
    if (!localMessage.outgoing ||
        localMessage.deliveredAt != null ||
        localMessage.readAt != null ||
        localMessage.messageId != envelope.messageId ||
        localMessage.conversationId != envelope.conversationId ||
        localMessage.sentAt != envelope.createdAt ||
        localMessage.oneTime != envelope.oneTime ||
        localMessage.expiresAt != envelope.expiresAt ||
        localMessage.isGroup != envelope.isGroup) {
      throw const FormatException(
        'Outbound message metadata does not match its envelope.',
      );
    }
    if (envelope.isGroup) {
      if (localMessage.peerUsername != envelope.senderUsername ||
          !_sameStrings(
            localMessage.participantUsernames,
            envelope.participantUsernames,
          )) {
        throw const FormatException(
          'Outbound group metadata does not match its envelope.',
        );
      }
    } else if (localMessage.peerUsername != envelope.recipientUsername) {
      throw const FormatException(
        'Outbound recipient does not match its envelope.',
      );
    }
    if (attemptCount < 0 || attemptCount > maxAttemptCount) {
      throw const FormatException('Outbound attempt count is invalid.');
    }
    if ((attemptCount == 0) != (lastAttemptAt == null)) {
      throw const FormatException('Outbound attempt metadata is invalid.');
    }
    if (state == OutboundMessageState.accepted) {
      if (attemptCount == 0 || acceptedCursor == null || acceptedCursor! < 1) {
        throw const FormatException('Accepted outbound state is invalid.');
      }
    } else if (acceptedCursor != null) {
      throw const FormatException(
        'Only accepted messages may retain a cursor.',
      );
    }
    if ((state == OutboundMessageState.retryable ||
            state == OutboundMessageState.rejected) &&
        attemptCount == 0) {
      throw const FormatException(
        'Outbound failure state requires an attempt.',
      );
    }
  }

  OutboundChatMessage withAttempt(DateTime attemptedAt) {
    if (attemptCount >= maxAttemptCount) {
      throw const FormatException('Outbound retry limit was reached.');
    }
    return OutboundChatMessage(
      envelope: envelope,
      localMessage: localMessage,
      state: OutboundMessageState.queued,
      attemptCount: attemptCount + 1,
      lastAttemptAt: attemptedAt,
    );
  }

  OutboundChatMessage withAccepted(MessageSendReceipt receipt) {
    if (attemptCount == 0 || receipt.messageId != envelope.messageId) {
      throw const FormatException('Message send receipt does not match.');
    }
    return OutboundChatMessage(
      envelope: envelope,
      localMessage: localMessage,
      state: OutboundMessageState.accepted,
      attemptCount: attemptCount,
      lastAttemptAt: lastAttemptAt,
      acceptedCursor: receipt.cursor,
    );
  }

  OutboundChatMessage withFailure(OutboundMessageState failureState) {
    if ((attemptCount == 0 && failureState != OutboundMessageState.conflict) ||
        (failureState != OutboundMessageState.retryable &&
            failureState != OutboundMessageState.rejected &&
            failureState != OutboundMessageState.conflict)) {
      throw const FormatException('Outbound failure state is invalid.');
    }
    return OutboundChatMessage(
      envelope: envelope,
      localMessage: localMessage,
      state: failureState,
      attemptCount: attemptCount,
      lastAttemptAt: lastAttemptAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'envelope': envelope.toJson(),
    'local_message': localMessage.toJson(),
    'state': state.name,
    'attempt_count': attemptCount,
    if (lastAttemptAt case final value?)
      'last_attempt_at': value.toIso8601String(),
    'accepted_cursor': ?acceptedCursor,
  };

  factory OutboundChatMessage.fromJson(Map<String, dynamic> value) {
    final rawEnvelope = value['envelope'];
    final rawLocal = value['local_message'];
    final rawState = value['state'];
    final attemptCount = value['attempt_count'];
    final acceptedCursor = value['accepted_cursor'];
    if (rawEnvelope is! Map ||
        rawLocal is! Map ||
        rawState is! String ||
        attemptCount is! int ||
        (acceptedCursor != null && acceptedCursor is! int)) {
      throw const FormatException('Outbound message state is invalid.');
    }
    final state = _readState(rawState);
    return OutboundChatMessage(
      envelope: EncryptedChatMessage.fromJson(
        Map<String, dynamic>.from(rawEnvelope),
      ),
      localMessage: LocalChatMessage.fromJson(
        Map<String, dynamic>.from(rawLocal),
      ),
      state: state,
      attemptCount: attemptCount,
      lastAttemptAt: _readOptionalDate(value['last_attempt_at']),
      acceptedCursor: acceptedCursor as int?,
    );
  }
}

OutboundMessageState _readState(String raw) {
  for (final state in OutboundMessageState.values) {
    if (state.name == raw) return state;
  }
  throw const FormatException('Outbound message state is invalid.');
}

DateTime? _readOptionalDate(Object? raw) {
  if (raw == null) return null;
  if (raw is! String) {
    throw const FormatException('Outbound attempt timestamp is invalid.');
  }
  final value = DateTime.tryParse(raw);
  if (value == null || !raw.endsWith('Z')) {
    throw const FormatException('Outbound attempt timestamp is invalid.');
  }
  return value.toUtc();
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
