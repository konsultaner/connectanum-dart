import 'abstract_message.dart';
import 'custom_fields.dart';
import 'message_types.dart';

/// The WAMP Challenge massage
class Challenge extends AbstractMessage {
  String authMethod;
  Extra extra;

  /// Creates a WAMP Challenge message that is returned by the router to
  /// challenge the client with a given [authMethod] and some [extra]
  /// authentication data
  Challenge(this.authMethod, this.extra) {
    id = MessageTypes.codeChallenge;
  }
}

/// Challenge values to check the authentication validity
class Extra with CustomFieldContainer {
  static const Set<String> _structuredKeys = {
    'challenge',
    'salt',
    'channel_binding',
    'keylen',
    'iterations',
    'memory',
    'kdf',
    'nonce',
  };

  String? _challenge;
  String? _salt;
  String? _channelBinding;
  int? _keyLen;
  int? _iterations;
  int? _memory;
  String? _kdf;
  String? _nonce;

  Map<String, dynamic> Function()? _lazyLoader;

  String? get challenge {
    if (_challenge == null) {
      _ensureLazyLoaded();
    }
    return _challenge;
  }

  set challenge(String? value) => _challenge = value;

  String? get salt {
    if (_salt == null) {
      _ensureLazyLoaded();
    }
    return _salt;
  }

  set salt(String? value) => _salt = value;

  String? get channelBinding {
    if (_channelBinding == null) {
      _ensureLazyLoaded();
    }
    return _channelBinding;
  }

  set channelBinding(String? value) => _channelBinding = value;

  int? get keyLen {
    if (_keyLen == null) {
      _ensureLazyLoaded();
    }
    return _keyLen;
  }

  set keyLen(int? value) => _keyLen = value;

  int? get iterations {
    if (_iterations == null) {
      _ensureLazyLoaded();
    }
    return _iterations;
  }

  set iterations(int? value) => _iterations = value;

  int? get memory {
    if (_memory == null) {
      _ensureLazyLoaded();
    }
    return _memory;
  }

  set memory(int? value) => _memory = value;

  String? get kdf {
    if (_kdf == null) {
      _ensureLazyLoaded();
    }
    return _kdf;
  }

  set kdf(String? value) => _kdf = value;

  String? get nonce {
    if (_nonce == null) {
      _ensureLazyLoaded();
    }
    return _nonce;
  }

  set nonce(String? value) => _nonce = value;

  Extra({
    String? challenge,
    String? salt,
    int? keyLen,
    String? channelBinding,
    int? iterations,
    int? memory,
    String? kdf,
    String? nonce,
    Map<String, dynamic>? custom,
  }) : _challenge = challenge,
       _salt = salt,
       _keyLen = keyLen,
       _channelBinding = channelBinding,
       _iterations = iterations,
       _memory = memory,
       _kdf = kdf,
       _nonce = nonce {
    if (custom != null && custom.isNotEmpty) {
      this.custom.addAll(custom);
    }
  }

  factory Extra.fromMap(Map<String, dynamic> map) {
    return Extra(
      challenge: map['challenge'] as String?,
      salt: map['salt'] as String?,
      keyLen: _asInt(map['keylen']),
      channelBinding: map['channel_binding'] as String?,
      iterations: _asInt(map['iterations']),
      memory: _asInt(map['memory']),
      kdf: map['kdf'] as String?,
      nonce: map['nonce'] as String?,
      custom: _customFieldsFromMap(map),
    );
  }

  Map<String, Object?> toMap() {
    _ensureLazyLoaded();

    final map = <String, Object?>{};
    if (_challenge != null) {
      map['challenge'] = _challenge;
    }
    if (_salt != null) {
      map['salt'] = _salt;
    }
    if (_keyLen != null) {
      map['keylen'] = _keyLen;
    }
    if (_channelBinding != null) {
      map['channel_binding'] = _channelBinding;
    }
    if (_iterations != null) {
      map['iterations'] = _iterations;
    }
    if (_memory != null) {
      map['memory'] = _memory;
    }
    if (_kdf != null) {
      map['kdf'] = _kdf;
    }
    if (_nonce != null) {
      map['nonce'] = _nonce;
    }
    for (final entry in custom.entries) {
      map.putIfAbsent(entry.key, () => entry.value);
    }
    return map;
  }

  void setLazyLoader(Map<String, dynamic> Function() loader) {
    final previousLoader = _lazyLoader;
    if (previousLoader == null) {
      _lazyLoader = loader;
    } else {
      _lazyLoader = () {
        final merged = <String, dynamic>{}
          ..addAll(previousLoader())
          ..addAll(loader());
        return merged;
      };
    }
    attachLazyStringKeyMapLoader(custom, () {
      _ensureLazyLoaded();
      return const <String, dynamic>{};
    });
  }

  void _ensureLazyLoaded() {
    final loader = _lazyLoader;
    if (loader == null) {
      return;
    }
    _lazyLoader = null;
    final map = loader();
    _challenge ??= map['challenge'] as String?;
    _salt ??= map['salt'] as String?;
    _keyLen ??= _asInt(map['keylen']);
    _channelBinding ??= map['channel_binding'] as String?;
    _iterations ??= _asInt(map['iterations']);
    _memory ??= _asInt(map['memory']);
    _kdf ??= map['kdf'] as String?;
    _nonce ??= map['nonce'] as String?;
    for (final entry in _customFieldsFromMap(map).entries) {
      custom.putIfAbsent(entry.key, () => entry.value);
    }
  }
}

int? _asInt(Object? value) => value is int ? value : null;

Map<String, dynamic> _customFieldsFromMap(Map<String, dynamic> map) {
  final custom = Map<String, dynamic>.from(map);
  custom.removeWhere((key, _) => Extra._structuredKeys.contains(key));
  return custom;
}
