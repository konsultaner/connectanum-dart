import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class StoredAccount {
  const StoredAccount({
    required this.username,
    required this.displayName,
    required this.storedKey,
    required this.serverKey,
    required this.salt,
    required this.iterations,
    required this.memoryKiB,
    required this.kdf,
    required this.createdAt,
  });

  final String username;
  final String displayName;
  final String storedKey;
  final String serverKey;
  final String salt;
  final int iterations;
  final int memoryKiB;
  final String kdf;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'username': username,
    'display_name': displayName,
    'stored_key': storedKey,
    'server_key': serverKey,
    'salt': salt,
    'iterations': iterations,
    'memory_kib': memoryKiB,
    'kdf': kdf,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory StoredAccount.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '');
    if (json case {
      'username': final String username,
      'display_name': final String displayName,
      'stored_key': final String storedKey,
      'server_key': final String serverKey,
      'salt': final String salt,
      'iterations': final int iterations,
      'memory_kib': final int memoryKiB,
      'kdf': final String kdf,
    } when createdAt != null) {
      return StoredAccount(
        username: username,
        displayName: displayName,
        storedKey: storedKey,
        serverKey: serverKey,
        salt: salt,
        iterations: iterations,
        memoryKiB: memoryKiB,
        kdf: kdf,
        createdAt: createdAt.toUtc(),
      );
    }
    throw const FormatException('Account store contains an invalid account.');
  }
}

class AccountAlreadyExists implements Exception {
  const AccountAlreadyExists(this.username);

  final String username;

  @override
  String toString() => 'Account $username already exists.';
}

class AccountStore {
  AccountStore(String path) : file = File(path);

  final File file;
  Future<void> _writeTail = Future<void>.value();

  Future<void> initialize() async {
    await file.parent.create(recursive: true);
    if (!await file.exists()) {
      await _serializeWrite(() async {
        if (!await file.exists()) {
          await _writeDocument(const <String, StoredAccount>{});
        }
      });
    }
  }

  Future<StoredAccount?> find(String username) async {
    final accounts = await _readDocument();
    return accounts[username];
  }

  Future<void> create(StoredAccount account) {
    return _serializeWrite(() async {
      final accounts = await _readDocument();
      if (accounts.containsKey(account.username)) {
        throw AccountAlreadyExists(account.username);
      }
      await _writeDocument({...accounts, account.username: account});
    });
  }

  Future<Map<String, StoredAccount>> _readDocument() async {
    if (!await file.exists()) return <String, StoredAccount>{};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic> || decoded['schema'] != 1) {
      throw const FormatException('Unsupported account store schema.');
    }
    final rawAccounts = decoded['accounts'];
    if (rawAccounts is! Map<String, dynamic>) {
      throw const FormatException('Account store accounts must be a map.');
    }
    return rawAccounts.map((username, value) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Account store entry must be a map.');
      }
      final account = StoredAccount.fromJson(value);
      if (username != account.username) {
        throw const FormatException(
          'Account store key does not match username.',
        );
      }
      return MapEntry(username, account);
    });
  }

  Future<void> _writeDocument(Map<String, StoredAccount> accounts) async {
    final document = jsonEncode({
      'schema': 1,
      'accounts': accounts.map(
        (username, account) => MapEntry(username, account.toJson()),
      ),
    });
    final temporary = File(
      p.join(
        file.parent.path,
        '.${p.basename(file.path)}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    try {
      await temporary.writeAsString(document, flush: true);
      if (!Platform.isWindows) {
        final result = await Process.run('chmod', ['600', temporary.path]);
        if (result.exitCode != 0) {
          throw FileSystemException(
            'Could not restrict account store permissions',
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
