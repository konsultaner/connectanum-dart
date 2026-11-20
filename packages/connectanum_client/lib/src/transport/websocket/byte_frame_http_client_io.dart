import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'canonical_json_byte_frames_io.dart';

class CanonicalJsonFrameKinds {
  bool active = false;
  final _kinds = Queue<bool>();
  void add(bool text) => _kinds.addLast(text);
  bool? take() => _kinds.isEmpty ? null : _kinds.removeFirst();
  void clear() => _kinds.clear();
}

HttpClient canonicalJsonByteFrameClient(
  HttpClient delegate, {
  CanonicalJsonFrameKinds? kinds,
}) => _Client(delegate, kinds ?? CanonicalJsonFrameKinds());

class _Client implements HttpClient {
  final HttpClient delegate;
  final CanonicalJsonFrameKinds kinds;
  _Client(this.delegate, this.kinds);
  @override
  Duration get idleTimeout => delegate.idleTimeout;
  @override
  set idleTimeout(Duration value) {
    delegate.idleTimeout = value;
  }

  @override
  Duration? get connectionTimeout => delegate.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) {
    delegate.connectionTimeout = value;
  }

  @override
  int? get maxConnectionsPerHost => delegate.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? value) {
    delegate.maxConnectionsPerHost = value;
  }

  @override
  bool get autoUncompress => delegate.autoUncompress;
  @override
  set autoUncompress(bool value) {
    delegate.autoUncompress = value;
  }

  @override
  String? get userAgent => delegate.userAgent;
  @override
  set userAgent(String? value) {
    delegate.userAgent = value;
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => delegate
      .open(method, host, port, path)
      .then((request) => _Request(request, kinds));
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      delegate.openUrl(method, url).then((request) => _Request(request, kinds));
  @override
  Future<HttpClientRequest> get(String host, int port, String path) => delegate
      .get(host, port, path)
      .then((request) => _Request(request, kinds));
  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      delegate.getUrl(url).then((request) => _Request(request, kinds));
  @override
  Future<HttpClientRequest> post(String host, int port, String path) => delegate
      .post(host, port, path)
      .then((request) => _Request(request, kinds));
  @override
  Future<HttpClientRequest> postUrl(Uri url) =>
      delegate.postUrl(url).then((request) => _Request(request, kinds));
  @override
  Future<HttpClientRequest> put(String host, int port, String path) => delegate
      .put(host, port, path)
      .then((request) => _Request(request, kinds));
  @override
  Future<HttpClientRequest> putUrl(Uri url) =>
      delegate.putUrl(url).then((request) => _Request(request, kinds));
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      delegate
          .delete(host, port, path)
          .then((request) => _Request(request, kinds));
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) =>
      delegate.deleteUrl(url).then((request) => _Request(request, kinds));
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      delegate
          .patch(host, port, path)
          .then((request) => _Request(request, kinds));
  @override
  Future<HttpClientRequest> patchUrl(Uri url) =>
      delegate.patchUrl(url).then((request) => _Request(request, kinds));
  @override
  Future<HttpClientRequest> head(String host, int port, String path) => delegate
      .head(host, port, path)
      .then((request) => _Request(request, kinds));
  @override
  Future<HttpClientRequest> headUrl(Uri url) =>
      delegate.headUrl(url).then((request) => _Request(request, kinds));
  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) => delegate.authenticate = f;
  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) => delegate.addCredentials(url, realm, credentials);
  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )?
    f,
  ) => delegate.connectionFactory = f;
  @override
  set findProxy(String Function(Uri url)? f) => delegate.findProxy = f;
  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
    f,
  ) => delegate.authenticateProxy = f;
  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) => delegate.addProxyCredentials(host, port, realm, credentials);
  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) => delegate.badCertificateCallback = callback;
  @override
  set keyLog(Function(String line)? callback) => delegate.keyLog = callback;
  @override
  void close({bool force = false}) => delegate.close(force: force);
}

class _Request implements HttpClientRequest {
  final HttpClientRequest delegate;
  final CanonicalJsonFrameKinds kinds;
  _Request(this.delegate, this.kinds);
  @override
  bool get persistentConnection => delegate.persistentConnection;
  @override
  set persistentConnection(bool value) {
    delegate.persistentConnection = value;
  }

  @override
  bool get followRedirects => delegate.followRedirects;
  @override
  set followRedirects(bool value) {
    delegate.followRedirects = value;
  }

  @override
  int get maxRedirects => delegate.maxRedirects;
  @override
  set maxRedirects(int value) {
    delegate.maxRedirects = value;
  }

  @override
  String get method => delegate.method;
  @override
  Uri get uri => delegate.uri;
  @override
  int get contentLength => delegate.contentLength;
  @override
  set contentLength(int value) {
    delegate.contentLength = value;
  }

  @override
  bool get bufferOutput => delegate.bufferOutput;
  @override
  set bufferOutput(bool value) {
    delegate.bufferOutput = value;
  }

  @override
  HttpHeaders get headers => delegate.headers;
  @override
  List<Cookie> get cookies => delegate.cookies;
  @override
  Future<HttpClientResponse> get done =>
      delegate.done.then((response) => _Response(response, kinds));
  @override
  Future<HttpClientResponse> close() =>
      delegate.close().then((response) => _Response(response, kinds));
  @override
  HttpConnectionInfo? get connectionInfo => delegate.connectionInfo;
  @override
  void abort([Object? exception, StackTrace? stackTrace]) =>
      delegate.abort(exception, stackTrace);
  @override
  Encoding get encoding => delegate.encoding;
  @override
  set encoding(Encoding value) {
    delegate.encoding = value;
  }

  @override
  void add(List<int> data) => delegate.add(data);
  @override
  void write(Object? object) => delegate.write(object);
  @override
  void writeAll(Iterable objects, [String separator = ""]) =>
      delegate.writeAll(objects, separator);
  @override
  void writeln([Object? object = ""]) => delegate.writeln(object);
  @override
  void writeCharCode(int charCode) => delegate.writeCharCode(charCode);
  @override
  void addError(error, [StackTrace? stackTrace]) =>
      delegate.addError(error, stackTrace);
  @override
  Future addStream(Stream<List<int>> stream) => delegate.addStream(stream);
  @override
  Future flush() => delegate.flush();
}

class _Response extends StreamView<List<int>> implements HttpClientResponse {
  final HttpClientResponse delegate;
  final CanonicalJsonFrameKinds kinds;
  _Response(this.delegate, this.kinds) : super(delegate);
  @override
  int get statusCode => delegate.statusCode;
  @override
  String get reasonPhrase => delegate.reasonPhrase;
  @override
  int get contentLength => delegate.contentLength;
  @override
  HttpClientResponseCompressionState get compressionState =>
      delegate.compressionState;
  @override
  bool get persistentConnection => delegate.persistentConnection;
  @override
  bool get isRedirect => delegate.isRedirect;
  @override
  List<RedirectInfo> get redirects => delegate.redirects;
  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) => delegate
      .redirect(method, url, followLoops)
      .then((response) => _Response(response, kinds));
  @override
  HttpHeaders get headers => delegate.headers;
  @override
  Future<Socket> detachSocket() async {
    final socket = await delegate.detachSocket();
    if (delegate.headers['sec-websocket-extensions'] != null) return socket;
    kinds.active = true;
    return _Socket(socket, kinds);
  }

  @override
  List<Cookie> get cookies => delegate.cookies;
  @override
  X509Certificate? get certificate => delegate.certificate;
  @override
  HttpConnectionInfo? get connectionInfo => delegate.connectionInfo;
}

class _Socket extends StreamView<Uint8List> implements Socket {
  final Socket delegate;
  final CanonicalJsonFrameKinds kinds;
  _Socket(this.delegate, this.kinds)
    : super(canonicalJsonByteFrames(delegate, onMessage: kinds.add));
  @override
  void destroy() => delegate.destroy();
  @override
  bool setOption(SocketOption option, bool enabled) =>
      delegate.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) =>
      delegate.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => delegate.setRawOption(option);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      delegate.addError(error, stackTrace);
  @override
  int get port => delegate.port;
  @override
  int get remotePort => delegate.remotePort;
  @override
  InternetAddress get address => delegate.address;
  @override
  InternetAddress get remoteAddress => delegate.remoteAddress;
  @override
  Future close() => delegate.close();
  @override
  Future get done => delegate.done;
  @override
  Encoding get encoding => delegate.encoding;
  @override
  set encoding(Encoding value) {
    delegate.encoding = value;
  }

  @override
  void add(List<int> data) => delegate.add(data);
  @override
  void write(Object? object) => delegate.write(object);
  @override
  void writeAll(Iterable objects, [String separator = ""]) =>
      delegate.writeAll(objects, separator);
  @override
  void writeln([Object? object = ""]) => delegate.writeln(object);
  @override
  void writeCharCode(int charCode) => delegate.writeCharCode(charCode);
  @override
  Future addStream(Stream<List<int>> stream) => delegate.addStream(stream);
  @override
  Future flush() => delegate.flush();
}
