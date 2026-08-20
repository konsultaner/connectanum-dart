import 'file_transfer.dart';

/// Local path sources are only available on Dart IO platforms.
Future<WampFileSource> wampFileSourceFromPath(
  String path, {
  String? name,
  String? contentType,
  String? sha256Digest,
  Map<String, dynamic>? custom,
}) {
  throw UnsupportedError('Local file paths are unavailable on this platform');
}
