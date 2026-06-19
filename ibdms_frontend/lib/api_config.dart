import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// Zero-config dynamic network layer.
///
/// Discovery order on every app start:
///   1. Load last-known IP from SharedPreferences (instant, no UI delay).
///   2. Send UDP listen on port 5001 — the backend broadcasts
///      "IBDMS_SERVER:5000" every 3 s from wherever it is running.
///   3. When a broadcast is heard, the sender's IP is saved and
///      [serverIpNotifier] fires so the UI updates itself automatically.
///
/// Result: the app works on ANY Wi-Fi network with zero manual setup.
class ApiConfig {
  ApiConfig._();
 
  static const int _apiPort = 5000;
  static const int _discoveryPort = 5001;

  static String _serverIp = '192.168.1.35'; // last-known / fallback
  static bool _discovering = false;

  /// Reactive notifier — widgets rebuild whenever the IP changes.
  static final ValueNotifier<String> serverIpNotifier =
      ValueNotifier('192.168.1.35');

  // ── Initialisation ─────────────────────────────────────────────────────────

  /// Call once in main() before runApp().
  /// Returns immediately after loading the stored IP;
  /// UDP discovery continues in the background.
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('server_ip');
    if (stored != null && stored.isNotEmpty) {
      _serverIp = stored;
      serverIpNotifier.value = stored;
    }
    // Fire-and-forget background discovery
    unawaited(_backgroundDiscover());
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  static String get baseUrl {
    if (kIsWeb) return 'http://localhost:$_apiPort';
    return 'http://$_serverIp:$_apiPort';
  }

  static String get currentServerIp => _serverIp;
  static bool get isDiscovering => _discovering;

  /// Returns the standard JSON + Authorization headers for authenticated calls.
  ///
  /// Use this everywhere instead of building the header map inline, so there
  /// is exactly ONE place to change if the auth scheme ever evolves.
  ///
  ///   final res = await http.get(
  ///     Uri.parse('$baseUrl/api/donor/profile'),
  ///     headers: ApiConfig.authHeaders(widget.token),
  ///   );
  static Map<String, String> authHeaders(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${token.trim()}',
      };

  /// Persist a manually entered IP (from Settings UI).
  static Future<void> setServerIp(String ip) async {
    final trimmed = ip.trim();
    if (trimmed.isEmpty) return;
    _serverIp = trimmed;
    serverIpNotifier.value = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_ip', trimmed);
  }

  /// Re-run UDP discovery on demand (e.g. "Scan Network" button).
  /// Returns the discovered IP, or null if nothing found within 7 s.
  static Future<String?> rescan() async {
    final found = await _udpListen();
    if (found != null) {
      await setServerIp(found);
    }
    return found;
  }

  // ── Internal helpers ────────────────────────────────────────────────────────

  static Future<void> _backgroundDiscover() async {
    if (kIsWeb) return;
    _discovering = true;
    // Trigger UI rebuild by re-emitting the current value
    serverIpNotifier.value = _serverIp;

    final found = await _udpListen();
    _discovering = false;

    if (found != null) {
      await setServerIp(found); // also updates notifier
    } else {
      serverIpNotifier.value = _serverIp; // clear scanning badge
    }
  }

  /// Bind to UDP port 5001 and wait for the backend's broadcast.
  /// Resolves with the sender IP on first valid packet, or null on timeout.
  static Future<String?> _udpListen({int timeoutSeconds = 7}) async {
    if (kIsWeb) return null;
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

      try { sock.close(); } catch (_) {}
      return result;
    } catch (_) {
      try { sock?.close(); } catch (_) {}
      return null;
    }
  }

  /// Quick HTTP ping to verify a given IP is actually the IBDMS server.
  static Future<bool> isServerReachable([String? ip]) async {
    try {
      final target = ip ?? _serverIp;
      final res = await http
          .get(Uri.parse('http://$target:$_apiPort/'))
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
