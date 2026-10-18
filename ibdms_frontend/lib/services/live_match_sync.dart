import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../api_config.dart';
import '../widgets/match_found_overlay.dart';

typedef MatchConnectHandler = Future<void> Function(Map<String, dynamic> match);
typedef MatchBackupHandler = Future<void> Function(Map<String, dynamic> match);

/// Dual-bridge live sync: WebSocket (instant) + 3 s HTTP poll (fallback).
class LiveMatchSync {
  final Set<int> _seenMatchIds = {};
  final Set<String> _seenAlertIds = {};
  bool _dialogOpen = false;
  Timer? _pollTimer;
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSub;

  static const pollInterval = Duration(seconds: 3);

  Set<int> get seenMatchIds => Set.unmodifiable(_seenMatchIds);
  Set<String> get seenAlertIds => Set.unmodifiable(_seenAlertIds);

  void reset() {
    stopPolling();
    stopWebSocket();
    _seenMatchIds.clear();
    _seenAlertIds.clear();
    _dialogOpen = false;
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void stopWebSocket() {
    _wsSub?.cancel();
    _wsSub = null;
    _wsChannel?.sink.close();
    _wsChannel = null;
  }

  void startWebSocket({
    required String token,
    required void Function(Map<String, dynamic> match) onWsMatch,
  }) {
    stopWebSocket();
    try {
      final uri = Uri.parse(
        '${ApiConfig.wsUrl}?token=${Uri.encodeComponent(token.trim())}',
      );
      _wsChannel = WebSocketChannel.connect(uri);
      _wsSub = _wsChannel!.stream.listen(
        (raw) {
          try {
            final data = json.decode(raw as String) as Map<String, dynamic>;
            if (data['type'] == 'pong') return;
            if (data['type'] == 'match_found' && data['status'] == 'FOUND') {
              final match = Map<String, dynamic>.from(
                data['match_data'] as Map? ?? data,
              );
              final id = match['match_id'] as int?;
              if (id != null && _seenMatchIds.contains(id)) return;
              onWsMatch(match);
            }
          } catch (_) {}
        },
        onError: (_) => stopWebSocket(),
        onDone: () => stopWebSocket(),
      );
    } catch (_) {
      stopWebSocket();
    }
  }

  void startPolling({
    required Future<void> Function() pollOnce,
    required bool Function() isActive,
  }) {
    stopPolling();
    unawaited(pollOnce());
    _pollTimer = Timer.periodic(pollInterval, (_) {
      if (isActive()) {
        pollOnce();
      } else {
        stopPolling();
      }
    });
  }

  Future<void> processNewMatches(
    BuildContext context, {
    required List<Map<String, dynamic>> newEvents,
    required MatchConnectHandler onConnect,
    required MatchBackupHandler onKeepLooking,
  }) async {
    for (final match in newEvents) {
      if (!context.mounted) return;
      await _showDecision(context, match, onConnect, onKeepLooking);
    }
  }

  Future<void> _showDecision(
    BuildContext context,
    Map<String, dynamic> match,
    MatchConnectHandler onConnect,
    MatchBackupHandler onKeepLooking,
  ) async {
    final id = match['match_id'] as int?;
    if (id != null) {
      if (_seenMatchIds.contains(id)) return;
      _seenMatchIds.add(id);
    }

    while (_dialogOpen) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!context.mounted) return;
    }

    _dialogOpen = true;
    try {
      await MatchFoundOverlay.showDecisionDialog(
        context,
        match: match,
        onConnect: onConnect,
        onKeepLooking: onKeepLooking,
      );
    } finally {
      _dialogOpen = false;
    }
  }

  void markMatchSeen(int matchId) => _seenMatchIds.add(matchId);
  void markAlertSeen(String alertId) => _seenAlertIds.add(alertId);
}
