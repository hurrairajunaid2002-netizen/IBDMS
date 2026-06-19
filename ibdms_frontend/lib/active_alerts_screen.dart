import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

/// Active Alerts feed — open to ALL authenticated users.
///
/// Dual-Role additions
/// ───────────────────
/// • Any user (Recipient, Admin, etc.) who does NOT yet have a DonorProfile
///   sees a "Become a Volunteer Donor" enrolment banner at the top.
/// • Tapping the banner opens a bottom sheet with blood-group / weight / DOB
///   fields, which submits to POST /api/donor/enroll.
/// • Once enrolled the availability toggle is shown, so the user can go
///   Active immediately.
class ActiveAlertsScreen extends StatefulWidget {
  final String token;
  final String userName;
  final String role;

  const ActiveAlertsScreen({
    super.key,
    required this.token,
    required this.userName,
    required this.role,
  });

  @override
  State<ActiveAlertsScreen> createState() => _ActiveAlertsScreenState();
}

class _ActiveAlertsScreenState extends State<ActiveAlertsScreen> {
  // ── Donor profile state ───────────────────────────────────────────────────
  bool _profileChecked = false;
  bool _hasDonorProfile = false;
  bool _enrolling = false;

  // ── 60-day cooldown state ─────────────────────────────────────────────────
  bool _inCooldown = false;
  int _daysRemaining = 0;
  String _eligibleDate = '';

  // ── Availability ──────────────────────────────────────────────────────────
  bool _available = true;
  bool _togglingAvailability = false;

  // ── Alerts ────────────────────────────────────────────────────────────────
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _alerts = [];
  Position? _position;
  Timer? _refreshTimer;

  // ── Enrolment form controllers ─────────────────────────────────────────────
  final _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  String _enrollBloodGroup = 'O+';
  final _weightCtrl = TextEditingController(text: '65');
  final _dobCtrl = TextEditingController(text: '1995-01-01');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _weightCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_getPosition(), _checkDonorProfile(), _checkCooldown()]);
    await _loadAlerts();
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _loadAlerts());
  }

  // ── GPS (passive — no requestPermission) ─────────────────────────────────

  Future<void> _getPosition() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) { _position = last; return; }
      _position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.medium)
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  // ── 60-day cooldown check ─────────────────────────────────────────────────

  Future<void> _checkCooldown() async {
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/donor/cooldown'),
        headers: {'Authorization': 'Bearer ${widget.token.trim()}'},
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        setState(() {
          _inCooldown = data['is_in_cooldown'] as bool? ?? false;
          _daysRemaining = data['days_remaining'] as int? ?? 0;
          _eligibleDate = data['eligible_date'] as String? ?? '';
        });
      }
    } catch (_) {}
  }

  // ── Donor profile check ───────────────────────────────────────────────────

  Future<void> _checkDonorProfile() async {
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/donor/profile'),
        headers: {'Authorization': 'Bearer ${widget.token.trim()}'},
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        setState(() {
          _hasDonorProfile = data['donor_profile'] != null;
          _profileChecked = true;
          if (_hasDonorProfile) {
            final dp = data['donor_profile'] as Map;
            _available = dp['availability_status'] == 'Active';
          }
        });
      } else {
        setState(() => _profileChecked = true);
      }
    } catch (_) {
      if (mounted) setState(() => _profileChecked = true);
    }
  }

  // ── Enrol as donor ────────────────────────────────────────────────────────

  Future<void> _submitEnrolment() async {
    if (_enrolling) return;
    setState(() => _enrolling = true);
    final lat = _position?.latitude ?? 24.8607;
    final lon = _position?.longitude ?? 67.0011;
    try {
      final res = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/donor/enroll'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${widget.token}',
            },
            body: json.encode({
              'blood_group': _enrollBloodGroup,
              'weight_kg': double.tryParse(_weightCtrl.text.trim()) ?? 60.0,
              'dob': _dobCtrl.text.trim(),
              'gps_latitude': lat,
              'gps_longitude': lon,
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      if (res.statusCode == 201) {
        Navigator.pop(context);
        setState(() { _hasDonorProfile = true; _available = true; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('You are now enrolled as a donor volunteer!')));
      } else {
        final err = json.decode(res.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(err['detail']?.toString() ?? 'Enrolment failed.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Network error.')));
      }
    } finally {
      if (mounted) setState(() => _enrolling = false);
    }
  }

  void _showEnrolmentSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.volunteer_activism,
                        color: Colors.green[700], size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Enrol as Donor Volunteer',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17)),
                  ),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                  'Provide your donor information to join the active matching pool.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _enrollBloodGroup,
                decoration:
                    const InputDecoration(labelText: 'Blood Group', border: OutlineInputBorder()),
                items: _bloodGroups
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (v) {
                  setState(() => _enrollBloodGroup = v!);
                  setSheet(() {});
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _weightCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Weight (kg)',
                    border: OutlineInputBorder(),
                    hintText: 'e.g. 65'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dobCtrl,
                keyboardType: TextInputType.datetime,
                decoration: const InputDecoration(
                    labelText: 'Date of Birth (YYYY-MM-DD)',
                    border: OutlineInputBorder(),
                    hintText: '1995-06-15'),
              ),
              const SizedBox(height: 16),
              // 7-criterion eligibility reminder
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Eligibility Criteria',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.blue[800])),
                    const SizedBox(height: 4),
                    ...[
                      '✓ Age: 17–65 years',
                      '✓ Weight: ≥ 50 kg',
                      '✓ Haemoglobin: ≥ 12.5 g/dL',
                      '✓ No active infections or chronic conditions',
                      '✓ 56-day gap since last whole-blood donation',
                      '✓ No recent tattoos / piercings (< 6 months)',
                      '✓ Not pregnant or recently post-partum',
                    ].map((c) => Text(c,
                        style: TextStyle(
                            fontSize: 11, color: Colors.blue[700]))),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _enrolling ? null : _submitEnrolment,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700]),
                icon: _enrolling
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check),
                label: Text(_enrolling ? 'Enrolling…' : 'Enrol as Donor'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Alerts ────────────────────────────────────────────────────────────────

  Future<void> _loadAlerts() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });

    final lat = _position?.latitude ?? 24.8607;
    final lon = _position?.longitude ?? 67.0011;

    try {
      final uri = Uri.parse(
          '${ApiConfig.baseUrl}/api/requests/nearby?lat=$lat&lon=$lon&radius=50');
      final res = await http.get(uri, headers: {
        'Authorization': 'Bearer ${widget.token.trim()}',
        'Content-Type': 'application/json',
      }).timeout(const Duration(seconds: 12));

      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        setState(() => _alerts = (data['requests'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            []);
      } else {
        setState(() => _error = 'Failed to load alerts (${res.statusCode})');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Network error: ${ApiConfig.baseUrl}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleAvailability(bool val) async {
    setState(() => _togglingAvailability = true);
    try {
      final res = await http
          .put(
            Uri.parse('${ApiConfig.baseUrl}/api/donor/availability'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${widget.token}',
            },
            body: json.encode({'status': val ? 'Active' : 'Inactive'}),
          )
          .timeout(const Duration(seconds: 10));
      if (mounted && res.statusCode == 200) {
        setState(() => _available = val);
      }
    } catch (_) {
      if (mounted) setState(() => _available = val);
    } finally {
      if (mounted) setState(() => _togglingAvailability = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color _urgencyColor(String? u) => switch (u) {
        'Critical' => Colors.red,
        'Medium' => Colors.orange,
        _ => Colors.green,
      };

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) { return ''; }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  // ── 60-day cooldown screen ────────────────────────────────────────────────

  Widget _buildCooldownScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                shape: BoxShape.circle,
                border: Border.all(color: Colors.orange[200]!, width: 2),
              ),
              child: Icon(Icons.favorite_border,
                  size: 56, color: Colors.orange[700]),
            ),
            const SizedBox(height: 24),
            Text(
              'Thank You for Your Life-Saving Donation!',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[900]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Column(children: [
                Text(
                  '$_daysRemaining',
                  style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[800]),
                ),
                Text(
                  'days until you can donate again',
                  style: TextStyle(
                      fontSize: 13, color: Colors.orange[700]),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            Text(
              'To protect your health, the 60-day recovery period must complete '
              'before your next whole-blood donation.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            if (_eligibleDate.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Eligible from: $_eligibleDate',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.green[700],
                    fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.info_outline, size: 16),
              label: const Text('Why 60 days?'),
            ),
            const SizedBox(height: 8),
            Text(
              'Whole blood replenishment takes 56–60 days. '
              'Iron stores and haemoglobin need this full cycle to recover.',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show cooldown screen when user is enrolled and in cooling-off period.
    if (_profileChecked && _hasDonorProfile && _inCooldown) {
      return Scaffold(
        appBar: AppBar(title: const Text('Donor Status')),
        body: _buildCooldownScreen(),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Active Emergency Alerts'),
        actions: [
          if (_hasDonorProfile)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _togglingAvailability
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Switch(
                      value: _available,
                      activeThumbColor: Colors.white,
                      activeTrackColor: Colors.green[400],
                      inactiveThumbColor: Colors.grey[300],
                      inactiveTrackColor: Colors.grey[600],
                      onChanged: _toggleAvailability,
                    ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Volunteer enrolment banner (non-donors) ─────────────────────
          if (_profileChecked && !_hasDonorProfile) _buildEnrolBanner(),

          // ── Availability status bar (enrolled donors) ───────────────────
          if (_hasDonorProfile)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              color: _available ? Colors.green[700] : Colors.grey[700],
              padding:
                  const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Icon(_available ? Icons.circle : Icons.circle_outlined,
                        size: 10, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      _available
                          ? 'I am Available to Donate'
                          : 'Currently Unavailable',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ]),
                  if (_position != null)
                    Text('GPS Active',
                        style: TextStyle(
                            color: Colors.white.withAlpha(200),
                            fontSize: 11)),
                ],
              ),
            ),

          // ── Header & refresh ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'ACTIVE EMERGENCY ALERTS',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: Colors.grey[600]),
                  ),
                ),
                if (_loading)
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: _loadAlerts,
                    tooltip: 'Refresh',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),

          Expanded(child: _buildAlertsList()),
        ],
      ),
    );
  }

  // ── Enrol banner ──────────────────────────────────────────────────────────

  Widget _buildEnrolBanner() {
    return GestureDetector(
      onTap: _showEnrolmentSheet,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.green[700]!, Colors.green[500]!],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.green.withAlpha(60),
                blurRadius: 8,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.white.withAlpha(50),
                  shape: BoxShape.circle),
              child: const Icon(Icons.volunteer_activism,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Become a Volunteer Donor',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Tap to complete the 7-criterion check and join the active donor pool.',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.white70, size: 16),
          ],
        ),
      ),
    );
  }

  // ── Alert list ────────────────────────────────────────────────────────────

  Widget _buildAlertsList() {
    if (_loading && _alerts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _alerts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadAlerts,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_alerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('No active alerts in your area.',
                style: TextStyle(color: Colors.grey[500])),
            const SizedBox(height: 8),
            Text('Pull to refresh or check back later.',
                style: TextStyle(fontSize: 12, color: Colors.grey[400])),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAlerts,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: _alerts.length,
        itemBuilder: (_, i) => _buildAlertCard(_alerts[i]),
      ),
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    final bloodGroup = alert['blood_group_needed']?.toString() ?? '?';
    final urgency = alert['urgency_level']?.toString() ?? 'Low';
    final distance =
        (alert['distance_km'] as num?)?.toStringAsFixed(1) ?? '—';
    final location =
        alert['location_hint']?.toString() ?? 'Karachi, Pakistan';
    final time = _timeAgo(alert['created_at']?.toString());
    final alertStatus = alert['status']?.toString() ?? 'Pending';
    final searchRadius =
        (alert['current_radius_km'] as num?)?.toInt() ?? 5;
    final urgencyColor = _urgencyColor(urgency);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showAlertDetail(alert),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: urgencyColor.withAlpha(25),
                  shape: BoxShape.circle,
                  border: Border.all(color: urgencyColor, width: 1.5),
                ),
                child: Center(
                  child: Text(bloodGroup,
                      style: TextStyle(
                          color: urgencyColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (time.isNotEmpty)
                      Text(time,
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey[500])),
                    Text('Location: $location',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Row(children: [
                      Text(
                        '$bloodGroup  •  $distance km away  •  ',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                      Text(urgency,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: urgencyColor)),
                    ]),
                    const SizedBox(height: 2),
                    Row(children: [
                      Icon(Icons.radar, size: 11, color: Colors.blue[400]),
                      const SizedBox(width: 3),
                      Text(
                        'Search radius: ${searchRadius} km  •  '
                        '${alertStatus == 'Pending' ? 'Awaiting response' : alertStatus}',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey[500]),
                      ),
                    ]),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  void _showAlertDetail(Map<String, dynamic> alert) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        final urgency = alert['urgency_level']?.toString() ?? 'Low';
        final color = _urgencyColor(urgency);
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    alert['blood_group_needed']?.toString() ?? '?',
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Text(urgency,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ]),
              const SizedBox(height: 16),
              _detailRow(Icons.location_on_outlined, 'Location',
                  alert['location_hint']?.toString() ?? 'N/A'),
              _detailRow(Icons.straighten, 'Distance',
                  '${(alert['distance_km'] as num?)?.toStringAsFixed(1) ?? '—'} km'),
              _detailRow(Icons.bloodtype, 'Units Needed',
                  '${alert['units_required'] ?? '?'}'),
              _detailRow(Icons.radar, 'Search Radius',
                  '${(alert['current_radius_km'] as num?)?.toInt() ?? 5} km'),
              _detailRow(Icons.access_time, 'Requested',
                  _timeAgo(alert['created_at']?.toString())),
              const SizedBox(height: 20),
              if (_hasDonorProfile)
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Response acknowledged. Contact the recipient directly.')));
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700]),
                  icon: const Icon(Icons.volunteer_activism),
                  label: const Text('Respond to Request'),
                )
              else
                ElevatedButton.icon(
                  onPressed: _showEnrolmentSheet,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600]),
                  icon: const Icon(Icons.person_add),
                  label: const Text('Enrol as Donor to Respond'),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 10),
          Text('$label: ',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13)),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
      );
}
