import 'package:connectanum/authentication.dart' as auth;
import 'package:connectanum/cbor.dart' as cbor;
import 'package:connectanum/connectanum.dart' as connectanum;
import 'package:connectanum/json.dart' as json;
import 'package:connectanum/logging.dart' as logging;
import 'package:connectanum/mcp.dart' as mcp;
import 'package:connectanum/msgpack.dart' as msgpack;
import 'package:connectanum/socket.dart' as socket;
import 'package:test/test.dart';

T? _typeToken<T>() => null;

void main() {
  test('compatibility facade exports client entrypoints', () {
    expect(_typeToken<connectanum.Client>(), isNull);
    expect(_typeToken<connectanum.Session>(), isNull);
    expect(_typeToken<connectanum.WebSocketTransport>(), isNull);
    expect(_typeToken<auth.TicketAuthentication>(), isNull);
    expect(_typeToken<auth.CraAuthentication>(), isNull);
    expect(_typeToken<json.Serializer>(), isNull);
    expect(_typeToken<msgpack.Serializer>(), isNull);
    expect(_typeToken<cbor.Serializer>(), isNull);
    expect(_typeToken<socket.SocketTransport>(), isNull);
    expect(_typeToken<mcp.McpStreamableHttpClient>(), isNull);
    expect(logging.Level.INFO.name, 'INFO');
  });
}
