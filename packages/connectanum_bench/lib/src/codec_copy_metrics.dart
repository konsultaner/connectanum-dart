const codecCopyMetricFields = [
  'vector_copy_bytes',
  'string_copy_bytes',
  'growth_copy_bytes',
  'parser_read_copy_bytes',
  'framing_copy_bytes',
  'key_material_copy_bytes',
];

/// Native codec fields observe actual source bytes, distinct from transport.
/// Missing or rewound process observations must not turn into zero-byte claims.
Map<String, Object?> codecCopyMetricsDelta(
  Map<String, int>? before,
  Map<String, int>? after,
) {
  Map<String, Object?> unavailable(String reason) => {
    'status': 'not_measured',
    'reason': reason,
  };
  if (before == null || after == null) {
    return unavailable('native codec copy metrics ABI v1 is unavailable');
  }
  final delta = <String, int>{};
  for (final field in codecCopyMetricFields) {
    final start = before[field];
    final end = after[field];
    if (start == null || end == null || start < 0 || end < start) {
      return unavailable(
        'codec counter $field is missing, invalid or rewound',
      );
    }
    delta[field] = end - start;
  }
  return {
    'status': 'measured',
    ...delta,
    'known_copy_bytes': codecCopyMetricFields.fold<int>(
      0,
      (sum, field) => sum + delta[field]!,
    ),
  };
}
