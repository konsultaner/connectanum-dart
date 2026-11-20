import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_client/src/transport/websocket/byte_frame_http_client_io.dart';
import 'package:test/test.dart';

void registerByteFrameHttpClientContractTests() {
  group('byte frame SDK boundary', () {
    test(
      'HTTP methods, URIs, headers and request bodies survive wrapping',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'method': request.method,
              'uri': request.uri.toString(),
              'body': body,
              'agent': request.headers.value(HttpHeaders.userAgentHeader),
              'header': request.headers.value('x-contract'),
              'cookie': request.cookies.single.value,
            }),
          );
          await request.response.close();
        });
        final client = canonicalJsonByteFrameClient(HttpClient());
        client.userAgent = 'adapter-contract';
        final host = '127.0.0.1', port = server.port, path = '/echo?value=one';
        final uri = Uri.parse('http://$host:$port$path');
        final requests = <(String, Future<HttpClientRequest> Function())>[
          ('OPTIONS', () => client.open('OPTIONS', host, port, path)),
          ('OPTIONS', () => client.openUrl('OPTIONS', uri)),
          ('GET', () => client.get(host, port, path)),
          ('GET', () => client.getUrl(uri)),
          ('POST', () => client.post(host, port, path)),
          ('POST', () => client.postUrl(uri)),
          ('PUT', () => client.put(host, port, path)),
          ('PUT', () => client.putUrl(uri)),
          ('DELETE', () => client.delete(host, port, path)),
          ('DELETE', () => client.deleteUrl(uri)),
          ('PATCH', () => client.patch(host, port, path)),
          ('PATCH', () => client.patchUrl(uri)),
          ('HEAD', () => client.head(host, port, path)),
          ('HEAD', () => client.headUrl(uri)),
        ];
        try {
          for (final (method, open) in requests) {
            final request = await open();
            expect(request.method, method);
            expect(request.uri, uri);
            request.headers.set('x-contract', 'unchanged');
            request.cookies.add(Cookie('session', 'contract-cookie'));
            request.contentLength = 4;
            request.write('body');
            final response = await request.close();
            expect(response.statusCode, HttpStatus.ok);
            final bytes = await response.fold<List<int>>(
              [],
              (all, part) => all..addAll(part),
            );
            if (method == 'HEAD') {
              expect(bytes, isEmpty);
            } else {
              expect(jsonDecode(utf8.decode(bytes)), {
                'method': method,
                'uri': path,
                'body': 'body',
                'agent': 'adapter-contract',
                'header': 'unchanged',
                'cookie': 'contract-cookie',
              });
            }
          }
        } finally {
          client.close(force: true);
          await server.close(force: true);
        }
      },
    );

    test(
      'client configuration and security callbacks keep their SDK contract',
      () async {
        final fixture = _BoundaryFixture();
        final client = fixture.client, calls = fixture.rawClient.calls;
        addTearDown(fixture.dispose);
        client.idleTimeout = const Duration(seconds: 9);
        client.connectionTimeout = const Duration(seconds: 4);
        client.maxConnectionsPerHost = 3;
        client.autoUncompress = false;
        client.userAgent = 'configured';
        expect(calls.values['idleTimeout'], const Duration(seconds: 9));
        expect(calls.values['connectionTimeout'], const Duration(seconds: 4));
        expect(calls.values['maxConnectionsPerHost'], 3);
        expect(calls.values['autoUncompress'], isFalse);
        expect(calls.values['userAgent'], 'configured');
        calls.values.addAll({
          'idleTimeout': const Duration(seconds: 12),
          'connectionTimeout': null,
          'maxConnectionsPerHost': null,
          'autoUncompress': true,
          'userAgent': null,
        });
        expect(client.idleTimeout, const Duration(seconds: 12));
        expect(client.connectionTimeout, isNull);
        expect(client.maxConnectionsPerHost, isNull);
        expect(client.autoUncompress, isTrue);
        expect(client.userAgent, isNull);

        final url = Uri.https('example.invalid', '/secure');
        final observed = <Object?>[];
        client.authenticate = (url, scheme, realm) async {
          observed.addAll([url, scheme, realm]);
          return true;
        };
        expect(
          await Function.apply(calls.values['authenticate'] as Function, [
            url,
            'Basic',
            'realm',
          ]),
          isTrue,
        );
        expect(observed, [url, 'Basic', 'realm']);
        client.authenticateProxy = (host, port, scheme, realm) async =>
            host == 'proxy' &&
            port == 8080 &&
            scheme == 'Basic' &&
            realm == null;
        expect(
          await Function.apply(calls.values['authenticateProxy'] as Function, [
            'proxy',
            8080,
            'Basic',
            null,
          ]),
          isTrue,
        );
        client.findProxy = (value) =>
            value == url ? 'DIRECT' : 'PROXY proxy:8080';
        expect(
          Function.apply(calls.values['findProxy'] as Function, [url]),
          'DIRECT',
        );
        var cancellations = 0;
        final task = ConnectionTask.fromSocket<Socket>(
          Future.value(fixture.socket),
          () => cancellations++,
        );
        client.connectionFactory = (value, host, port) async {
          expect([value, host, port], [url, 'proxy', 8080]);
          return task;
        };
        expect(
          await Function.apply(calls.values['connectionFactory'] as Function, [
            url,
            'proxy',
            8080,
          ]),
          same(task),
        );
        expect(await task.socket, same(fixture.socket));
        task.cancel();
        expect(cancellations, 1);
        final certificate = _CertificateFake();
        client.badCertificateCallback = (cert, host, port) =>
            identical(cert, certificate) &&
            host == 'example.invalid' &&
            port == 443;
        expect(
          Function.apply(calls.values['badCertificateCallback'] as Function, [
            certificate,
            'example.invalid',
            443,
          ]),
          isTrue,
        );
        final keyLines = <String>[];
        client.keyLog = keyLines.add;
        Function.apply(calls.values['keyLog'] as Function, ['test-key-log']);
        expect(keyLines, ['test-key-log']);
        final credentials = HttpClientBasicCredentials(
          'fixture',
          'fixture-password',
        );
        client.addCredentials(url, 'realm', credentials);
        calls.expectLast(#addCredentials, [url, 'realm', credentials]);
        client.addProxyCredentials('proxy', 8080, 'realm', credentials);
        calls.expectLast(#addProxyCredentials, [
          'proxy',
          8080,
          'realm',
          credentials,
        ]);
        client.authenticate = null;
        client.authenticateProxy = null;
        client.findProxy = null;
        client.connectionFactory = null;
        client.badCertificateCallback = null;
        client.keyLog = null;
        for (final name in [
          'authenticate',
          'authenticateProxy',
          'findProxy',
          'connectionFactory',
          'badCertificateCallback',
          'keyLog',
        ]) {
          expect(calls.values[name], isNull);
        }
        client.close();
        calls.expectLast(#close, [], named: {#force: false});
        client.close(force: true);
        calls.expectLast(#close, [], named: {#force: true});
      },
    );

    test(
      'request settings, body encoding and completion remain observable',
      () async {
        final fixture = _BoundaryFixture();
        addTearDown(fixture.dispose);
        final request = await fixture.client.getUrl(_BoundaryFixture.url);
        final raw = fixture.request;
        request.persistentConnection = false;
        request.followRedirects = false;
        request.maxRedirects = 2;
        request.contentLength = 17;
        request.bufferOutput = false;
        expect(raw.calls.values, containsPair('persistentConnection', false));
        expect(raw.calls.values, containsPair('followRedirects', false));
        expect(raw.calls.values, containsPair('maxRedirects', 2));
        expect(raw.calls.values, containsPair('contentLength', 17));
        expect(raw.calls.values, containsPair('bufferOutput', false));
        expect(request.persistentConnection, isFalse);
        expect(request.followRedirects, isFalse);
        expect(request.maxRedirects, 2);
        expect(request.contentLength, 17);
        expect(request.bufferOutput, isFalse);
        expect(request.headers, same(raw.headers));
        request.cookies.add(Cookie('request', 'cookie'));
        expect(raw.cookies.single.value, 'cookie');
        expect(request.connectionInfo, same(fixture.info));
        request.encoding = latin1;
        expect(request.encoding, same(latin1));
        request.write('café');
        request.writeAll([1, 2], '/');
        request.writeln('!');
        request.writeCharCode(65);
        request.add([0, 255]);
        await request.addStream(Stream.value([3, 4]));
        final error = StateError('body event');
        final stack = StackTrace.current;
        request.addError(error, stack);
        await request.flush();
        final done = request.done;
        final response = await request.close();
        expect((await done).statusCode, response.statusCode);
        expect(raw.output.bytes, [
          ...latin1.encode('café1/2!\nA'),
          0,
          255,
          3,
          4,
        ]);
        expect(raw.output.errors.single.$1, same(error));
        expect(raw.output.errors.single.$2, same(stack));
      },
    );

    test('request abort preserves its exception and stack arguments', () async {
      final fixture = _BoundaryFixture();
      addTearDown(fixture.dispose);
      final request = await fixture.client.getUrl(_BoundaryFixture.url);
      final error = StateError('cancelled upgrade'), stack = StackTrace.current;
      request.abort(error, stack);
      fixture.request.calls.expectLast(#abort, [error, stack]);
      request.abort();
      fixture.request.calls.expectLast(#abort, [null, null]);
    });

    test(
      'response metadata, stream and redirected socket preserve identity',
      () async {
        final fixture = _BoundaryFixture();
        addTearDown(fixture.dispose);
        final response = await (await fixture.client.getUrl(
          _BoundaryFixture.url,
        )).close();
        expect(response.statusCode, 101);
        expect(response.reasonPhrase, 'Switching Protocols');
        expect(response.contentLength, 2);
        expect(
          response.compressionState,
          HttpClientResponseCompressionState.notCompressed,
        );
        expect(response.persistentConnection, isTrue);
        expect(response.isRedirect, isFalse);
        expect(response.redirects, same(fixture.response.redirects));
        expect(response.headers, same(fixture.response.headers));
        expect(response.cookies, same(fixture.response.cookies));
        expect(response.certificate, same(fixture.certificate));
        expect(response.connectionInfo, same(fixture.info));
        expect(await response.toList(), [
          [7, 8],
        ]);
        final url = Uri.https('example.invalid', '/redirected');
        final redirected = await response.redirect('POST', url, true);
        fixture.response.calls.expectLast(#redirect, ['POST', url, true]);
        expect(redirected.statusCode, 101);
        await response.redirect();
        fixture.response.calls.expectLast(#redirect, [null, null, null]);
        expect(fixture.kinds.active, isFalse);
        final socket = await redirected.detachSocket();
        expect(fixture.kinds.active, isTrue);
        expect(socket, isNot(same(fixture.socket)));
        expect((await socket.toList()).expand((part) => part), [130, 2, 3, 4]);
      },
    );

    test(
      'negotiated compression keeps the detached SDK socket unchanged',
      () async {
        final fixture = _BoundaryFixture(extensions: ['permessage-deflate']);
        addTearDown(fixture.dispose);
        final response = await (await fixture.client.getUrl(
          _BoundaryFixture.url,
        )).close();
        expect(await response.detachSocket(), same(fixture.socket));
        expect(fixture.kinds.active, isFalse);
      },
    );

    test(
      'detached socket retains options, endpoints and sink lifecycle',
      () async {
        final fixture = _BoundaryFixture();
        addTearDown(fixture.dispose);
        final response = await (await fixture.client.getUrl(
          _BoundaryFixture.url,
        )).close();
        final socket = await response.detachSocket();
        expect(socket.port, 1234);
        expect(socket.remotePort, 4321);
        expect(socket.address, InternetAddress.loopbackIPv4);
        expect(socket.remoteAddress, InternetAddress.loopbackIPv4);
        expect(socket.setOption(SocketOption.tcpNoDelay, false), isTrue);
        fixture.socket.calls.expectLast(#setOption, [
          SocketOption.tcpNoDelay,
          false,
        ]);
        final option = RawSocketOption(1, 2, Uint8List.fromList([1, 0, 0, 0]));
        socket.setRawOption(option);
        fixture.socket.calls.expectLast(#setRawOption, [option]);
        expect(socket.getRawOption(option), same(fixture.socket.rawOption));
        fixture.socket.calls.expectLast(#getRawOption, [option]);
        socket.encoding = latin1;
        expect(socket.encoding, same(latin1));
        socket.add([0, 255]);
        socket.write('café');
        socket.writeAll([1, 2], '/');
        socket.writeln('!');
        socket.writeCharCode(65);
        await socket.addStream(Stream.value([3, 4]));
        final error = StateError('socket event'), stack = StackTrace.current;
        socket.addError(error, stack);
        await socket.flush();
        final done = socket.done;
        await socket.close();
        await done;
        expect(fixture.socket.output.bytes, [
          0,
          255,
          ...latin1.encode('café1/2!\nA'),
          3,
          4,
        ]);
        expect(fixture.socket.output.errors.single.$1, same(error));
        expect(fixture.socket.output.errors.single.$2, same(stack));
        socket.destroy();
        fixture.socket.calls.expectLast(#destroy, []);
      },
    );
  });
}

class _Calls {
  final values = <String, Object?>{};
  final handlers = <Symbol, Object? Function(Invocation)>{};
  final invocations = <Invocation>[];

  void property(String name, Object? value) {
    values[name] = value;
    handlers[Symbol(name)] = (_) => values[name];
    handlers[Symbol('$name=')] = (call) =>
        values[name] = call.positionalArguments.single;
  }

  void getter(Symbol name, Object? Function() get) =>
      handlers[name] = (_) => get();

  void sink(_ByteOutput output) {
    getter(#encoding, () => output.sink.encoding);
    handlers[const Symbol('encoding=')] = (call) {
      output.sink.encoding = call.positionalArguments.single as Encoding;
      return null;
    };
    getter(#done, () => output.sink.done);
    final methods = <Symbol, Function>{
      #add: output.sink.add,
      #write: output.sink.write,
      #writeAll: output.sink.writeAll,
      #writeln: output.sink.writeln,
      #writeCharCode: output.sink.writeCharCode,
      #addError: output.sink.addError,
      #addStream: output.sink.addStream,
      #flush: output.sink.flush,
      #close: output.finish,
    };
    for (final entry in methods.entries) {
      handlers[entry.key] = (call) => Function.apply(
        entry.value,
        call.positionalArguments,
        call.namedArguments,
      );
    }
  }

  Object? invoke(Invocation call) {
    invocations.add(call);
    final handler = handlers[call.memberName];
    if (handler == null) {
      throw StateError('Unexpected SDK call ${call.memberName}');
    }
    return handler(call);
  }

  void expectLast(
    Symbol name,
    List<Object?> args, {
    Map<Symbol, Object?> named = const {},
  }) {
    final call = invocations.last;
    expect(call.memberName, name);
    expect(call.positionalArguments, args);
    expect(call.namedArguments, named);
  }
}

class _ByteOutput implements StreamConsumer<List<int>> {
  final bytes = <int>[];
  final errors = <(Object, StackTrace)>[];
  late final sink = IOSink(this);
  Future<void>? _closing;

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    final done = Completer<void>();
    stream.listen(
      bytes.addAll,
      onError: (Object error, StackTrace stack) {
        errors.add((error, stack));
      },
      onDone: done.complete,
    );
    return done.future;
  }

  @override
  Future<void> close() async {}

  Future<void> finish() => _closing ??= sink.close().then((_) {});
}

class _ClientFake implements HttpClient {
  _ClientFake(HttpClientRequest request) {
    calls.property('idleTimeout', const Duration(seconds: 15));
    calls.property('connectionTimeout', null);
    calls.property('maxConnectionsPerHost', null);
    calls.property('autoUncompress', true);
    calls.property('userAgent', null);
    for (final name in [
      'authenticate',
      'authenticateProxy',
      'findProxy',
      'connectionFactory',
      'badCertificateCallback',
      'keyLog',
    ]) {
      calls.property(name, null);
    }
    calls.handlers[#getUrl] = (_) => Future<HttpClientRequest>.value(request);
    for (final name in [#addCredentials, #addProxyCredentials, #close]) {
      calls.handlers[name] = (_) => null;
    }
  }
  final calls = _Calls();
  @override
  dynamic noSuchMethod(Invocation invocation) => calls.invoke(invocation);
}

class _RequestFake implements HttpClientRequest {
  _RequestFake(HttpClientResponse response, HttpConnectionInfo info) {
    calls.sink(output);
    calls.property('persistentConnection', true);
    calls.property('followRedirects', true);
    calls.property('maxRedirects', 5);
    calls.property('contentLength', -1);
    calls.property('bufferOutput', true);
    calls.getter(#headers, () => headers);
    calls.getter(#cookies, () => cookies);
    calls.getter(#connectionInfo, () => info);
    calls.getter(
      #done,
      () => output.sink.done.then<HttpClientResponse>((_) => response),
    );
    calls.handlers[#close] = (_) =>
        output.finish().then<HttpClientResponse>((_) => response);
    calls.handlers[#abort] = (_) => null;
  }
  final calls = _Calls(), output = _ByteOutput();
  @override
  final headers = _HeadersFake();
  @override
  final cookies = <Cookie>[];
  @override
  dynamic noSuchMethod(Invocation invocation) => calls.invoke(invocation);
}

class _ResponseFake extends StreamView<List<int>>
    implements HttpClientResponse {
  _ResponseFake(
    this.socket,
    this.connectionInfo,
    this.certificate,
    List<String>? extensions,
  ) : headers = _HeadersFake(extensions),
      super(Stream.value([7, 8])) {
    calls.handlers[#redirect] = (_) => Future<HttpClientResponse>.value(this);
    calls.handlers[#detachSocket] = (_) => Future<Socket>.value(socket);
  }
  final _SocketFake socket;
  final calls = _Calls();
  @override
  final HttpConnectionInfo connectionInfo;
  @override
  final X509Certificate certificate;
  @override
  final HttpHeaders headers;
  @override
  int get statusCode => 101;
  @override
  String get reasonPhrase => 'Switching Protocols';
  @override
  int get contentLength => 2;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  bool get persistentConnection => true;
  @override
  bool get isRedirect => false;
  @override
  final redirects = <RedirectInfo>[];
  @override
  final cookies = <Cookie>[Cookie('response', 'cookie')];
  @override
  dynamic noSuchMethod(Invocation invocation) => calls.invoke(invocation);
}

class _SocketFake extends StreamView<Uint8List> implements Socket {
  _SocketFake() : super(Stream.value(Uint8List.fromList([130, 2, 3, 4]))) {
    calls.sink(output);
    calls.getter(#port, () => 1234);
    calls.getter(#remotePort, () => 4321);
    calls.getter(#address, () => InternetAddress.loopbackIPv4);
    calls.getter(#remoteAddress, () => InternetAddress.loopbackIPv4);
    calls.handlers[#setOption] = (_) => true;
    calls.handlers[#setRawOption] = (_) => null;
    calls.handlers[#getRawOption] = (_) => rawOption;
    calls.handlers[#destroy] = (_) => null;
  }
  final calls = _Calls(), output = _ByteOutput();
  final rawOption = Uint8List.fromList([8, 7]);
  @override
  dynamic noSuchMethod(Invocation invocation) => calls.invoke(invocation);
}

class _BoundaryFixture {
  _BoundaryFixture({List<String>? extensions}) {
    response = _ResponseFake(socket, info, certificate, extensions);
    request = _RequestFake(response, info);
    rawClient = _ClientFake(request);
    client = canonicalJsonByteFrameClient(rawClient, kinds: kinds);
  }
  static final url = Uri.https('example.invalid', '/upgrade');
  final info = _ConnectionInfoFake(), certificate = _CertificateFake();
  final socket = _SocketFake();
  final kinds = CanonicalJsonFrameKinds(adaptJson: false);
  late final _ResponseFake response;
  late final _RequestFake request;
  late final _ClientFake rawClient;
  late final HttpClient client;
  Future<void> dispose() async {
    await request.output.finish();
    await socket.output.finish();
  }
}

class _HeadersFake implements HttpHeaders {
  _HeadersFake([this.extensions]);
  final List<String>? extensions;
  @override
  List<String>? operator [](String name) =>
      name.toLowerCase() == 'sec-websocket-extensions' ? extensions : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CertificateFake implements X509Certificate {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ConnectionInfoFake implements HttpConnectionInfo {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
