import 'attachment_crypto_worker.dart';

final class PlatformAttachmentCryptoWorker implements AttachmentCryptoWorker {
  @override
  AttachmentCryptoTask start(
    AttachmentCryptoRequest request, {
    Duration? timeout,
  }) => throw UnsupportedError(
    'Attachment crypto is not supported on this platform',
  );

  @override
  Future<void> dispose() async {}
}
