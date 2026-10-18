import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api_config.dart';

const _red = Color(0xFFB71C1C);
const _redLight = Color(0xFFFEE2E2);

/// Recipient decision card — Connect vs Keep Searching.
class MatchDecisionCard extends StatelessWidget {
  final Map<String, dynamic> match;
  final String token;
  final bool busy;
  final VoidCallback? onConnect;
  final VoidCallback? onContinueSearch;
  final Map<String, dynamic>? authorized;

  const MatchDecisionCard({
    super.key,
    required this.match,
    required this.token,
    this.busy = false,
    this.onConnect,
    this.onContinueSearch,
    this.authorized,
  });

  static Future<Map<String, dynamic>?> connect({
    required String token,
    required int matchId,
  }) async {
    final res = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/alerts/matches/$matchId/connect'),
          headers: ApiConfig.authHeaders(token),
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode == 200) {
      return json.decode(res.body) as Map<String, dynamic>;
    }
    return null;
  }

  static Future<Map<String, dynamic>?> continueSearch({
    required String token,
    required int matchId,
  }) async {
    final res = await http.post(
      Uri.parse(
          '${ApiConfig.baseUrl}/api/alerts/matches/$matchId/continue-search'),
      headers: ApiConfig.authHeaders(token),
    ).timeout(const Duration(seconds: 12));
    if (res.statusCode == 200) {
      return json.decode(res.body) as Map<String, dynamic>;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final alias = match['donor_alias']?.toString() ?? 'Compatible Donor';
    final blood = match['blood_group']?.toString() ?? '—';
    final distLabel = match['distance_label']?.toString() ??
        '${match['distance_km'] ?? '—'} km away';
    final status = match['status']?.toString() ?? 'FOUND';
    final showActions = status == 'FOUND' && authorized == null;

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _red.withValues(alpha: 0.25)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _redLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.volunteer_activism, color: _red),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Matching donor found!',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: Colors.grey[900],
                        ),
                      ),
                      Text(
                        distLabel,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _infoRow(Icons.person_outline, 'Donor', alias),
            const SizedBox(height: 6),
            _infoRow(Icons.bloodtype, 'Blood type', blood),
            const SizedBox(height: 6),
            _infoRow(Icons.place_outlined, 'Distance', distLabel),
            if (authorized != null) ...[
              const Divider(height: 20),
              Text(
                'Contact unlocked',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.green[800],
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              _infoRow(
                Icons.phone_outlined,
                'Phone',
                authorized!['phone']?.toString() ??
                    authorized!['full_name']?.toString() ??
                    'See app',
              ),
            ],
            if (status == 'CONTINUED_SEARCH') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Saved as backup — search continues for more donors.',
                  style: TextStyle(fontSize: 12, color: Colors.blue[900]),
                ),
              ),
            ],
            if (showActions) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: busy ? null : onConnect,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.connect_without_contact, size: 20),
                  label: const Text(
                    'Connect & Contact Now',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onContinueSearch,
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Keep Looking for Backups'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _red,
                    side: const BorderSide(color: _red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
