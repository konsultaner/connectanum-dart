import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

void main() {
  group('LazyStringKeyMap', () {
    test('loads unresolved entries only when accessed', () {
      var loadCount = 0;
      final map = lazyStringKeyMap<dynamic>(
        initialValues: {'eager': 'value'},
        loader: () {
          loadCount += 1;
          return {'lazy': 'loaded', 'eager': 'ignored'};
        },
      );

      expect(loadCount, 0);
      expect(map['eager'], 'value');
      expect(loadCount, 0);
      expect(map['lazy'], 'loaded');
      expect(loadCount, 1);
      expect(map['eager'], 'value');
    });

    test('explicit writes win over lazy loader values', () {
      var loadCount = 0;
      final options = PublishOptions(acknowledge: true);
      options.setCustomField('_trace', 'manual');
      options.setLazyCustomFieldsLoader(() {
        loadCount += 1;
        return {'_trace': 'lazy', '_span': 'ok'};
      });

      expect(loadCount, 0);
      expect(options.acknowledge, isTrue);
      expect(loadCount, 0);
      expect(options.custom['_trace'], 'manual');
      expect(options.custom['_span'], 'ok');
      expect(loadCount, 1);
    });

    test('details can lazily materialize auth extra maps', () {
      var loadCount = 0;
      final details = Details()..authid = 'bench-user';
      details.setLazyAuthExtraLoader(() {
        loadCount += 1;
        return {'nonce': 'abc123'};
      });

      expect(loadCount, 0);
      expect(details.authid, 'bench-user');
      expect(loadCount, 0);
      expect(details.authextra?['nonce'], 'abc123');
      expect(loadCount, 1);
    });

    test('details lazily materialize structured fields only on demand', () {
      var loadCount = 0;
      final details = Details()..authid = 'bench-user';
      details.setLazyFieldsLoader(() {
        loadCount += 1;
        return {
          'realm': 'bench.realm',
          'authmethods': ['ticket'],
          'authextra': {'nonce': 'abc123'},
          'roles': {
            'dealer': {
              'features': {'call_timeout': true},
            },
          },
          '_trace': 'native',
        };
      });

      expect(loadCount, 0);
      expect(details.authid, 'bench-user');
      expect(loadCount, 0);

      expect(details.realm, 'bench.realm');
      expect(loadCount, 1);
      expect(details.authmethods, ['ticket']);
      expect(details.authextra?['nonce'], 'abc123');
      expect(details.roles?.dealer?.features?.callTimeout, isTrue);
      expect(details.custom['_trace'], 'native');
      expect(loadCount, 1);
    });

    test('challenge extras lazily materialize auth fields on demand', () {
      var loadCount = 0;
      final extra = Extra()..nonce = 'abc123';
      extra.setLazyLoader(() {
        loadCount += 1;
        return {
          'challenge': 'signed-value',
          'salt': 'salt',
          'iterations': 4096,
          'channel_binding': 'tls-unique',
        };
      });

      expect(loadCount, 0);
      expect(extra.nonce, 'abc123');
      expect(loadCount, 0);
      expect(extra.challenge, 'signed-value');
      expect(extra.salt, 'salt');
      expect(extra.iterations, 4096);
      expect(extra.channelBinding, 'tls-unique');
      expect(loadCount, 1);
    });

    test('abort keeps lazy detail maps intact', () {
      var loadCount = 0;
      final abort = Abort(
        'wamp.error.abort',
        details: lazyStringKeyMap<Object?>(
          initialValues: {'message': 'boom'},
          loader: () {
            loadCount += 1;
            return {'_trace': 'native'};
          },
        ),
        message: 'boom',
      );

      expect(loadCount, 0);
      expect(abort.message?.message, 'boom');
      expect(loadCount, 0);
      expect(abort.details['_trace'], 'native');
      expect(loadCount, 1);
    });
  });
}
