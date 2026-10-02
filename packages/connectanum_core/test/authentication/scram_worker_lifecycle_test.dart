@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:connectanum_core/authentication.dart';
import 'package:connectanum_core/src/authentication/scram_key_derivation_web.dart';
import 'package:test/test.dart';

@JS('eval')
external JSAny? _evaluate(JSString source);

extension type _Harness(JSObject _) implements JSObject {
  external JSArray<_Worker> get workers;
  external JSArray<JSString> get created;
  external JSArray<JSString> get revoked;
  external set failUrl(bool value);
  external set failConstructor(bool value);
  external set failPost(bool value);
  external void restore();
}

extension type _Worker(JSObject _) implements JSObject {
  external int get terminations;
  external _Message get sent;
  external JSArray<JSArrayBuffer> get transfers;
  external void deliver(JSAny? bytes);
  external void failMessage();
  external void failWorker();
}

extension type _Message(JSObject _) implements JSObject {
  external String get kdf;
  external int get iterations;
  external int get memory;
  external int get keyLength;
  external JSUint8Array get password;
  external JSUint8Array get salt;
}

_Harness _installHarness() {
  final harness = _Harness(
    _evaluate(
          r'''
(() => {
  const Worker = globalThis.Worker;
  const create = URL.createObjectURL;
  const revoke = URL.revokeObjectURL;
  const h = {
    workers: [], created: [], revoked: [],
    failUrl: false, failConstructor: false, failPost: false,
    restore() {
      globalThis.Worker = Worker;
      URL.createObjectURL = create;
      URL.revokeObjectURL = revoke;
      for (const worker of h.workers) {
        worker.sent?.password.fill(0);
        worker.sent?.salt.fill(0);
      }
      for (const url of h.created) revoke.call(URL, url);
    }
  };
  URL.createObjectURL = function (blob) {
    if (h.failUrl) throw new Error("private-url-diagnostic");
    const url = create.call(URL, blob);
    h.created.push(url);
    return url;
  };
  URL.revokeObjectURL = function (url) {
    h.revoked.push(url);
    revoke.call(URL, url);
  };
  globalThis.Worker = class {
    constructor(url) {
      if (h.failConstructor) throw new Error("private-constructor-diagnostic");
      this.url = url;
      this.terminations = 0;
      h.workers.push(this);
    }
    postMessage(message, transfers) {
      this.sent = message;
      this.transfers = transfers;
      if (h.failPost) throw new Error("private-transfer-diagnostic");
    }
    terminate() { this.terminations++; }
    deliver(data) { this.onmessage(new MessageEvent("message", {data})); }
    failMessage() { this.onmessageerror(new Event("messageerror")); }
    failWorker() { this.onerror(new ErrorEvent("error", {message: "private-error"})); }
  };
  return h;
})()
'''
              .toJS,
        )
        as JSObject,
  );
  addTearDown(() => harness.restore());
  return harness;
}

ScramKeyDerivationRequest _request({int length = 32, int marker = 7}) =>
    ScramKeyDerivationRequest(
      password: Uint8List.fromList([1, 2, 3]),
      salt: Uint8List.fromList([marker, 2, 3, 4]),
      kdf: ScramAuthentication.kdfArgon,
      iterations: 2,
      memory: 100,
      keyLength: length,
    );

final class _Observation {
  _Observation(Future<Uint8List> result) {
    unawaited(
      result.then<void>(
        (bytes) {
          value = bytes;
          settled = true;
        },
        onError: (Object failure, StackTrace _) {
          error = failure;
          settled = true;
        },
      ),
    );
    addTearDown(() {
      final bytes = value;
      if (bytes != null) bytes.fillRange(0, bytes.length, 0);
    });
  }

  bool settled = false;
  Uint8List? value;
  Object? error;

  void expectFailure(String message) {
    expect(settled, isTrue, reason: 'The delivered event must settle the task');
    expect(value, isNull);
    expect(
      error,
      isA<ScramKeyDerivationException>().having(
        (error) => error.message,
        'sanitized failure',
        message,
      ),
    );
  }
}

// Drain callbacks after a synchronously delivered event, not a wall-clock deadline.
Future<void> _drain() => Future<void>.delayed(Duration.zero);

JSUint8Array _bytes(int length, int value) =>
    (Uint8List(length)..fillRange(0, length, value)).toJS;

final class _ManualTimer implements Timer {
  _ManualTimer(this.duration, this.callback);

  final Duration duration;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    callback();
  }
}

void main() {
  test('URL initialization failure is sanitized and recovers', () async {
    final harness = _installHarness()..failUrl = true;
    final deriver = PlatformScramKeyDeriver();
    addTearDown(deriver.dispose);
    expect(
      () => deriver.start(_request()),
      throwsA(
        isA<ScramKeyDerivationException>().having(
          (error) => error.message,
          'sanitized failure',
          'worker initialization failed',
        ),
      ),
    );
    expect(harness.workers.toDart, isEmpty);
    expect(harness.created.toDart, isEmpty);
    harness.failUrl = false;
    final observation = _Observation(deriver.start(_request()).result);
    harness.workers.toDart.single.deliver(_bytes(32, 9));
    await _drain();
    expect(observation.error, isNull);
    expect(observation.value, orderedEquals(List.filled(32, 9)));
  });

  for (final constructorFailure in [true, false]) {
    test(
      'initialization failure clears consumed input: constructor=$constructorFailure',
      () async {
        final harness = _installHarness();
        harness.failConstructor = constructorFailure;
        harness.failPost = !constructorFailure;
        final deriver = PlatformScramKeyDeriver();
        addTearDown(deriver.dispose);
        final request = _request();
        final observation = _Observation(deriver.start(request).result);
        await _drain();
        observation.expectFailure('worker initialization failed');
        expect(request.password, everyElement(0));
        expect(request.salt, everyElement(0));
        if (constructorFailure) {
          expect(harness.workers.toDart, isEmpty);
        } else {
          final worker = harness.workers.toDart.single;
          expect(worker.terminations, 1);
          expect(worker.sent.password.toDart, everyElement(0));
          expect(worker.sent.salt.toDart, everyElement(0));
        }
        await deriver.dispose();
        expect(
          harness.revoked.toDart.map((url) => url.toDart),
          orderedEquals(harness.created.toDart.map((url) => url.toDart)),
        );
      },
    );
  }

  for (final messageFailure in [true, false]) {
    test(
      'worker event failure settles and terminates: message=$messageFailure',
      () async {
        final harness = _installHarness();
        final deriver = PlatformScramKeyDeriver();
        addTearDown(deriver.dispose);
        final observation = _Observation(deriver.start(_request()).result);
        final worker = harness.workers.toDart.single;
        if (messageFailure) {
          worker.failMessage();
        } else {
          worker.failWorker();
        }
        await _drain();
        observation.expectFailure(
          messageFailure ? 'worker message failed' : 'worker failed',
        );
        expect(worker.terminations, 1);
        final late = _bytes(32, 5);
        worker.deliver(late);
        await _drain();
        expect(late.toDart, everyElement(0));
        expect(observation.value, isNull);
        expect(worker.terminations, 1);
      },
    );
  }

  for (final length in [16, 32, 64]) {
    test(
      'successful $length-byte event retains an owned result and rejects later events',
      () async {
        final harness = _installHarness();
        final deriver = PlatformScramKeyDeriver();
        addTearDown(deriver.dispose);
        final request = _request(length: length);
        final task = deriver.start(request);
        final observation = _Observation(task.result);
        final worker = harness.workers.toDart.single;
        expect(worker.sent.kdf, ScramAuthentication.kdfArgon);
        expect(worker.sent.iterations, 2);
        expect(worker.sent.memory, 100);
        expect(worker.sent.keyLength, length);
        expect(worker.sent.password.toDart, [1, 2, 3]);
        expect(worker.sent.salt.toDart, [7, 2, 3, 4]);
        expect(worker.transfers.toDart, hasLength(2));
        expect(request.password, everyElement(0));
        expect(request.salt, everyElement(0));
        final bytes = _bytes(length, 4);
        worker.deliver(bytes);
        await _drain();
        expect(observation.settled, isTrue);
        expect(observation.error, isNull);
        expect(observation.value, orderedEquals(List.filled(length, 4)));
        expect(bytes.toDart, everyElement(0));
        expect(worker.terminations, 1);
        final late = _bytes(length, 8);
        worker.deliver(late);
        worker.failMessage();
        worker.failWorker();
        await task.cancel();
        await _drain();
        expect(late.toDart, everyElement(0));
        expect(observation.value, orderedEquals(List.filled(length, 4)));
        expect(observation.error, isNull);
        expect(worker.terminations, 1);
      },
    );
  }

  for (final length in [0, 31, 33]) {
    test('malformed length $length is cleared before failure', () async {
      final harness = _installHarness();
      final deriver = PlatformScramKeyDeriver();
      addTearDown(deriver.dispose);
      final observation = _Observation(deriver.start(_request()).result);
      final worker = harness.workers.toDart.single;
      final bytes = _bytes(length, 6);
      worker.deliver(bytes);
      await _drain();
      observation.expectFailure('worker returned invalid length');
      expect(bytes.toDart, everyElement(0));
      expect(worker.terminations, 1);
    });
  }

  test(
    'disposal settles all pending tasks and revokes the shared URL once',
    () async {
      final harness = _installHarness();
      final deriver = PlatformScramKeyDeriver();
      addTearDown(deriver.dispose);
      final observations = [
        for (var i = 0; i < 3; i++)
          _Observation(deriver.start(_request()).result),
      ];
      expect(harness.created.toDart, hasLength(1));
      await deriver.dispose();
      await _drain();
      for (final observation in observations) {
        expect(observation.settled, isTrue);
        expect(observation.error, isA<ScramKeyDerivationCancelledException>());
      }
      for (final worker in harness.workers.toDart) {
        expect(worker.terminations, 1);
        worker.deliver(_bytes(32, 11));
      }
      await deriver.dispose();
      expect(harness.revoked.toDart, hasLength(1));
      expect(() => deriver.start(_request()), throwsStateError);
      expect(harness.workers.toDart, hasLength(3));
    },
  );

  for (final completesBeforeTimeout in [true, false]) {
    test(
      'configured timer is cancelled on settlement: success=$completesBeforeTimeout',
      () async {
        final harness = _installHarness();
        final deriver = PlatformScramKeyDeriver();
        addTearDown(deriver.dispose);
        final timers = <_ManualTimer>[];
        final task = runZoned(
          () => deriver.start(_request(), timeout: const Duration(seconds: 17)),
          zoneSpecification: ZoneSpecification(
            createTimer: (self, parent, zone, duration, callback) {
              final timer = _ManualTimer(
                duration,
                () => zone.runGuarded(callback),
              );
              timers.add(timer);
              return timer;
            },
          ),
        );
        final observation = _Observation(task.result);
        expect(timers, hasLength(1));
        final timer = timers.single;
        expect(timer.duration, const Duration(seconds: 17));
        expect(timer.isActive, isTrue);
        final worker = harness.workers.toDart.single;
        if (completesBeforeTimeout) {
          worker.deliver(_bytes(32, 8));
        } else {
          timer.fire();
        }
        await _drain();
        expect(observation.settled, isTrue);
        expect(timer.isActive, isFalse);
        expect(worker.terminations, 1);
        if (completesBeforeTimeout) {
          expect(observation.error, isNull);
          expect(observation.value, orderedEquals(List.filled(32, 8)));
        } else {
          expect(observation.value, isNull);
          expect(observation.error, isA<ScramKeyDerivationTimeoutException>());
        }
        timer.fire();
        await _drain();
        expect(worker.terminations, 1);
      },
    );
  }
}
