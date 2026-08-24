import 'scram_key_derivation.dart';

final class PlatformScramKeyDeriver implements ScramKeyDeriver {
  @override
  ScramKeyDerivationTask start(
    ScramKeyDerivationRequest request, {
    Duration? timeout,
  }) => throw UnsupportedError(
    'SCRAM key derivation is not supported on this platform',
  );

  @override
  Future<void> dispose() async {}
}
