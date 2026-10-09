import '../../message/abstract_message.dart';
import '../../message/abort.dart';
import '../../message/authenticate.dart';
import '../../message/challenge.dart';
import '../../message/goodbye.dart';
import '../../message/hello.dart';
import '../../message/welcome.dart';
import 'serializer.dart';

/// Capability for the pinned wire layout and complete metadata dictionary.
const flatBuffersMetadataFeature = '_connectanum_flatbuffers_metadata_v1';

enum _Phase {
  initial,
  hello,
  challenged,
  authenticated,
  established,
  closing,
  closed,
}

/// Immutable capability gate for one FlatBuffers WAMP connection.
///
/// Preparing a send does not commit its transition: retain the returned profile
/// only after the transport accepts the frame. Incoming frames must pass this
/// gate before authentication callbacks or application delivery. This is a
/// capability check, separate from peer authentication and authorization.
final class FlatBuffersSessionProfile {
  const FlatBuffersSessionProfile.client()
    : _client = true,
      _phase = _Phase.initial;

  const FlatBuffersSessionProfile.router()
    : _client = false,
      _phase = _Phase.initial;

  const FlatBuffersSessionProfile._(this._client, this._phase);

  final bool _client;
  final _Phase _phase;

  bool get isEstablished => _phase == _Phase.established;

  FlatBuffersSessionProfile _at(_Phase phase) =>
      FlatBuffersSessionProfile._(_client, phase);

  /// Validate and optionally advertise in a bootstrap message. Pre-encoded
  /// frames must set [advertise] to false; their bytes already need the offer
  /// or acknowledgement and cannot be modified by this gate.
  FlatBuffersSessionProfile prepareOutgoing(
    AbstractMessage message, {
    bool advertise = true,
  }) => _prepare(message, outgoing: true, advertise: advertise);

  FlatBuffersSessionProfile acceptIncoming(AbstractMessage message) =>
      _prepare(message, outgoing: false, advertise: false);

  FlatBuffersSessionProfile _prepare(
    AbstractMessage message, {
    required bool outgoing,
    required bool advertise,
  }) {
    if (message is Abort) {
      if (_phase == _Phase.established ||
          _phase == _Phase.closing ||
          _phase == _Phase.closed) {
        throw StateError('Unexpected FlatBuffers bootstrap ABORT');
      }
      // Includes diagnostic metadata, but grants no session capability.
      Serializer().metadataFor(message);
      return _at(_Phase.closed);
    }
    if (message is Hello) {
      _expect(outgoing == _client && _phase == _Phase.initial, 'HELLO');
      _roles(message, const [
        'caller',
        'callee',
        'publisher',
        'subscriber',
      ], advertise: advertise);
      return _at(_Phase.hello);
    }
    if (message is Challenge) {
      _expect(
        outgoing != _client &&
            (_phase == _Phase.hello || _phase == _Phase.authenticated),
        'CHALLENGE',
      );
      final codec = Serializer();
      final extra = codec.metadataFor(message);
      if (advertise) {
        extra[flatBuffersMetadataFeature] = true;
        codec.retainMetadataValues(message, extra);
      }
      if (extra[flatBuffersMetadataFeature] != true) {
        throw UnsupportedError(
          'FlatBuffers CHALLENGE must acknowledge $flatBuffersMetadataFeature',
        );
      }
      return _at(_Phase.challenged);
    }
    if (message is Authenticate) {
      _expect(
        outgoing == _client && _phase == _Phase.challenged,
        'AUTHENTICATE',
      );
      return _at(_Phase.authenticated);
    }
    if (message is Welcome) {
      _expect(
        outgoing != _client &&
            (_phase == _Phase.hello || _phase == _Phase.authenticated),
        'WELCOME',
      );
      _roles(message, const ['broker', 'dealer'], advertise: advertise);
      return _at(_Phase.established);
    }
    if (message is Goodbye) {
      _expect(
        _phase == _Phase.established || _phase == _Phase.closing,
        'GOODBYE',
      );
      return _at(_phase == _Phase.closing ? _Phase.closed : _Phase.closing);
    }
    _expect(_phase == _Phase.established, 'application message');
    return this;
  }

  void _roles(
    AbstractMessage message,
    List<String> names, {
    required bool advertise,
  }) {
    final codec = Serializer();
    final dictionary = codec.metadataFor(message);
    final roles = dictionary['roles'];
    if (roles is! Map) {
      throw UnsupportedError('FlatBuffers bootstrap requires WAMP roles');
    }
    var applicable = 0;
    for (final name in names) {
      if (!roles.containsKey(name)) continue;
      applicable++;
      final role = roles[name];
      if (role is! Map) {
        throw UnsupportedError('Invalid FlatBuffers role $name');
      }
      if (advertise && role['features'] == null) {
        role['features'] = <String, dynamic>{};
      }
      final features = role['features'];
      if (features is! Map) {
        throw UnsupportedError('FlatBuffers role $name requires features');
      }
      if (advertise) features[flatBuffersMetadataFeature] = true;
      if (features[flatBuffersMetadataFeature] != true) {
        throw UnsupportedError(
          'FlatBuffers role $name must acknowledge $flatBuffersMetadataFeature',
        );
      }
    }
    if (applicable == 0) {
      throw UnsupportedError('No applicable FlatBuffers WAMP role');
    }
    if (advertise) codec.retainMetadataValues(message, dictionary);
  }

  void _expect(bool accepted, String name) {
    if (!accepted) {
      throw StateError('Unexpected $name during FlatBuffers session setup');
    }
  }
}
