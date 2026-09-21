@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:connectanum_router/src/router/http/http_context.dart';
import 'package:test/test.dart';

Map<String, Object?> _payload() => {
  'id': 73,
  'method': 'POST',
  'target': '/orders?tag=one&tag=two',
  'path': '/orders',
  'protocol': 'https',
  'version': 2,
  'headers': <String, String>{'X-Request': 'original'},
};

HttpRequestSnapshot _snapshot({
  Map<String, String> headers = const {},
  Map<String, List<String>>? headerValues,
  Uint8List? body,
  bool? copyBody,
}) {
  if (copyBody == null) {
    return HttpRequestSnapshot(
      id: 73,
      method: 'POST',
      target: '/orders',
      path: '/orders',
      protocol: 'https',
      version: 2,
      headers: headers,
      headerValues: headerValues,
      body: body,
    );
  }
  return HttpRequestSnapshot(
    id: 73,
    method: 'POST',
    target: '/orders',
    path: '/orders',
    protocol: 'https',
    version: 2,
    headers: headers,
    headerValues: headerValues,
    body: body,
    copyBody: copyBody,
  );
}

HttpRequestSnapshot? _parse(Map<String, Object?> payload) {
  HttpRequestSnapshot? result;
  expect(
    () => result = HttpRequestSnapshot.fromInvocationPayload(payload),
    returnsNormally,
  );
  return result;
}

void main() {
  for (final reversed in [false, true]) {
    test('mixed-case repeated headers retain every override: $reversed', () {
      final headers = <String, String>{
        'X-Trace': 'legacy-one',
        'x-trace': 'legacy-two',
        'Content-Type': 'application/json',
      };
      final values = <String, List<String>>{
        if (reversed) 'x-TRACE': ['second', 'third'],
        'X-Trace': ['first'],
        if (!reversed) 'x-TRACE': ['second', 'third'],
        'x-empty': [],
      };
      final snapshot = _snapshot(headers: headers, headerValues: values);
      final expected = <String, List<String>>{
        'x-trace': reversed
            ? ['second', 'third', 'first']
            : ['first', 'second', 'third'],
        'content-type': ['application/json'],
        'x-empty': [],
      };
      expect(snapshot.headerValues, expected);
      headers['Content-Type'] = 'changed';
      values['X-Trace']!.add('changed');
      values.clear();
      expect(snapshot.headerValues, expected);
      expect(snapshot.headers['Content-Type'], 'application/json');
      expect(() => snapshot.headerValues.clear(), throwsUnsupportedError);
      expect(
        () => snapshot.headerValues['x-trace']!.add('changed'),
        throwsUnsupportedError,
      );
      expect(() => snapshot.headers.clear(), throwsUnsupportedError);
    });
  }

  test('absent repeated headers preserve all case-insensitive values', () {
    final snapshot = _snapshot(
      headers: {
        'X-Trace': 'first',
        'x-trace': 'second',
        'x-TRACE': '',
      },
    );
    expect(snapshot.headerValues, {
      'x-trace': ['first', 'second', ''],
    });
  });

  for (final copyBody in <bool?>[null, true, false]) {
    test('body view ownership with copyBody=$copyBody', () {
      final parent = Uint8List.fromList([91, 11, 22, 33, 92]);
      final view = Uint8List.sublistView(parent, 1, 4);
      final snapshot = _snapshot(body: view, copyBody: copyBody);
      expect(snapshot.body, [11, 22, 33]);
      expect(identical(snapshot.body, view), copyBody == false);
      parent[2] = 44;
      expect(snapshot.body, copyBody == false ? [11, 44, 33] : [11, 22, 33]);
      snapshot.body![0] = 55;
      expect(
        parent,
        copyBody == false ? [91, 55, 44, 33, 92] : [91, 11, 44, 33, 92],
      );
      expect(identical(snapshot.body, snapshot.body), isTrue);
    });
  }

  for (final query in <String?>[null, '', 'tag=one&tag=two']) {
    for (final realm in <String?>[null, '', 'public.realm']) {
      for (final procedure in <String?>[null, '', 'com.orders.create']) {
        test('snapshot optional payload fields: $query/$realm/$procedure', () {
          final snapshot = HttpRequestSnapshot(
            id: 73,
            method: 'POST',
            target: '/orders?tag=one&tag=two',
            path: '/orders',
            protocol: 'https',
            version: 2,
            headers: {'X-Request': 'original'},
            query: query,
            realm: realm,
            procedure: procedure,
          );
          final expected = <String, Object?>{
            ..._payload(),
            'headerValues': {
              'x-request': ['original'],
            },
            if (query != null) 'query': query,
            if (realm != null) 'realm': realm,
            if (procedure != null) 'procedure': procedure,
          };
          expect(snapshot.toInvocationPayload(), expected);
          final decoded = _parse(expected)!;
          expect(decoded.id, 73);
          expect(decoded.method, 'POST');
          expect(decoded.target, '/orders?tag=one&tag=two');
          expect(decoded.path, '/orders');
          expect(decoded.protocol, 'https');
          expect(decoded.version, 2);
          expect(decoded.query, query);
          expect(decoded.realm, realm);
          expect(decoded.procedure, procedure);
          expect(decoded.body, isNull);
        });
      }
    }
  }

  final invalidHeaders = <Object?>[
    true,
    1,
    '',
    <Object?>[],
    <Object?, Object?>{
      1: <String>['value'],
    },
    <Object?, Object?>{
      null: <String>['value'],
    },
    <String, Object?>{'x': 'value'},
    <String, Object?>{'x': null},
    <String, Object?>{
      'x': {'nested': 'value'},
    },
    <String, Object?>{
      'x': <Object?>[null],
    },
    <String, Object?>{
      'x': <Object?>['valid', 7],
    },
    <String, Object?>{
      'x': <Object?>['valid', false],
    },
    <String, Object?>{
      'x': <Object?>['valid', <String>[]],
    },
  ];
  for (var index = 0; index < invalidHeaders.length; index++) {
    test('rejects malformed repeated header representation $index', () {
      expect(
        _parse({..._payload(), 'headerValues': invalidHeaders[index]}),
        isNull,
      );
    });
  }

  for (final values in <Map<String, List<String>>?>[
    null,
    {},
    {'x-request': []},
    {
      'X-Request': ['new'],
      'x-request': ['next'],
    },
  ]) {
    test('valid repeated header payload owns nested lists: $values', () {
      final snapshot = _parse({..._payload(), 'headerValues': values});
      expect(snapshot, isNotNull);
      final expected = values == null || values.isEmpty
          ? ['original']
          : values.length == 1
          ? <String>[]
          : ['new', 'next'];
      expect(snapshot!.headerValues, {'x-request': expected});
      values?.values.firstOrNull?.add('later');
      expect(snapshot.headerValues, {'x-request': expected});
    });
  }

  for (final body in <Object>[
    Uint8List.fromList([0, 128, 255]),
    <int>[0, 128, 255],
    Uint8List(0),
    <int>[],
  ]) {
    test('decoded binary body owns its bytes: ${body.runtimeType}/$body', () {
      final snapshot = _parse({..._payload(), 'body': body});
      expect(snapshot, isNotNull);
      final expected = (body as List<int>).isEmpty ? <int>[] : [0, 128, 255];
      expect(snapshot!.body, expected);
      expect(identical(snapshot.body, body), isFalse);
      if (body.isNotEmpty) body[0] = 42;
      expect(snapshot.body, expected);
      expect(snapshot.toInvocationPayload()['body'], expected);
    });
  }
}
