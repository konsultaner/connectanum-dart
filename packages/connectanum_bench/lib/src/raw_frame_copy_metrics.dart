const rawFrameCopyMetricFields = [
  'coalescing_copy_bytes',
  'range_copy_bytes',
  'single_segment_contiguous_requests',
  'multi_segment_contiguous_requests',
];

/// Requests for contiguity are not copies: a single span can retain its owner.
/// Missing or rewound process observations must not turn into zero-byte claims.
Map<String, Object?> rawFrameCopyMetricsDelta(
  Map<String, int>? before,
  Map<String, int>? after,
) {
  Map<String, Object?> unavailable(String reason) => {
    'status': 'not_measured',
    'reason': reason,
  };
  if (before == null || after == null) {
    return unavailable('native raw-frame copy metrics ABI v1 is unavailable');
  }
  final delta = <String, int>{};
  for (final field in rawFrameCopyMetricFields) {
    final start = before[field];
    final end = after[field];
    if (start == null || end == null || start < 0 || end < start) {
      return unavailable(
        'raw-frame counter $field is missing, invalid or rewound',
      );
    }
    delta[field] = end - start;
  }
  return {
    'status': 'measured',
    ...delta,
    'known_copy_bytes':
        delta['coalescing_copy_bytes']! + delta['range_copy_bytes']!,
  };
}
