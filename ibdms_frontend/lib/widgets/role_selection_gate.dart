import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api_config.dart';

const _red = Color(0xFFDC2626);
const _redDark = Color(0xFFB91C1C);
const _redLight = Color(0xFFFEE2E2);
const _white = Color(0xFFFFFFFF);
const _text = Color(0xFF1E293B);
const _muted = Color(0xFF64748B);

/// Mandatory onboarding card — user must pick Donor or Recipient before
/// accessing the workspace.
class RoleSelectionGate extends StatefulWidget {
  final String token;
  final String userName;
  final ValueChanged<RoleSelectionResult> onComplete;

  const RoleSelectionGate({
    super.key,
    required this.token,
    required this.userName,
    required this.onComplete,
  });

  @override
  State<RoleSelectionGate> createState() => _RoleSelectionGateState();
}

class RoleSelectionResult {
  final String token;
  final String role;

  const RoleSelectionResult({required this.token, required this.role});
}

class _RoleSelectionGateState extends State<RoleSelectionGate> {
  bool _submitting = false;
  String? _error;

  Future<void> _select(String role) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final res = await http
          .patch(
            Uri.parse('${ApiConfig.baseUrl}/api/auth/select-role'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${widget.token}',
            },
            body: json.encode({'role': role}),
          )
          .timeout(const Duration(seconds: 12));

      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        widget.onComplete(RoleSelectionResult(
          token: data['access_token'] as String? ?? widget.token,
          role: data['role'] as String? ?? role,
        ));
      } else {
        final body = json.decode(res.body) as Map<String, dynamic>;
        setState(() =>
            _error = body['detail']?.toString() ?? 'Could not save your choice.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Network error — check your connection.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              decoration: BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _red.withValues(alpha: 0.35), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: _red.withValues(alpha: 0.12),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _redLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.bloodtype, color: _red, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.userName.isNotEmpty
                                  ? 'Welcome, ${widget.userName.split(' ').first}'
                                  : 'Welcome to IBDMS',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: _text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'How will you use IBDMS today?',
                              style: TextStyle(fontSize: 13, color: _muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose your primary path to continue. You can access both '
                    'donation and emergency features later from your profile.',
                    style: TextStyle(fontSize: 13, color: _muted, height: 1.45),
                  ),
                  const SizedBox(height: 20),
                  _RoleTile(
                    icon: Icons.volunteer_activism_outlined,
                    title: 'I want to Volunteer & Donate Blood',
                    subtitle: 'Receive alerts and respond to nearby emergencies',
                    enabled: !_submitting,
                    onTap: () => _select('Donor'),
                  ),
                  const SizedBox(height: 12),
                  _RoleTile(
                    icon: Icons.emergency_outlined,
                    title: 'I am looking for Emergency Blood',
                    subtitle: 'Start a GPS-matched urgent blood search',
                    enabled: !_submitting,
                    onTap: () => _select('Recipient'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: _redDark),
                    ),
                  ],
                  if (_submitting) ...[
                    const SizedBox(height: 20),
                    const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _red,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _RoleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_RoleTile> createState() => _RoleTileState();
}

class _RoleTileState extends State<_RoleTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hovered && widget.enabled ? _redLight : _white;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: widget.enabled ? widget.onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _hovered && widget.enabled
                    ? _red.withValues(alpha: 0.55)
                    : const Color(0xFFE2E8F0),
                width: _hovered && widget.enabled ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icon, color: _red, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _text,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: widget.enabled ? _red : _muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
