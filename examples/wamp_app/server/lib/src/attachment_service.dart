import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'attachment_store.dart';
import 'mailbox_store.dart';

final class AttachmentService {
  const AttachmentService({required this.store, required this.mailbox});

  final AttachmentStore store;
  final MailboxStore mailbox;

  Future<AttachmentChunkStoreResult> putChunk(
    String callerUsername,
    EncryptedAttachmentChunk chunk,
  ) {
    final caller = AccountRegistration.normalizeUsername(callerUsername);
    if (caller != chunk.senderUsername) {
      throw StateError(
        'The authenticated sender does not match the attachment chunk.',
      );
    }
    return store.put(chunk);
  }

  Future<AttachmentUploadStatus> status(
    String callerUsername, {
    required String messageId,
    required String attachmentId,
    required int chunkCount,
  }) {
    return store.status(
      senderUsername: callerUsername,
      messageId: messageId,
      attachmentId: attachmentId,
      chunkCount: chunkCount,
    );
  }

  Future<EncryptedAttachmentChunk> getChunk(
    String callerUsername, {
    required String messageId,
    required String attachmentId,
    required int chunkIndex,
    DateTime? now,
  }) async {
    final message = await mailbox.findVisibleMessage(
      callerUsername,
      messageId,
      now: now,
    );
    if (message == null ||
        !message.message.attachmentIds.contains(attachmentId)) {
      throw AttachmentNotFound(attachmentId);
    }
    return store.readChunk(
      senderUsername: message.message.senderUsername,
      messageId: messageId,
      attachmentId: attachmentId,
      chunkIndex: chunkIndex,
    );
  }
}
