import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

final class MailboxAppendResult {
  const MailboxAppendResult({required this.message, required this.duplicate});

  final MailboxMessage message;
  final bool duplicate;
}

final class MailboxReceiptUpdate {
  const MailboxReceiptUpdate({
    required this.receipt,
    required this.senderUsername,
    required this.recipientUsername,
  });

  final MessageReceipt receipt;
  final String senderUsername;
  final String recipientUsername;
}

final class MessageConflict implements Exception {
  const MessageConflict(this.messageId);

  final String messageId;
}

final class MessageNotFound implements Exception {
  const MessageNotFound(this.messageId);

  final String messageId;
}

final class MailboxLimitExceeded implements Exception {
  const MailboxLimitExceeded();
}

class MailboxStore {
  MailboxStore(String path, {this.maxMessages = 100000}) : file = File(path);

  final File file;
  final int maxMessages;
  static final Map<String, Future<void>> _pathWriteTails = {};

  Future<void> initialize() async {
    await file.parent.create(recursive: true);
    if (!await file.exists()) {
      await _serializeWrite(() async {
        if (!await file.exists()) {
          await _writeDocument(const _MailboxDocument(nextCursor: 1));
        }
      });
    }
  }

  Future<MailboxAppendResult> append(
    EncryptedChatMessage message, {
    DateTime? now,
  }) {
    message.validate();
    return _serializeWrite(() async {
      final document = await _readDocument();
      final existing = document.messages
          .where((entry) => entry.message.messageId == message.messageId)
          .firstOrNull;
      if (existing != null) {
        if (jsonEncode(existing.message.toJson()) !=
            jsonEncode(message.toJson())) {
          throw MessageConflict(message.messageId);
        }
        return MailboxAppendResult(message: existing, duplicate: true);
      }
      if (document.messages.length >= maxMessages) {
        throw const MailboxLimitExceeded();
      }
      final acceptedAt = (now ?? DateTime.now()).toUtc();
      final stored = MailboxMessage(
        cursor: document.nextCursor,
        message: message,
        acceptedAt: acceptedAt,
      );
      await _writeDocument(
        _MailboxDocument(
          nextCursor: document.nextCursor + 1,
          messages: [...document.messages, stored],
        ),
      );
      return MailboxAppendResult(message: stored, duplicate: false);
    });
  }

  Future<MailboxBatch> sync(
    String username, {
    required int afterCursor,
    int limit = 100,
    DateTime? now,
  }) async {
    if (afterCursor < 0) {
      throw const FormatException('after_cursor must not be negative.');
    }
    if (limit < 1 || limit > 500) {
      throw const FormatException('limit must be between 1 and 500.');
    }
    final document = await _readDocument();
    final currentCursor = document.nextCursor - 1;
    if (afterCursor > currentCursor) {
      throw const FormatException('after_cursor is ahead of the mailbox.');
    }
    final timestamp = (now ?? DateTime.now()).toUtc();
    final messages = <MailboxMessage>[];
    for (final entry in document.messages) {
      if (entry.cursor <= afterCursor ||
          entry.message.isExpiredAt(timestamp) ||
          (entry.message.senderUsername != username &&
              entry.message.recipientUsername != username)) {
        continue;
      }
      messages.add(entry);
      if (messages.length == limit) break;
    }
    final nextCursor = messages.length == limit
        ? messages.last.cursor
        : currentCursor;
    return MailboxBatch(nextCursor: nextCursor, messages: messages);
  }

  Future<MailboxReceiptUpdate> markReceipt(
    String username,
    String messageId, {
    required bool read,
    DateTime? now,
  }) {
    return _serializeWrite(() async {
      final document = await _readDocument();
      final existing = document.messages.reversed
          .where((entry) => entry.message.messageId == messageId)
          .firstOrNull;
      if (existing == null) throw MessageNotFound(messageId);
      if (existing.message.recipientUsername != username) {
        throw StateError('Only the recipient may acknowledge a message.');
      }
      final needsUpdate =
          existing.deliveredAt == null || (read && existing.readAt == null);
      if (!needsUpdate) {
        return MailboxReceiptUpdate(
          receipt: MessageReceipt(
            messageId: messageId,
            cursor: existing.cursor,
            deliveredAt: existing.deliveredAt,
            readAt: existing.readAt,
          ),
          senderUsername: existing.message.senderUsername,
          recipientUsername: existing.message.recipientUsername,
        );
      }
      final timestamp = (now ?? DateTime.now()).toUtc();
      final updated = MailboxMessage(
        cursor: document.nextCursor,
        message: existing.message,
        acceptedAt: existing.acceptedAt,
        deliveredAt: existing.deliveredAt ?? timestamp,
        readAt: read ? (existing.readAt ?? timestamp) : existing.readAt,
      );
      await _writeDocument(
        _MailboxDocument(
          nextCursor: document.nextCursor + 1,
          messages: [...document.messages, updated],
        ),
      );
      return MailboxReceiptUpdate(
        receipt: MessageReceipt(
          messageId: messageId,
          cursor: updated.cursor,
          deliveredAt: updated.deliveredAt,
          readAt: updated.readAt,
        ),
        senderUsername: updated.message.senderUsername,
        recipientUsername: updated.message.recipientUsername,
      );
    });
  }

  Future<_MailboxDocument> _readDocument() async {
    if (!await file.exists()) {
      return const _MailboxDocument(nextCursor: 1);
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic> || decoded['schema'] != 1) {
      throw const FormatException('Unsupported mailbox store schema.');
    }
    final nextCursor = decoded['next_cursor'];
    final rawMessages = decoded['messages'];
    if (nextCursor is! int || nextCursor < 1 || rawMessages is! List) {
      throw const FormatException('Mailbox store document is invalid.');
    }
    final messages = rawMessages
        .map((raw) {
          if (raw is! Map) {
            throw const FormatException('Mailbox store entry must be a map.');
          }
          return MailboxMessage.fromJson(Map<String, dynamic>.from(raw));
        })
        .toList(growable: false);
    var expectedCursor = 1;
    for (final message in messages) {
      if (message.cursor != expectedCursor++) {
        throw const FormatException(
          'Mailbox store cursors are not contiguous.',
        );
      }
    }
    if (nextCursor != expectedCursor) {
      throw const FormatException('Mailbox next cursor is inconsistent.');
    }
    return _MailboxDocument(nextCursor: nextCursor, messages: messages);
  }

  Future<void> _writeDocument(_MailboxDocument document) async {
    final encoded = jsonEncode({
      'schema': 1,
      'next_cursor': document.nextCursor,
      'messages': document.messages
          .map((message) => message.toJson())
          .toList(growable: false),
    });
    final temporary = File(
      p.join(
        file.parent.path,
        '.${p.basename(file.path)}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    try {
      await temporary.writeAsString(encoded, flush: true);
      if (!Platform.isWindows) {
        final result = await Process.run('chmod', ['600', temporary.path]);
        if (result.exitCode != 0) {
          throw FileSystemException(
            'Could not restrict mailbox store permissions',
            temporary.path,
          );
        }
      }
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<T> _serializeWrite<T>(Future<T> Function() action) async {
    final path = file.absolute.path;
    final previous = _pathWriteTails[path] ?? Future<void>.value();
    final release = Completer<void>();
    _pathWriteTails[path] = release.future;
    await previous;
    RandomAccessFile? lock;
    var hasLock = false;
    try {
      lock = await File('${file.path}.lock').open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      hasLock = true;
      return await action();
    } finally {
      if (lock != null) {
        if (hasLock) await lock.unlock();
        await lock.close();
      }
      release.complete();
      if (identical(_pathWriteTails[path], release.future)) {
        _pathWriteTails.remove(path);
      }
    }
  }
}

final class _MailboxDocument {
  const _MailboxDocument({required this.nextCursor, this.messages = const []});

  final int nextCursor;
  final List<MailboxMessage> messages;
}
