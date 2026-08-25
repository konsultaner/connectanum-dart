import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:wamp_app_protocol/wamp_app_protocol.dart';

final class CallConflict implements Exception {
  const CallConflict(this.callId);
  final String callId;
}

final class CallNotFound implements Exception {
  const CallNotFound(this.callId);
  final String callId;
}

final class CallAlreadyAnswered implements Exception {
  const CallAlreadyAnswered(this.callId);
  final String callId;
}

final class CallAlreadyEnded implements Exception {
  const CallAlreadyEnded(this.callId);
  final String callId;
}

final class CallLimitExceeded implements Exception {
  const CallLimitExceeded();
}

final class CallAppendResult {
  const CallAppendResult({required this.update, required this.duplicate});

  final CallUpdate update;
  final bool duplicate;
}

final class CallStore {
  CallStore(
    String path, {
    this.maximumCalls = 100000,
    this.maximumEvents = 500000,
    this.maximumConcurrentCallsPerAccount = 4,
    this.ringTimeout = const Duration(minutes: 2),
    this.maximumCallDuration = const Duration(hours: 24),
  }) : file = File(path);

  final File file;
  final int maximumCalls;
  final int maximumEvents;
  final int maximumConcurrentCallsPerAccount;
  final Duration ringTimeout;
  final Duration maximumCallDuration;

  static final Map<String, Future<void>> _pathWriteTails = {};

  Future<void> initialize() async {
    await file.parent.create(recursive: true);
    if (!await file.exists()) {
      await _serializeWrite(() async {
        if (!await file.exists()) {
          await _writeDocument(_CallDocument(nextCursor: 1));
        }
      });
    }
  }

  Future<CallAppendResult> start(CallStartRequest request, {DateTime? now}) =>
      _serializeWrite(() async {
        request.validate();
        final timestamp = (now ?? DateTime.now()).toUtc();
        final document = await _readDocument();
        final expired = _expire(document, timestamp);
        final existing = document.calls[request.callId];
        if (existing != null) {
          final first = document.events
              .where((update) => update.call.callId == request.callId)
              .firstOrNull;
          if (first == null ||
              first.call.media != request.media ||
              first.call.calleeUsername != request.calleeUsername ||
              first.call.callerUsername != request.callerUsername ||
              first.call.callerDeviceId != request.callerDeviceId ||
              jsonEncode(
                    first.signals.map((signal) => signal.toJson()).toList(),
                  ) !=
                  jsonEncode(
                    request.offers.map((signal) => signal.toJson()).toList(),
                  )) {
            throw CallConflict(request.callId);
          }
          final latest = document.events
              .where((update) => update.call.callId == request.callId)
              .last;
          if (expired) await _writeDocument(document);
          return CallAppendResult(update: latest, duplicate: true);
        }
        if (document.calls.length >= maximumCalls ||
            document.events.length >= maximumEvents) {
          throw const CallLimitExceeded();
        }
        final activeForParticipants = document.calls.values.where(
          (call) =>
              !call.isTerminal &&
              (call.callerUsername == request.callerUsername ||
                  call.calleeUsername == request.callerUsername ||
                  call.callerUsername == request.calleeUsername ||
                  call.calleeUsername == request.calleeUsername),
        );
        final counts = <String, int>{};
        for (final call in activeForParticipants) {
          counts.update(
            call.callerUsername,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
          counts.update(
            call.calleeUsername,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
        if ((counts[request.callerUsername] ?? 0) >=
                maximumConcurrentCallsPerAccount ||
            (counts[request.calleeUsername] ?? 0) >=
                maximumConcurrentCallsPerAccount) {
          throw const CallLimitExceeded();
        }
        final call = CallRecord(
          callId: request.callId,
          callerUsername: request.callerUsername,
          callerDeviceId: request.callerDeviceId,
          calleeUsername: request.calleeUsername,
          media: request.media,
          state: CallState.ringing,
          createdAt: timestamp,
        );
        final update = _append(document, call, request.offers);
        await _writeDocument(document);
        return CallAppendResult(update: update, duplicate: false);
      });

  Future<CallAppendResult> accept(
    EncryptedCallSignal answer, {
    DateTime? now,
  }) => _serializeWrite(() async {
    answer.validate();
    if (answer.kind != CallSignalKind.answer) {
      throw const FormatException('Call acceptance requires an answer.');
    }
    final timestamp = (now ?? DateTime.now()).toUtc();
    final document = await _readDocument();
    final expired = _expire(document, timestamp);
    final duplicate = _findSignal(document, answer);
    if (duplicate != null) {
      if (expired) await _writeDocument(document);
      return CallAppendResult(update: duplicate, duplicate: true);
    }
    final call = document.calls[answer.callId];
    if (call == null) throw CallNotFound(answer.callId);
    if (call.isTerminal) throw CallAlreadyEnded(answer.callId);
    if (call.state == CallState.active) {
      throw CallAlreadyAnswered(answer.callId);
    }
    if (answer.senderUsername != call.calleeUsername ||
        answer.recipientUsername != call.callerUsername ||
        answer.recipientDeviceId != call.callerDeviceId) {
      throw const FormatException('Call answer participants are invalid.');
    }
    final accepted = CallRecord(
      callId: call.callId,
      callerUsername: call.callerUsername,
      callerDeviceId: call.callerDeviceId,
      calleeUsername: call.calleeUsername,
      media: call.media,
      state: CallState.active,
      acceptedDeviceId: answer.senderDeviceId,
      createdAt: call.createdAt,
      answeredAt: timestamp,
    );
    final update = _append(document, accepted, [answer]);
    await _writeDocument(document);
    return CallAppendResult(update: update, duplicate: false);
  });

  Future<CallAppendResult> signal(EncryptedCallSignal signal) =>
      _serializeWrite(() async {
        signal.validate();
        if (signal.kind != CallSignalKind.iceCandidate) {
          throw const FormatException('Only ICE candidates use call.signal.');
        }
        final document = await _readDocument();
        final expired = _expire(document, DateTime.now().toUtc());
        final duplicate = _findSignal(document, signal);
        if (duplicate != null) {
          if (expired) await _writeDocument(document);
          return CallAppendResult(update: duplicate, duplicate: true);
        }
        final call = document.calls[signal.callId];
        if (call == null) throw CallNotFound(signal.callId);
        if (call.isTerminal) throw CallAlreadyEnded(signal.callId);
        if (call.state != CallState.active ||
            !_matchesSelectedParticipants(call, signal)) {
          throw const FormatException(
            'ICE candidate participants are invalid.',
          );
        }
        final signalCount = document.events
            .where((update) => update.call.callId == call.callId)
            .fold<int>(0, (count, update) => count + update.signals.length);
        if (signalCount >= WampAppCallLimits.maximumSignalsPerCall ||
            document.events.length >= maximumEvents) {
          throw const CallLimitExceeded();
        }
        final update = _append(document, call, [signal]);
        await _writeDocument(document);
        return CallAppendResult(update: update, duplicate: false);
      });

  Future<CallAppendResult> end(EncryptedCallSignal signal, {DateTime? now}) =>
      _serializeWrite(() async {
        signal.validate();
        if (signal.kind != CallSignalKind.decline &&
            signal.kind != CallSignalKind.hangup) {
          throw const FormatException('Call termination signal is invalid.');
        }
        final timestamp = (now ?? DateTime.now()).toUtc();
        final document = await _readDocument();
        final expired = _expire(document, timestamp);
        final duplicate = _findSignal(document, signal);
        if (duplicate != null) {
          if (expired) await _writeDocument(document);
          return CallAppendResult(update: duplicate, duplicate: true);
        }
        final call = document.calls[signal.callId];
        if (call == null) throw CallNotFound(signal.callId);
        if (call.isTerminal) throw CallAlreadyEnded(signal.callId);

        late final CallState nextState;
        if (call.state == CallState.ringing) {
          if (signal.senderUsername == call.calleeUsername &&
              signal.recipientUsername == call.callerUsername &&
              signal.recipientDeviceId == call.callerDeviceId &&
              signal.kind == CallSignalKind.decline) {
            nextState = CallState.declined;
          } else if (signal.senderUsername == call.callerUsername &&
              signal.senderDeviceId == call.callerDeviceId &&
              signal.recipientUsername == call.calleeUsername &&
              signal.kind == CallSignalKind.hangup) {
            nextState = CallState.cancelled;
          } else {
            throw const FormatException('Ringing call termination is invalid.');
          }
        } else {
          if (signal.kind != CallSignalKind.hangup ||
              !_matchesSelectedParticipants(call, signal)) {
            throw const FormatException('Active call termination is invalid.');
          }
          nextState = CallState.ended;
        }
        final ended = CallRecord(
          callId: call.callId,
          callerUsername: call.callerUsername,
          callerDeviceId: call.callerDeviceId,
          calleeUsername: call.calleeUsername,
          media: call.media,
          state: nextState,
          acceptedDeviceId: call.acceptedDeviceId,
          createdAt: call.createdAt,
          answeredAt: call.answeredAt,
          endedAt: timestamp,
        );
        final update = _append(document, ended, [signal]);
        await _writeDocument(document);
        return CallAppendResult(update: update, duplicate: false);
      });

  Future<CallBatch> sync(
    String username,
    String deviceId, {
    required int afterCursor,
    int limit = 100,
    DateTime? now,
  }) => _serializeWrite(() async {
    if (afterCursor < 0) {
      throw const FormatException('after_cursor must not be negative.');
    }
    if (limit < 1 || limit > 500) {
      throw const FormatException('limit must be between 1 and 500.');
    }
    final normalized = AccountRegistration.normalizeUsername(username);
    final document = await _readDocument();
    final expired = _expire(document, (now ?? DateTime.now()).toUtc());
    final currentCursor = document.nextCursor - 1;
    if (afterCursor > currentCursor) {
      throw const FormatException('after_cursor is ahead of call state.');
    }
    final updates = <CallUpdate>[];
    for (final update in document.events) {
      if (update.cursor <= afterCursor ||
          (update.call.callerUsername != normalized &&
              update.call.calleeUsername != normalized)) {
        continue;
      }
      final signals = update.signals
          .where(
            (signal) =>
                (signal.senderUsername == normalized &&
                    signal.senderDeviceId == deviceId) ||
                (signal.recipientUsername == normalized &&
                    signal.recipientDeviceId == deviceId),
          )
          .toList(growable: false);
      updates.add(
        CallUpdate(cursor: update.cursor, call: update.call, signals: signals),
      );
      if (updates.length == limit) break;
    }
    if (expired) await _writeDocument(document);
    return CallBatch(
      nextCursor: updates.length == limit ? updates.last.cursor : currentCursor,
      updates: updates,
    );
  });

  CallUpdate _append(
    _CallDocument document,
    CallRecord call,
    Iterable<EncryptedCallSignal> signals,
  ) {
    if (document.events.length >= maximumEvents) {
      throw const CallLimitExceeded();
    }
    final update = CallUpdate(
      cursor: document.nextCursor,
      call: call,
      signals: signals,
    );
    document.nextCursor += 1;
    document.calls[call.callId] = call;
    document.events.add(update);
    return update;
  }

  CallUpdate? _findSignal(_CallDocument document, EncryptedCallSignal signal) {
    for (final update in document.events.reversed) {
      for (final existing in update.signals) {
        if (existing.signalId != signal.signalId) continue;
        if (jsonEncode(existing.toJson()) != jsonEncode(signal.toJson())) {
          throw CallConflict(signal.callId);
        }
        return update;
      }
    }
    return null;
  }

  bool _matchesSelectedParticipants(
    CallRecord call,
    EncryptedCallSignal signal,
  ) {
    final acceptedDevice = call.acceptedDeviceId;
    if (acceptedDevice == null) return false;
    final callerToCallee =
        signal.senderUsername == call.callerUsername &&
        signal.senderDeviceId == call.callerDeviceId &&
        signal.recipientUsername == call.calleeUsername &&
        signal.recipientDeviceId == acceptedDevice;
    final calleeToCaller =
        signal.senderUsername == call.calleeUsername &&
        signal.senderDeviceId == acceptedDevice &&
        signal.recipientUsername == call.callerUsername &&
        signal.recipientDeviceId == call.callerDeviceId;
    return callerToCallee || calleeToCaller;
  }

  bool _expire(_CallDocument document, DateTime timestamp) {
    var changed = false;
    for (final call in document.calls.values.toList(growable: false)) {
      final expiredRinging =
          call.state == CallState.ringing &&
          !timestamp.isBefore(call.createdAt.add(ringTimeout));
      final expiredActive =
          call.state == CallState.active &&
          !timestamp.isBefore(
            (call.answeredAt ?? call.createdAt).add(maximumCallDuration),
          );
      if (!expiredRinging && !expiredActive) continue;
      _append(
        document,
        CallRecord(
          callId: call.callId,
          callerUsername: call.callerUsername,
          callerDeviceId: call.callerDeviceId,
          calleeUsername: call.calleeUsername,
          media: call.media,
          state: expiredRinging ? CallState.missed : CallState.ended,
          acceptedDeviceId: call.acceptedDeviceId,
          createdAt: call.createdAt,
          answeredAt: call.answeredAt,
          endedAt: timestamp,
        ),
        const [],
      );
      changed = true;
    }
    return changed;
  }

  Future<_CallDocument> _readDocument() async {
    if (!await file.exists()) return _CallDocument(nextCursor: 1);
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map || decoded['version'] != 1) {
      throw const FormatException('Call store document is invalid.');
    }
    final nextCursor = decoded['next_cursor'];
    final rawCalls = decoded['calls'];
    final rawEvents = decoded['events'];
    if (nextCursor is! int ||
        nextCursor < 1 ||
        rawCalls is! List ||
        rawEvents is! List) {
      throw const FormatException('Call store document is invalid.');
    }
    final calls = <String, CallRecord>{};
    for (final raw in rawCalls) {
      if (raw is! Map) {
        throw const FormatException('Call store entry is invalid.');
      }
      final call = CallRecord.fromJson(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (calls.putIfAbsent(call.callId, () => call) != call) {
        throw const FormatException('Call store contains duplicate calls.');
      }
    }
    final events = rawEvents
        .map((raw) {
          if (raw is! Map) {
            throw const FormatException('Call event is invalid.');
          }
          return CallUpdate.fromJson(
            raw.map((key, value) => MapEntry(key.toString(), value)),
          );
        })
        .toList(growable: true);
    if (events.length > maximumEvents ||
        calls.length > maximumCalls ||
        events.any((event) => event.cursor >= nextCursor)) {
      throw const FormatException('Call store exceeds its bounds.');
    }
    return _CallDocument(nextCursor: nextCursor, calls: calls, events: events);
  }

  Future<void> _writeDocument(_CallDocument document) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'version': 1,
        'next_cursor': document.nextCursor,
        'calls': document.calls.values.map((call) => call.toJson()).toList(),
        'events': document.events.map((event) => event.toJson()).toList(),
      }),
      flush: true,
    );
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', temporary.path]);
    }
    await temporary.rename(file.path);
  }

  Future<T> _serializeWrite<T>(Future<T> Function() action) {
    final path = file.absolute.path;
    final previous = _pathWriteTails[path] ?? Future<void>.value();
    final completer = Completer<void>();
    _pathWriteTails[path] = completer.future;
    return previous.then((_) => action()).whenComplete(() {
      completer.complete();
      if (identical(_pathWriteTails[path], completer.future)) {
        _pathWriteTails.remove(path);
      }
    });
  }
}

final class _CallDocument {
  _CallDocument({
    required this.nextCursor,
    Map<String, CallRecord>? calls,
    List<CallUpdate>? events,
  }) : calls = calls ?? <String, CallRecord>{},
       events = events ?? <CallUpdate>[];

  int nextCursor;
  final Map<String, CallRecord> calls;
  final List<CallUpdate> events;
}
