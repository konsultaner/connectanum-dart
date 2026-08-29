import 'dart:async';

import 'attachment_store.dart';
import 'mailbox_store.dart';

final class AttachmentRetentionController {
  AttachmentRetentionController({
    required this.store,
    required this.mailbox,
    required this.interval,
    this.onBackgroundError,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval', 'must be positive');
    }
  }

  final AttachmentStore store;
  final MailboxStore mailbox;
  final Duration interval;
  final void Function(Object error, StackTrace stackTrace)? onBackgroundError;
  final DateTime Function() _clock;

  Timer? _timer;
  Future<void>? _running;
  var _closed = false;

  Future<void> start() async {
    if (_closed || _timer != null) {
      throw StateError('Attachment retention is already started or closed.');
    }
    await runOnce();
    if (_closed) return;
    _timer = Timer.periodic(interval, (_) => _schedule());
  }

  Future<void> runOnce() async {
    if (_closed) return;
    final running = _running;
    if (running != null) return running;
    final timestamp = _clock().toUtc();
    late final Future<void> operation;
    operation = store
        .prune(
          loadActiveMessages: () =>
              mailbox.activeAttachmentMessages(now: timestamp),
          loadImmediatelyRemovableMessages: () =>
              mailbox.consumedOneTimeAttachmentMessages(),
          now: timestamp,
        )
        .then<void>((_) {})
        .whenComplete(() {
          if (identical(_running, operation)) _running = null;
        });
    _running = operation;
    return operation;
  }

  void _schedule() {
    if (_closed || _running != null) return;
    unawaited(
      runOnce().catchError((Object error, StackTrace stackTrace) {
        onBackgroundError?.call(error, stackTrace);
      }),
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    await _running;
  }
}
