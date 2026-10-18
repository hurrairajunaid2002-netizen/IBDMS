/// Web stub for dart:io types used only in UDP LAN discovery.
/// All call-sites are guarded by `if (kIsWeb) return …` so none of
/// these implementations are ever executed on the web platform.
library;

import 'dart:async';

class RawSocketEvent {
  static const RawSocketEvent read = RawSocketEvent._();
  const RawSocketEvent._();
}

class FakeAddress {
  final String address;
  const FakeAddress(this.address);
}

class Datagram {
  final List<int> data;
  final FakeAddress address;
  final int port;
  const Datagram(this.data, this.address, this.port);
}

class InternetAddress {
  final String address;
  const InternetAddress(this.address);
  static const InternetAddress anyIPv4 = InternetAddress('0.0.0.0');
}

class RawDatagramSocket extends Stream<RawSocketEvent> {
  bool broadcastEnabled = false;

  static Future<RawDatagramSocket> bind(
    dynamic address,
    int port, {
    bool reuseAddress = true,
    bool reusePort = false,
    int ttl = 1,
  }) async =>
      throw UnsupportedError('UDP sockets are not available on web.');

  Datagram? receive() => null;

  void close() {}

  @override
  StreamSubscription<RawSocketEvent> listen(
    void Function(RawSocketEvent event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      throw UnsupportedError('UDP sockets are not available on web.');
}
