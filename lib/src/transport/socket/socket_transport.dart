import 'package:connectanum_dart/src/message/abstract_message.dart';

import '../abstract_transport.dart';

class SocketTransport extends AbstractTransport {

  bool _ssl;
  int _port;
  String _host;

  SocketTransport(String this._host, int this._port, bool this._ssl) {

  }

  @override
  Future<void> close() {
    // TODO: implement close
    return null;
  }

  @override
  bool isOpen() {
    // TODO: implement isOpen
    return null;
  }

  @override
  Future<void> open() {
    // TODO: implement open
    return null;
  }

  @override
  Stream<AbstractMessage> receive() {
    // TODO: implement receive
    return null;
  }

  @override
  void send(AbstractMessage message) {
    // TODO: implement send
  }
}