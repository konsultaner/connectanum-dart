const encodedWampVolumeScope = 'accepted_wamp_message_bytes_v1';
const encodedWampVolumeVersionField = 'encoded_wamp_volume_version';
const encodedWampVolumeBytesField = 'encoded_wamp_bytes_accepted';
const encodedWampVolumeRejectedField = 'encoded_wamp_send_rejections';
const _limit = 9007199254740991;

Map<String, Object?> encodedWampVolumeDelta(
  Map<String, Object?>? before,
  Map<String, Object?>? after,
) {
  Map<String, Object?> unavailable(String reason) => {
    'status': 'not_measured',
    'measurement_scope': encodedWampVolumeScope,
    'reason': reason,
  };
  if (before?[encodedWampVolumeVersionField] is! int ||
      before?[encodedWampVolumeVersionField] != 1 ||
      after?[encodedWampVolumeVersionField] is! int ||
      after?[encodedWampVolumeVersionField] != 1) {
    return unavailable('encoded WAMP volume observation v1 is unavailable');
  }
  final deltas = <String, int>{};
  for (final field in [
    encodedWampVolumeBytesField,
    encodedWampVolumeRejectedField,
  ]) {
    final start = before![field], end = after![field];
    if (start is! int ||
        end is! int ||
        start < 0 ||
        end < start ||
        start > _limit ||
        end > _limit) {
      return unavailable(
        'encoded WAMP counter $field is missing, invalid or rewound',
      );
    }
    deltas[field] = end - start;
  }
  if (deltas[encodedWampVolumeRejectedField] != 0) {
    return {
      ...unavailable('an encoded WAMP submission failed'),
      'known_accepted_bytes': deltas[encodedWampVolumeBytesField],
      'rejected_submissions': deltas[encodedWampVolumeRejectedField],
    };
  }
  return {
    'status': 'measured',
    'measurement_scope': encodedWampVolumeScope,
    'accepted_bytes': deltas[encodedWampVolumeBytesField],
    'rejected_submissions': 0,
  };
}

Map<String, Object?> mergeEncodedWampVolumes(Map<String, Object?> inputs) {
  final components = <String, int>{}, errors = <String>[];
  var total = 0;
  for (final entry in inputs.entries) {
    final value = entry.value;
    if (value is! Map ||
        value['status'] != 'measured' ||
        value['measurement_scope'] != encodedWampVolumeScope ||
        value['accepted_bytes'] is! int ||
        (value['accepted_bytes'] as int) < 0 ||
        (value['accepted_bytes'] as int) > _limit ||
        value['rejected_submissions'] is! int ||
        value['rejected_submissions'] != 0) {
      errors.add('${entry.key} is incomplete');
      continue;
    }
    final bytes = value['accepted_bytes'] as int;
    if (total > _limit - bytes) {
      errors.add('aggregate exceeds the exact integer range');
      continue;
    }
    components[entry.key] = bytes;
    total += bytes;
  }
  return {
    'status': errors.isEmpty && inputs.isNotEmpty ? 'measured' : 'not_measured',
    'measurement_scope': encodedWampVolumeScope,
    if (errors.isEmpty && inputs.isNotEmpty) 'accepted_bytes': total,
    'known_accepted_bytes': total,
    'components': components,
    'unknown_boundaries': errors,
    if (errors.isEmpty && inputs.isNotEmpty) 'rejected_submissions': 0,
    'excludes': [
      'RawSocket/WebSocket framing',
      'TLS records',
      'network packet headers',
    ],
  };
}
