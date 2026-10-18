import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _red = Color(0xFFB71C1C);
const _redLight = Color(0xFFFEE2E2);

typedef MatchDecisionHandler = Future<void> Function(Map<String, dynamic> match);

/// Production match-decision modal — FOUND pop-up with Connect / Keep Looking.
class MatchFoundOverlay {
  MatchFoundOverlay._();

  static Future<void> notifyUser() async {
    try {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      await HapticFeedback.mediumImpact();
    } catch (_) {}
    try {
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
  }

  /// Shows decision pop-up for a FOUND match (recipient searching screen).
  static Future<void> showDecisionDialog(
    BuildContext context, {
    required Map<String, dynamic> match,
    required MatchDecisionHandler onConnect,
    required MatchDecisionHandler onKeepLooking,
    Map<String, dynamic>? authorized,
    bool busy = false,
  }) async {
    await notifyUser();
    if (!context.mounted) return;

    final alias = match['donor_alias']?.toString() ?? 'Compatible Donor';
    final blood = match['blood_group']?.toString() ?? '—';
    final dist = match['distance_label']?.toString() ??
        (match['distance_km'] != null
            ? '${match['distance_km']} km away'
            : 'Nearby');
    final status = match['status']?.toString() ?? 'FOUND';
    final showActions = status == 'FOUND' && authorized == null;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: !showActions,
      barrierLabel: 'Match found',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, animation, _) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> runAction(MatchDecisionHandler fn) async {
              if (busy) return;
              setLocal(() => busy = true);
              try {
                await fn(match);
                if (ctx.mounted) Navigator.of(ctx).pop();
              } finally {
                if (ctx.mounted) setLocal(() => busy = false);
              }
            }

            return Center(
              child: Material(
                color: Colors.transparent,
                child: ScaleTransition(
                  scale: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutBack,
                  ),
                  child: Container(
                    width: 360,
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: _red.withValues(alpha: 0.28),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                          decoration: const BoxDecoration(
                            color: _redLight,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(22),
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.volunteer_activism,
                                  color: _red,
                                  size: 38,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Matching Donor Found!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: _red,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'A compatible donor is within your search radius.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _row(Icons.person_outline, 'Donor', alias),
                              const SizedBox(height: 8),
                              _row(Icons.bloodtype, 'Blood type', blood),
                              const SizedBox(height: 8),
                              _row(Icons.place_outlined, 'Distance', dist),
                              if (authorized != null) ...[
                                const Divider(height: 22),
                                Text(
                                  'Contact unlocked',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.green[800],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _row(
                                  Icons.phone_outlined,
                                  'Phone',
                                  authorized['phone']?.toString() ?? '—',
                                ),
                              ],
                              if (showActions) ...[
                                const SizedBox(height: 20),
                                SizedBox(
                                  height: 48,
                                  child: ElevatedButton.icon(
                                    onPressed: busy
                                        ? null
                                        : () => runAction(onConnect),
                                    icon: busy
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.connect_without_contact,
                                            size: 20,
                                          ),
                                    label: const Text(
                                      'Connect & Contact Now',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _red,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  height: 46,
                                  child: OutlinedButton.icon(
                                    onPressed: busy
                                        ? null
                                        : () => runAction(onKeepLooking),
                                    icon: const Icon(Icons.search, size: 18),
                                    label: const Text(
                                      'Keep Looking for Backups',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _red,
                                      side: const BorderSide(color: _red),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ] else ...[
                                const SizedBox(height: 16),
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('Close'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Widget _row(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 10),
        Text('$label: ', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// Sticky banner while a FOUND match awaits decision.
class MatchFoundBanner extends StatelessWidget {
  final Map<String, dynamic> match;
  final VoidCallback onTap;

  const MatchFoundBanner({
    super.key,
    required this.match,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final blood = match['blood_group']?.toString() ?? '—';
    final dist = match['distance_label']?.toString() ??
        '${match['distance_km'] ?? '—'} km';

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: _red,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.notifications_active,
                  color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Donor found — tap to respond',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '$blood · $dist',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
