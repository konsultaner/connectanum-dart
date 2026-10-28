@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:connectanum_router/src/native/message_ready_notifications.dart';
import 'package:test/test.dart';

const _fixtureSource = r'''
#include <pthread.h>
typedef void (*wake_fn)(void);
static wake_fn callback;
static int registrations;
static int arms;
#ifdef WITH_REGISTER
void ct_set_message_ready_callback_v1(wake_fn value) {
  callback = value;
  registrations++;
}
#endif
#ifdef WITH_ARM
void ct_arm_message_ready_callback_v1(void) { arms++; }
#endif
int test_registered(void) { return callback != 0; }
int test_registrations(void) { return registrations; }
int test_arms(void) { return arms; }
void test_reset(void) { registrations = 0; arms = 0; }
static void *emit(void *unused) {
  (void)unused;
  if (callback) callback();
  return 0;
}
int test_emit_on_thread(void) {
  pthread_t thread;
  int result = pthread_create(&thread, 0, emit, 0);
  if (result) return result;
  return pthread_join(thread, 0);
}
''';

class _Fixture {
  _Fixture(this.path) : library = ffi.DynamicLibrary.open(path);
  final String path;
  final ffi.DynamicLibrary library;
  late final registered = library
      .lookupFunction<ffi.Int32 Function(), int Function()>('test_registered');
  late final registrations = library
      .lookupFunction<ffi.Int32 Function(), int Function()>(
        'test_registrations',
      );
  late final arms = library
      .lookupFunction<ffi.Int32 Function(), int Function()>('test_arms');
  late final reset = library
      .lookupFunction<ffi.Void Function(), void Function()>('test_reset');
  late final _emit = library
      .lookupFunction<ffi.Int32 Function(), int Function()>(
        'test_emit_on_thread',
      );
  void emit() => expect(_emit(), 0);
}

void main() {
  group(
    'optional native message-ready bridge',
    () {
      late Directory directory;
      late _Fixture complete;
      late _Fixture registerOnly;
      late _Fixture armOnly;
      setUpAll(() async {
        directory = await Directory.systemTemp.createTemp(
          'connectanum-wake-abi-',
        );
        final source = File('${directory.path}/fixture.c');
        await source.writeAsString(_fixtureSource);
        Future<_Fixture> build(String name, List<String> definitions) async {
          final path =
              '${directory.path}/$name.${Platform.isMacOS ? 'dylib' : 'so'}';
          final result = await Process.run('cc', [
            Platform.isMacOS ? '-dynamiclib' : '-shared',
            '-fPIC',
            '-pthread',
            ...definitions.map((name) => '-D$name'),
            source.path,
            '-o',
            path,
          ]);
          expect(result.exitCode, 0, reason: '${result.stderr}');
          return _Fixture(path);
        }

        complete = await build('complete', ['WITH_REGISTER', 'WITH_ARM']);
        registerOnly = await build('register-only', ['WITH_REGISTER']);
        armOnly = await build('arm-only', ['WITH_ARM']);
      });
      tearDownAll(() async => directory.delete(recursive: true));
      setUp(() {
        for (final fixture in [complete, registerOnly, armOnly]) {
          expect(fixture.registered(), 0);
          fixture.reset();
        }
      });

      test(
        'requires both optional symbols and preserves polling fallback',
        () async {
          for (final fixture in [registerOnly, armOnly]) {
            final bridge = NativeMessageReadyNotifications(fixture.library);
            addTearDown(bridge.dispose);
            expect(bridge.hasNativeSupport, isFalse);
            final received = <void>[];
            final subscription = bridge.events.listen(received.add);
            bridge.resume();
            bridge.arm();
            fixture.emit();
            await Future<void>.delayed(Duration.zero);
            expect(received, isEmpty);
            expect(fixture.registrations(), 0);
            expect(fixture.arms(), 0);
            await subscription.cancel();
            bridge.dispose();
          }
        },
      );

      test(
        'one native listener serves multiple subscribers until last cancel',
        () async {
          final bridge = NativeMessageReadyNotifications(complete.library);
          addTearDown(bridge.dispose);
          expect(bridge.hasNativeSupport, isTrue);
          var countA = 0;
          var countB = 0;
          final firstA = Completer<void>();
          var nextB = Completer<void>();
          final a = bridge.events.listen((_) {
            countA++;
            firstA.complete();
          });
          final b = bridge.events.listen((_) {
            countB++;
            nextB.complete();
          });
          addTearDown(a.cancel);
          addTearDown(b.cancel);
          expect(complete.registered(), 0);
          bridge.resume();
          expect(complete.registered(), 1);
          expect(complete.registrations(), 1);
          bridge.arm();
          expect(complete.arms(), 1);
          complete.emit();
          await Future.wait([
            firstA.future,
            nextB.future,
          ]).timeout(const Duration(seconds: 5));
          expect(countA, 1);
          expect(countB, 1);
          await a.cancel();
          expect(complete.registered(), 1);
          nextB = Completer<void>();
          complete.emit();
          await nextB.future.timeout(const Duration(seconds: 5));
          expect(countA, 1);
          expect(countB, 2);
          await b.cancel();
          expect(complete.registered(), 0);
          expect(complete.registrations(), 2);
        },
      );

      test(
        'cancel and relisten ignore already queued stale notifications',
        () async {
          final bridge = NativeMessageReadyNotifications(complete.library)
            ..resume();
          addTearDown(bridge.dispose);
          var oldCount = 0;
          final old = bridge.events.listen((_) => oldCount++);
          complete.emit();
          await old.cancel();
          expect(complete.registered(), 0);
          final fresh = Completer<void>();
          var freshCount = 0;
          final subscription = bridge.events.listen((_) {
            freshCount++;
            if (!fresh.isCompleted) fresh.complete();
          });
          addTearDown(subscription.cancel);
          complete.emit();
          await fresh.future.timeout(const Duration(seconds: 5));
          await Future<void>.delayed(Duration.zero);
          expect(oldCount, 0);
          expect(freshCount, 1);
        },
      );

      test('suspend, restart and disposal release the callable', () async {
        final bridge = NativeMessageReadyNotifications(complete.library)
          ..resume();
        addTearDown(bridge.dispose);
        final received = Completer<void>();
        var count = 0;
        final subscription = bridge.events.listen((_) {
          count++;
          if (!received.isCompleted) received.complete();
        });
        addTearDown(subscription.cancel);
        complete.emit();
        bridge.suspend();
        expect(complete.registered(), 0);
        bridge.arm();
        expect(complete.arms(), 0);
        bridge.resume();
        expect(complete.registered(), 1);
        complete.emit();
        await received.future.timeout(const Duration(seconds: 5));
        await Future<void>.delayed(Duration.zero);
        expect(count, 1);
        bridge.dispose();
        bridge.dispose();
        bridge.resume();
        bridge.arm();
        expect(complete.registered(), 0);
        expect(complete.arms(), 0);
        complete.emit();
        await Future<void>.delayed(Duration.zero);
        expect(count, 1);
      });

      test(
        'an uncancelled subscriber does not keep a disposed process alive',
        () async {
          var configRoot = Directory.current.absolute;
          while (!File(
            '${configRoot.path}/.dart_tool/package_config.json',
          ).existsSync()) {
            if (configRoot.parent.path == configRoot.path) {
              fail('No package config');
            }
            configRoot = configRoot.parent;
          }
          final script = File('${directory.path}/exit.dart');
          await script.writeAsString('''
import 'dart:ffi';
import 'package:connectanum_router/src/native/message_ready_notifications.dart';
void main(List<String> args) {
  final bridge = NativeMessageReadyNotifications(DynamicLibrary.open(args.single));
  bridge.resume();
  bridge.events.listen((_) {});
  bridge.dispose();
  print('disposed');
}
''');
          final child = await Process.start(Platform.resolvedExecutable, [
            '--packages=${configRoot.path}/.dart_tool/package_config.json',
            script.path,
            complete.path,
          ]);
          final output = child.stdout.transform(utf8.decoder).join();
          final errors = child.stderr.transform(utf8.decoder).join();
          try {
            expect(
              await child.exitCode.timeout(const Duration(seconds: 10)),
              0,
            );
            expect(await output, contains('disposed'));
            expect(await errors, isEmpty);
          } finally {
            child.kill();
          }
        },
      );
    },
    skip: !Platform.isLinux && !Platform.isMacOS
        ? 'POSIX C ABI fixture'
        : false,
  );
}
