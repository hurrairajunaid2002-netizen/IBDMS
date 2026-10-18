import 'dart:async';

// dart:io is not available on web; the stub provides the same type names so

// the file compiles on all platforms. All dart:io call-sites are already

// guarded by `if (kIsWeb) return …` so the stub is never executed.

import 'dart:io' if (dart.library.html) 'src/io_stub.dart';

import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:http/http.dart' as http;



/// Network layer — Ngrok (remote) or LAN discovery (local device testing).

class ApiConfig {

  ApiConfig._();



  /// Permanent Ngrok tunnel (matches ibdms_backend/.env NGROK_BASE_URL).

  static const String ngrokBaseUrl =

      'https://blah-curve-boxer.ngrok-free.dev';



  /// When true, all platforms use [ngrokBaseUrl]. Set false for LAN-only dev.

  static const bool useNgrok = true;



  static const int _apiPort = 5000;

  static const int _discoveryPort = 5001;



  static String _serverIp = '192.168.1.35';

  static bool _discovering = false;



  static final ValueNotifier<String> serverIpNotifier =

      ValueNotifier('192.168.1.35');



  static Future<void> initialize() async {

    if (kIsWeb || useNgrok) return;



    final prefs = await SharedPreferences.getInstance();

    final stored = prefs.getString('server_ip');

    if (stored != null && stored.isNotEmpty) {

      _serverIp = stored;

      serverIpNotifier.value = stored;

    }

    unawaited(_backgroundDiscover());

  }



  /// True when Flutter web is served from localhost (e.g. port 8080).
  static bool get _isLocalWebHost {
    if (!kIsWeb) return false;
    final host = Uri.base.host.toLowerCase();
    if (host.isEmpty) return true;
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '[::1]';
  }

  static String get baseUrl {
    // Flutter web dev always talks to the local FastAPI + MySQL stack.
    // Using Ngrok from the browser causes CORS preflight passes but GET
    // requests never complete (OPTIONS-only in server logs).
    if (kIsWeb && (kDebugMode || _isLocalWebHost)) {
      return 'http://127.0.0.1:$_apiPort';
    }
    if (useNgrok) return ngrokBaseUrl;
    if (kIsWeb) return ngrokBaseUrl;
    return 'http://$_serverIp:$_apiPort';
  }



  static String get currentServerIp => _serverIp;

  static bool get isDiscovering => _discovering;



  static Map<String, String> get jsonHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (baseUrl.contains('ngrok')) 'ngrok-skip-browser-warning': '69420',
      };

  static Map<String, String> authHeaders(String token) => {
        ...jsonHeaders,
        'Authorization': 'Bearer ${token.trim()}',
      };



  static String get wsUrl {

    final http = baseUrl;

    if (http.startsWith('https://')) {

      return '${http.replaceFirst('https://', 'wss://')}/ws/alerts';

    }

    return '${http.replaceFirst('http://', 'ws://')}/ws/alerts';

  }



  static Future<void> setServerIp(String ip) async {

    final trimmed = ip.trim();

    if (trimmed.isEmpty) return;

    _serverIp = trimmed;

    serverIpNotifier.value = trimmed;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('server_ip', trimmed);

  }



  static Future<String?> rescan() async {

    if (useNgrok) return null;

    final found = await _udpListen();

    if (found != null) await setServerIp(found);

    return found;

  }



  static Future<void> _backgroundDiscover() async {

    if (kIsWeb || useNgrok) return;

    _discovering = true;

    serverIpNotifier.value = _serverIp;



    final found = await _udpListen();

    _discovering = false;



    if (found != null) {

      await setServerIp(found);

    } else {

      serverIpNotifier.value = _serverIp;

    }

  }



  static Future<String?> _udpListen({int timeoutSeconds = 7}) async {

    if (kIsWeb || useNgrok) return null;

    RawDatagramSocket? sock;

    try {

      sock = await RawDatagramSocket.bind(

        InternetAddress.anyIPv4,

        _discoveryPort,

        reuseAddress: true,

        reusePort: false,

      ).timeout(const Duration(seconds: 3));



      sock.broadcastEnabled = true;



      final completer = Completer<String?>();



      sock.listen(

        (event) {

          if (event == RawSocketEvent.read) {

            final dg = sock?.receive();

            if (dg != null) {

              final msg = String.fromCharCodes(dg.data).trim();

              if (msg.startsWith('IBDMS_SERVER') &&

                  !completer.isCompleted) {

                completer.complete(dg.address.address);

              }

            }

          }

        },

        onError: (_) {

          if (!completer.isCompleted) completer.complete(null);

        },

        cancelOnError: true,

      );



      final result = await completer.future.timeout(

        Duration(seconds: timeoutSeconds),

        onTimeout: () => null,

      );



      try {

        sock.close();

      } catch (_) {}

      return result;

    } catch (_) {

      try {

        sock?.close();

      } catch (_) {}

      return null;

    }

  }



  static Future<bool> isServerReachable([String? ip]) async {
    try {
      final url = ip != null ? 'http://$ip:$_apiPort/' : '$baseUrl/';
      final res = await http
          .get(Uri.parse(url), headers: jsonHeaders)
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

}


