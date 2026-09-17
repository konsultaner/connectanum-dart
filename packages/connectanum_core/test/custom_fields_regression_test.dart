import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

void main() {
  group('lazy metadata map lifecycle', () {
    test('initial values are copied, including explicit nulls', () {
      final initial = <String, Object?>{'value': null};
      final map = LazyStringKeyMap<Object?>(initialValues: initial);
      initial['value'] = 'changed';
      initial['external'] = true;
      map['local'] = true;
      expect(map, {'value': null, 'local': true});
      expect(initial, {'value': 'changed', 'external': true});
      expect(map.hasPendingLoader, isFalse);
    });

    test('reading explicit null does not evaluate the pending loader', () {
      var loads = 0;
      final map = LazyStringKeyMap<Object?>(
        initialValues: {'value': null},
        loader: () {
          loads++;
          return {'value': 'stale', 'additional': 1};
        },
      );
      expect(map.hasPendingLoader, isTrue);
      expect(map['value'], isNull);
      expect(loads, 0);
      expect(map['additional'], 1);
      expect(map.hasPendingLoader, isFalse);
      expect(map['value'], isNull);
      expect(map['missing'], isNull);
      expect(loads, 1);
    });

    test('queued loaders run once and newer pending values win', () {
      final calls = <int>[];
      final map = LazyStringKeyMap<int>();
      map.attachLoader(() {
        calls.add(1);
        return {'first': 1, 'shared': 1};
      });
      map.attachLoader(() {
        calls.add(2);
        return {'second': 2, 'shared': 2};
      });
      expect(calls, isEmpty);
      expect(map['shared'], 2);
      expect(map, {'first': 1, 'second': 2, 'shared': 2});
      expect(calls, [1, 2]);
      expect(map.hasPendingLoader, isFalse);
    });

    test(
      'clear consumes pending entries without allowing their restoration',
      () {
        var loads = 0;
        final map = LazyStringKeyMap<int>(
          initialValues: {'first': 1},
          loader: () {
            loads++;
            return {'second': 2};
          },
        );
        map.clear();
        expect(map, isEmpty);
        expect(map['second'], isNull);
        expect(map.hasPendingLoader, isFalse);
        expect(loads, 1);
        map.attachLoader(() => {'fresh': 3});
        expect(map, {'fresh': 3});
        map.clear();
        expect(map, isEmpty);
      },
    );

    test('removal resolves a lazy value and returns it only once', () {
      final map = LazyStringKeyMap<int>(
        loader: () => {'removed': 1, 'retained': 2},
      );
      expect(map.remove('removed'), 1);
      expect(map.remove('removed'), isNull);
      expect(map, {'retained': 2});
      map.attachLoader(() => {'removed': 3});
      expect(map.remove('removed'), 3);
      expect(map, {'retained': 2});
    });

    for (final key in <Object?>[null, 1, 'missing']) {
      test('removing $key does not coerce or match unrelated keys', () {
        final map = LazyStringKeyMap<int>(
          loader: () => {'null': 1, '1': 2, 'retained': 3},
        );
        expect(map.remove(key), isNull);
        expect(map, {'null': 1, '1': 2, 'retained': 3});
      });
    }

    test('loader can inspect or update explicit entries without recursion', () {
      var loads = 0;
      final map = LazyStringKeyMap<int>(initialValues: {'explicit': 1});
      map.attachLoader(() {
        loads++;
        expect(map['explicit'], 1);
        expect(map['absent'], isNull);
        map['written'] = 2;
        return {'written': 99, 'loaded': 3};
      });
      expect(map['loaded'], 3);
      expect(map, {'explicit': 1, 'written': 2, 'loaded': 3});
      expect(loads, 1);
    });

    test('loader failure propagates without erasing explicit metadata', () {
      final failure = StateError('synthetic loader failure');
      var loads = 0;
      final map = LazyStringKeyMap<int>(initialValues: {'explicit': 1});
      map.attachLoader(() {
        loads++;
        throw failure;
      });
      expect(() => map.remove('explicit'), throwsA(same(failure)));
      expect(map['explicit'], 1);
      expect(map.hasPendingLoader, isFalse);
      map.attachLoader(() => {'recovered': 2});
      expect(map['recovered'], 2);
      expect(map, {'explicit': 1, 'recovered': 2});
      expect(loads, 1);
    });

    test(
      'public container removal cannot resurrect lazily decoded metadata',
      () {
        final options = PublishOptions();
        options.setCustomField('removed', null);
        options.setLazyCustomFieldsLoader(
          () => {'removed': 'stale', 'retained': true},
        );
        options.removeCustomField('removed');
        expect(options.custom, {'retained': true});
        options.setCustomField('retained', false);
        expect(options.custom['retained'], isFalse);
      },
    );
  });

  group('lazy metadata explicit updates', () {
    for (final initial in <Object?>['explicit', null]) {
      test('removing $initial does not resurrect the loaded value', () {
        final map = lazyStringKeyMap<Object?>(
          initialValues: {'removed': initial},
          loader: () => {'removed': 'stale', 'remaining': 'loaded'},
        );
        expect(map.remove('removed'), initial);
        expect(map['remaining'], 'loaded');
        expect(map.containsKey('removed'), isFalse);
        expect(map, {'remaining': 'loaded'});
        expect(map.remove('removed'), isNull);
      });
    }

    for (final lazy in [false, true]) {
      for (final initial in <Object?>['explicit', null]) {
        test('loader preserves explicit $initial in lazy=$lazy map', () {
          final Map<String, Object?> map = lazy
              ? LazyStringKeyMap<Object?>(initialValues: {'value': initial})
              : <String, Object?>{'value': initial};
          attachLazyStringKeyMapLoader(
            map,
            () => {
              'value': 'stale',
              'additional': 'loaded',
            },
          );
          expect(map['additional'], 'loaded');
          expect(map['value'], initial);
          expect(map, {'value': initial, 'additional': 'loaded'});
        });
      }
    }

    for (final customFirst in [false, true]) {
      for (final initial in <Object?>['explicit', null]) {
        test(
          'Details preserves explicit $initial, customFirst=$customFirst',
          () {
            final details = Details();
            details.custom['value'] = initial;
            details.setLazyFieldsLoader(
              () => {
                'realm': 'consumer.realm',
                'value': 'stale',
                'additional': 'loaded',
              },
            );
            if (customFirst) {
              expect(details.custom['additional'], 'loaded');
            } else {
              expect(details.realm, 'consumer.realm');
            }
            expect(details.custom['value'], initial);
            expect(details.custom, {'value': initial, 'additional': 'loaded'});
            expect(details.realm, 'consumer.realm');
          },
        );
      }
    }
  });
}
