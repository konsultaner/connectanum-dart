import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

final class McpConsentConflict implements Exception {
  const McpConsentConflict(this.currentRevision);

  final int currentRevision;
}

final class McpConsentStore {
  McpConsentStore(String path) : file = File(path);

  final File file;
  Future<void> _writeTail = Future<void>.value();

  Future<void> initialize() async {
    await file.parent.create(recursive: true);
    if (!await file.exists()) {
      await _serializeWrite(() async {
        if (!await file.exists()) {
          await _writeDocument(const <String, WampAppMcpConsent>{});
        }
      });
    }
    await _restrictPermissions(file);
  }

  Future<WampAppMcpConsent> get(String username) {
    final normalized = AccountRegistration.normalizeUsername(username);
    return _serializeWrite(() async {
      final consents = await _readDocument();
      return consents[normalized] ?? WampAppMcpConsent.denied;
    });
  }

  Future<WampAppMcpConsent> update(
    String username,
    WampAppMcpConsentUpdate update, {
    DateTime? now,
  }) {
    final normalized = AccountRegistration.normalizeUsername(username);
    return _serializeWrite(() async {
      final consents = await _readDocument();
      final current = consents[normalized] ?? WampAppMcpConsent.denied;
      if (current.revision != update.expectedRevision ||
          current.revision >= WampAppMcpConsentLimits.maxRevision) {
        throw McpConsentConflict(current.revision);
      }
      final observedAt = (now ?? DateTime.now()).toUtc();
      final updatedAt =
          current.updatedAt != null && observedAt.isBefore(current.updatedAt!)
          ? current.updatedAt!
          : observedAt;
      final replacement = WampAppMcpConsent(
        profileReadAllowed: update.profileReadAllowed,
        revision: current.revision + 1,
        updatedAt: updatedAt,
      );
      await _writeDocument({...consents, normalized: replacement});
      return replacement;
    });
  }

  Future<Map<String, WampAppMcpConsent>> _readDocument() async {
    if (!await file.exists()) return <String, WampAppMcpConsent>{};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic> || decoded['schema'] != 1) {
      throw const FormatException('Unsupported MCP consent store schema.');
    }
    final raw = decoded['consents'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('MCP consents must be a map.');
    }
    return raw.map((username, value) {
      final normalized = AccountRegistration.normalizeUsername(username);
      if (username != normalized || value is! Map<String, dynamic>) {
        throw const FormatException('MCP consent entry is malformed.');
      }
      return MapEntry(username, WampAppMcpConsent.fromWampKeywords(value));
    });
  }

  Future<void> _writeDocument(Map<String, WampAppMcpConsent> consents) async {
    final sorted = consents.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final document = jsonEncode({
      'schema': 1,
      'consents': {
        for (final entry in sorted) entry.key: entry.value.toWampKeywords(),
      },
    });
    final temporary = File(
      p.join(
        file.parent.path,
        '.${p.basename(file.path)}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    try {
      await temporary.writeAsString(document, flush: true);
      await _restrictPermissions(temporary);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<T> _serializeWrite<T>(Future<T> Function() action) async {
    final previous = _writeTail;
    final release = Completer<void>();
    _writeTail = release.future;
    await previous;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }
}

Future<void> _restrictPermissions(File target) async {
  if (Platform.isWindows) return;
  final result = await Process.run('chmod', ['600', target.path]);
  if (result.exitCode != 0) {
    throw FileSystemException(
      'Could not restrict MCP consent store permissions',
      target.path,
    );
  }
}
