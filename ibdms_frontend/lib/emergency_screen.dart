import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'api_config.dart';

/// Emergency Blood Search — open to ALL authenticated users.
///
/// Dual-Role capability: Recipients AND Donors can place blood requests.
/// The backend's time-staged escalation engine handles radius expansion;
/// this screen polls GET /api/requests/{id}/status every 15 s and drives
/// a live countdown UI over the flutter_map.
class EmergencyScreen extends StatefulWidget {
  final String token;
  final String userName;
  final String role;

  const EmergencyScreen({
    super.key,
    required this.token,
    required this.userName,
    required this.role,
  });

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen>
    with SingleTickerProviderStateMixin {
  // ── Map ───────────────────────────────────────────────────────────────────
  final MapController _mapController = MapController();
  bool _mapReady = false;
  static const _defaultLocation = LatLng(24.8607, 67.0011);

  // ── GPS ───────────────────────────────────────────────────────────────────
  LatLng? _deviceLocation;
  bool _gpsLoading = true;
  String _gpsError = '';

  // ── Form config ───────────────────────────────────────────────────────────
  String _selectedBloodGroup = 'A+';
  String _selectedUrgency = 'Critical';
  int _unitsRequired = 1;

  // ── Search state (local UI) ───────────────────────────────────────────────
  bool _isSearching = false;
  bool _searchComplete = false;
  String _searchStatus = ''; // Pending / Fulfilled / Cancelled / Unfulfilled

  // ── Live escalation state (from backend) ─────────────────────────────────
  int? _activeRequestId;
  double _currentRadiusKm = 5.0;
  double _nextRadiusKm = 10.0;
  int _matchedCount = 0;
  List<Map<String, dynamic>> _matchedDonors = [];

  // ── Countdown (local, synced from backend every 15 s) ─────────────────────
  int _secondsUntilExpansion = 300;
  Timer? _countdownTimer;
  Timer? _pollTimer;

  // ── Pulse animation ───────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAlpha;

  // ── Constants ─────────────────────────────────────────────────────────────
  static const _bloodGroups = [
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'
  ];
  static const _urgencies = ['Low', 'Medium', 'Critical'];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _pulseAlpha =
        Tween<double>(begin: 0.06, end: 0.28).animate(_pulseCtrl);
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestGps());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // ── GPS ───────────────────────────────────────────────────────────────────

  Future<void> _requestGps() async {
    if (!mounted) return;
    setState(() { _gpsLoading = true; _gpsError = ''; });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 6),
                onTimeout: () => LocationPermission.denied);
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _applyLocation(_defaultLocation,
            banner: 'Location permission not granted. Using Karachi default.');
        return;
      }
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          _applyLocation(LatLng(last.latitude, last.longitude));
          _refineGps();
          return;
        }
      } catch (_) {}
      final pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.medium)
          .timeout(const Duration(seconds: 10));
      _applyLocation(LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      _applyLocation(_defaultLocation,
          banner: 'GPS unavailable — using Karachi default location.');
    }
  }

  void _applyLocation(LatLng loc, {String? banner}) {
    if (!mounted) return;
    setState(() {
      _deviceLocation = loc;
      _gpsLoading = false;
      _gpsError = banner ?? '';
    });
    if (_mapReady) _mapController.move(loc, 12.0);
  }

  Future<void> _refineGps() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high)
          .timeout(const Duration(seconds: 10));
      if (mounted) {
        setState(() => _deviceLocation = LatLng(pos.latitude, pos.longitude));
        if (_mapReady) _mapController.move(_deviceLocation!, 14.0);
      }
    } catch (_) {}
  }

  // ── Search ────────────────────────────────────────────────────────────────

  Future<void> _startSearch() async {
    if (_deviceLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GPS location not yet available.')));
      return;
    }
    setState(() {
      _isSearching = true;
      _searchComplete = false;
      _searchStatus = 'Pending';
      _activeRequestId = null;
      _currentRadiusKm = 5.0;
      _nextRadiusKm = 10.0;
      _secondsUntilExpansion = 300;
      _matchedCount = 0;
      _matchedDonors = [];
    });
    _pulseCtrl.repeat(reverse: true);

    try {
      final res = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/requests/create'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${widget.token}',
            },
            body: json.encode({
              'blood_group_needed': _selectedBloodGroup,
              'units_required': _unitsRequired,
              'urgency_level': _selectedUrgency,
              'request_latitude': _deviceLocation!.latitude,
              'request_longitude': _deviceLocation!.longitude,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;

      if (res.statusCode == 201) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        setState(() {
          _activeRequestId = data['request_id'] as int;
          _currentRadiusKm =
              (data['current_radius_km'] as num).toDouble();
          _nextRadiusKm = (data['next_radius_km'] as num).toDouble();
          _secondsUntilExpansion =
              (data['seconds_until_expansion'] as int? ?? 300);
          _matchedCount = data['matched_count'] as int? ?? 0;
          _matchedDonors =
              (data['matched_donors'] as List? ?? [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
          _searchStatus = data['status'] as String? ?? 'Pending';
        });
        _syncMapRadius();

        if (_searchStatus == 'Pending') {
          _startCountdown();
          _startPolling();
        } else {
          _endSearch(fromBackend: true);
        }
      } else {
        final err = json.decode(res.body);
        _failSearch(err['detail']?.toString() ?? 'Server error (${res.statusCode})');
      }
    } catch (e) {
      _failSearch('Connection error — check ${ApiConfig.baseUrl}');
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isSearching) return;
      setState(() {
        if (_secondsUntilExpansion > 0) {
          _secondsUntilExpansion--;
        } else {
          // Timer expired — force a status poll now.
          _fetchStatus();
        }
      });
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isSearching) _fetchStatus();
    });
  }

  Future<void> _fetchStatus() async {
    if (_activeRequestId == null || !mounted) return;
    try {
      final res = await http.get(
        Uri.parse(
            '${ApiConfig.baseUrl}/api/requests/$_activeRequestId/status'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final newStatus = data['status'] as String? ?? 'Pending';
        setState(() {
          _currentRadiusKm =
              (data['current_radius_km'] as num).toDouble();
          _nextRadiusKm = (data['next_radius_km'] as num).toDouble();
          _secondsUntilExpansion =
              data['seconds_until_expansion'] as int? ?? 0;
          _matchedCount = data['matched_count'] as int? ?? 0;
          _matchedDonors =
              (data['matched_donors'] as List? ?? [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
          _searchStatus = newStatus;
        });
        _syncMapRadius();

        if (newStatus != 'Pending') {
          _endSearch(fromBackend: true);
        }
      }
    } catch (_) {}
  }

  Future<void> _cancelSearch() async {
    if (_activeRequestId == null) return;
    try {
      await http.post(
        Uri.parse(
            '${ApiConfig.baseUrl}/api/requests/$_activeRequestId/cancel'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      ).timeout(const Duration(seconds: 8));
    } catch (_) {}
    _endSearch(fromBackend: false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Search cancelled.')));
    }
  }

  void _endSearch({required bool fromBackend}) {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    _pulseCtrl.stop();
    if (!mounted) return;
    setState(() {
      _isSearching = false;
      _searchComplete = fromBackend && _searchStatus == 'Fulfilled';
    });
    if (fromBackend && _searchStatus != 'Cancelled') {
      _syncMapRadius();
    }
  }

  void _failSearch(String msg) {
    _pulseCtrl.stop();
    if (!mounted) return;
    setState(() { _isSearching = false; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _clearResults() => setState(() {
        _searchComplete = false;
        _searchStatus = '';
        _matchedDonors = [];
        _matchedCount = 0;
        _activeRequestId = null;
        _currentRadiusKm = 5.0;
        _nextRadiusKm = 10.0;
      });

  void _syncMapRadius() {
    if (!_mapReady || _deviceLocation == null) return;
    _mapController.move(_deviceLocation!, _zoomForRadius(_currentRadiusKm));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  double _zoomForRadius(double km) {
    if (km <= 5) return 12.0;
    if (km <= 10) return 11.5;
    if (km <= 20) return 10.5;
    if (km <= 30) return 9.5;
    return 8.5;
  }

  Color _urgencyColor(String u) => switch (u) {
        'Critical' => Colors.red,
        'Medium' => Colors.orange,
        _ => Colors.green,
      };

  String get _countdownLabel {
    final m = _secondsUntilExpansion ~/ 60;
    final s = _secondsUntilExpansion % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Map circle layers ─────────────────────────────────────────────────────

  List<CircleMarker> _buildCircles(LatLng center, double pulse) {
    if (!_isSearching && !_searchComplete) return [];
    final isComplete = !_isSearching && _searchComplete;
    final color = isComplete
        ? (_matchedCount > 0 ? Colors.green : Colors.grey)
        : Colors.blue;
    return [
      CircleMarker(
        point: center,
        radius: _currentRadiusKm * 1000,
        useRadiusInMeter: true,
        color: color.withAlpha(
            isComplete ? 25 : (pulse * 255).toInt().clamp(15, 60)),
        borderColor: color.withAlpha(isComplete ? 200 : 160),
        borderStrokeWidth: 2.0,
      ),
    ];
  }

  List<Marker> _buildMarkers(LatLng center) => [
        Marker(
          point: center,
          width: 36,
          height: 36,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFB71C1C),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
            ),
            child: const Icon(Icons.person_pin, color: Colors.white, size: 18),
          ),
        ),
        ..._matchedDonors.map((d) {
          final lat = (d['latitude'] as num?)?.toDouble() ?? center.latitude;
          final lon = (d['longitude'] as num?)?.toDouble() ?? center.longitude;
          return Marker(
            point: LatLng(lat, lon),
            width: 28,
            height: 28,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue[700],
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.bloodtype, color: Colors.white, size: 13),
            ),
          );
        }),
      ];

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Blood Search'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'How it works',
            onPressed: _showInfoDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(child: _buildMapBody()),
          if (_searchComplete) _buildResultPanel(),
        ],
      ),
    );
  }

  void _showInfoDialog() => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('How the Search Works'),
          content: const Text(
              '1. Starts scanning at 5 km from your GPS position.\n\n'
              '2. If no compatible donors accept within 5 minutes, the '
              'radius expands by +5 km (→ 10, 15, 20 … up to 50 km).\n\n'
              '3. The search stops as soon as enough donors are found, '
              'you press Cancel, or the 50 km ceiling is reached.\n\n'
              'Open to all users — both Donors and Recipients can request blood.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it')),
          ],
        ),
      );

  // ── Filter bar ────────────────────────────────────────────────────────────

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          _infoChip('Blood Type', _selectedBloodGroup, Colors.red.shade700),
          const SizedBox(width: 8),
          _infoChip('Urgency', _selectedUrgency, _urgencyColor(_selectedUrgency)),
          const Spacer(),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: (_isSearching || _gpsLoading) ? null : _startSearch,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: _isSearching
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search, size: 18),
              label: Text(_isSearching ? 'Searching…' : 'Search'),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 34,
            height: 34,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.tune, size: 20),
              onPressed: _isSearching ? null : _showConfigSheet,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String label, String value, Color color) => GestureDetector(
        onTap: _isSearching ? null : _showConfigSheet,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 9, color: Colors.grey)),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withAlpha(100)),
              ),
              child: Text(value,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
          ],
        ),
      );

  void _showConfigSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Configure Search',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedBloodGroup,
                decoration:
                    const InputDecoration(labelText: 'Blood Group Required'),
                items: _bloodGroups
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (v) {
                  setState(() => _selectedBloodGroup = v!);
                  setSheet(() {});
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedUrgency,
                decoration:
                    const InputDecoration(labelText: 'Urgency Level'),
                items: _urgencies
                    .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                    .toList(),
                onChanged: (v) {
                  setState(() => _selectedUrgency = v!);
                  setSheet(() {});
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Units required:'),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _unitsRequired > 1
                        ? () {
                            setState(() => _unitsRequired--);
                            setSheet(() {});
                          }
                        : null,
                  ),
                  Text('$_unitsRequired',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _unitsRequired < 5
                        ? () {
                            setState(() => _unitsRequired++);
                            setSheet(() {});
                          }
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Apply')),
            ],
          ),
        ),
      ),
    );
  }

  // ── Map body ──────────────────────────────────────────────────────────────

  Widget _buildMapBody() {
    if (_gpsLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFB71C1C)),
            SizedBox(height: 14),
            Text('Acquiring GPS location…',
                style: TextStyle(color: Colors.grey)),
            SizedBox(height: 6),
            Text('Takes up to 10 seconds.',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      );
    }

    final center = _deviceLocation!;
    return Stack(
      children: [
        // ── Map ──────────────────────────────────────────────────────────
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 12.0,
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.all),
            onMapReady: () {
              _mapReady = true;
              _mapController.move(center, 12.0);
            },
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.ibdms_frontend',
            ),
            if (_isSearching || _searchComplete)
              AnimatedBuilder(
                animation: _pulseAlpha,
                builder: (_, __) => CircleLayer(
                    circles: _buildCircles(center, _pulseAlpha.value)),
              ),
            MarkerLayer(markers: _buildMarkers(center)),
          ],
        ),

        // ── GPS banner (dismissible) ──────────────────────────────────────
        if (_gpsError.isNotEmpty)
          Positioned(
            top: 8, left: 12, right: 12,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(10),
              color: Colors.orange[800],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.location_off,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_gpsError,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11))),
                    GestureDetector(
                        onTap: () => setState(() => _gpsError = ''),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 16)),
                  ],
                ),
              ),
            ),
          ),

        // ── Live status card (active search) ─────────────────────────────
        if (_isSearching) _buildLiveStatusCard(center),
      ],
    );
  }

  // ── Live status card ──────────────────────────────────────────────────────

  Widget _buildLiveStatusCard(LatLng center) {
    final isAtCeiling = _currentRadiusKm >= 50.0;
    return Positioned(
      top: _gpsError.isNotEmpty ? 54 : 12,
      left: 12,
      right: 12,
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Row 1: spinner + title + cancel button
              Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFFB71C1C)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Searching within ${_currentRadiusKm.toInt()} km…',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  // ── CANCEL BUTTON ──────────────────────────────────────
                  TextButton.icon(
                    onPressed: _cancelSearch,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Cancel',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Row 2: countdown bar
              if (!isAtCeiling) ...[
                Row(
                  children: [
                    Icon(Icons.timer_outlined,
                        size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 6),
                    Text(
                      'Expanding to ${_nextRadiusKm.toInt()} km in  ',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[700]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFB71C1C).withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: const Color(0xFFB71C1C).withAlpha(80)),
                      ),
                      child: Text(
                        _countdownLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          color: Color(0xFFB71C1C),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Mini progress bar (5-min stage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: 1.0 -
                        (_secondsUntilExpansion.clamp(0, 300) / 300.0),
                    minHeight: 4,
                    backgroundColor: Colors.grey[200],
                    color: const Color(0xFFB71C1C),
                  ),
                ),
                const SizedBox(height: 6),
              ] else ...[
                Row(children: [
                  Icon(Icons.warning_amber_outlined,
                      size: 14, color: Colors.orange[700]),
                  const SizedBox(width: 6),
                  Text('Maximum radius (50 km) reached.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.orange[700])),
                ]),
                const SizedBox(height: 6),
              ],

              // Row 3: matched donors
              Row(
                children: [
                  Icon(
                    _matchedCount > 0
                        ? Icons.group
                        : Icons.person_search_outlined,
                    size: 14,
                    color: _matchedCount > 0
                        ? Colors.green[700]
                        : Colors.grey[500],
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _matchedCount > 0
                        ? '$_matchedCount compatible donor(s) found within ${_currentRadiusKm.toInt()} km'
                        : 'No donors in range yet — expanding soon…',
                    style: TextStyle(
                      fontSize: 12,
                      color: _matchedCount > 0
                          ? Colors.green[700]
                          : Colors.grey[500],
                    ),
                  ),
                ],
              ),

              // Stage breadcrumb
              const SizedBox(height: 6),
              _buildStageCrumbs(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStageCrumbs() {
    final stages = [5, 10, 15, 20, 25, 30, 35, 40, 45, 50];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: stages.map((s) {
          final reached = _currentRadiusKm >= s;
          final isCurrent = _currentRadiusKm.toInt() == s;
          return Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isCurrent
                  ? const Color(0xFFB71C1C)
                  : reached
                      ? Colors.red[100]
                      : Colors.grey[200],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${s}km',
              style: TextStyle(
                fontSize: 9,
                fontWeight:
                    isCurrent ? FontWeight.bold : FontWeight.normal,
                color: isCurrent ? Colors.white : Colors.grey[700],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Result panel ──────────────────────────────────────────────────────────

  Widget _buildResultPanel() {
    final fulfilled = _searchStatus == 'Fulfilled';
    final statusColor = fulfilled ? Colors.green[800] : Colors.grey[700];
    final msg = fulfilled
        ? '$_matchedCount donor(s) alerted within ${_currentRadiusKm.toInt()} km.'
        : _searchStatus == 'Unfulfilled'
            ? 'No donors found within 50 km — Admin notified.'
            : 'Search completed.';

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                fulfilled ? Icons.check_circle : Icons.info_outline,
                color: statusColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(msg,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: statusColor)),
              ),
              TextButton(
                  onPressed: _clearResults, child: const Text('Clear')),
            ],
          ),
          if (_matchedDonors.isNotEmpty) ...[
            const Divider(height: 8),
            SizedBox(
              height: 108,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _matchedDonors.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _donorCard(_matchedDonors[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _donorCard(Map<String, dynamic> d) => Container(
        width: 140,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blue[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Icon(Icons.bloodtype, size: 13, color: Colors.red[700]),
              const SizedBox(width: 4),
              Expanded(
                child: Text(d['name']?.toString() ?? 'Donor',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
            const SizedBox(height: 3),
            Text('📍 ${d['distance_km']} km',
                style: const TextStyle(fontSize: 11)),
            Text('📞 ${d['phone'] ?? '—'}',
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(4)),
              child: const Text('Alerted',
                  style: TextStyle(fontSize: 10, color: Colors.green)),
            ),
          ],
        ),
      );
}
