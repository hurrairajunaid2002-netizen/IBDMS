import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'auth_logout.dart';

// ── Clinical light-mode design tokens ────────────────────────────────────────
const _white = Color(0xFFFFFFFF);
const _panel = Color(0xFFF8FAFC);
const _red = Color(0xFFDC2626);
const _redDark = Color(0xFFB91C1C);
const _redLight = Color(0xFFFEE2E2);
const _text = Color(0xFF1E293B);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);
const _skeleton = Color(0xFFE2E8F0);

/// Standard mobile content inset below the custom app bar.
const _mobileContentPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);

const _bloodGroups = ['ALL', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
const _requestStatuses = [
  'ALL',
  'Pending',
  'Fulfilled',
  'Cancelled',
  'Unfulfilled',
  'Expired',
];

/// Administrative Command Center — light clinical theme, web-optimised.
class AdminDashboardScreen extends StatefulWidget {
  final String token;
  final String adminName;
  const AdminDashboardScreen({
    super.key,
    required this.token,
    this.adminName = 'Administrator',
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _section = 0;

  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _bloodStock = [];
  List<Map<String, dynamic>> _timeline = [];
  List<Map<String, dynamic>> _heatmap = [];

  List<Map<String, dynamic>> _donors = [];
  int _donorTotal = 0;
  int _donorPage = 1;
  String _donorSearch = '';
  String _donorBloodFilter = 'ALL';
  final _donorSearchCtrl = TextEditingController();

  List<Map<String, dynamic>> _requests = [];
  int _requestTotal = 0;
  int _requestPage = 1;
  String _requestSearch = '';
  String _requestStatusFilter = 'ALL';
  String _requestBloodFilter = 'ALL';
  final _requestSearchCtrl = TextEditingController();

  bool _overviewLoading = true;
  bool _donorsLoading = true;
  bool _requestsLoading = true;
  String? _overviewError;
  String? _donorsError;
  String? _requestsError;

  Map<String, dynamic>? _editingDonor;
  Map<String, dynamic>? _editingRequest;

  @override
  void initState() {
    super.initState();
    _loadOverview();
    _loadDonors();
    _loadRequests();
  }

  @override
  void dispose() {
    _donorSearchCtrl.dispose();
    _requestSearchCtrl.dispose();
    super.dispose();
  }

  Map<String, String> get _headers => ApiConfig.authHeaders(widget.token);

  String? _apiErrorMessage(http.Response res) {
    try {
      final body = _decodeJsonBody(res);
      if (body is Map && body['detail'] != null) {
        return body['detail'].toString();
      }
    } catch (_) {}
    return 'Server returned HTTP ${res.statusCode}.';
  }

  dynamic _decodeJsonBody(http.Response res) {
    final body = res.body.trim();
    if (body.isEmpty) {
      throw const FormatException('Empty response from server.');
    }
    if (body.startsWith('<!') || body.toLowerCase().startsWith('<html')) {
      throw const FormatException(
        'Received HTML instead of JSON — check API URL or Ngrok tunnel.',
      );
    }
    return json.decode(body);
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? _red : _text,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _loadOverview() async {
    setState(() {
      _overviewLoading = true;
      _overviewError = null;
    });
    try {
      final endpoints = [
        ('stats', '${ApiConfig.baseUrl}/api/admin/stats'),
        ('blood-stock', '${ApiConfig.baseUrl}/api/admin/analytics/blood-stock'),
        ('timeline', '${ApiConfig.baseUrl}/api/admin/analytics/timeline'),
        ('heatmap', '${ApiConfig.baseUrl}/api/admin/analytics/heatmap'),
      ];

      final results = await Future.wait(
        endpoints.map(
          (e) => http
              .get(Uri.parse(e.$2), headers: _headers)
              .timeout(const Duration(seconds: 15)),
        ),
      );

      if (!mounted) return;

      String? error;
      for (var i = 0; i < results.length; i++) {
        final res = results[i];
        final key = endpoints[i].$1;
        if (res.statusCode != 200) {
          error ??= _apiErrorMessage(res);
          continue;
        }
        try {
          final data = _decodeJsonBody(res) as Map<String, dynamic>;
          switch (key) {
            case 'stats':
              _stats = data;
            case 'blood-stock':
              _bloodStock = (data['groups'] as List?)
                      ?.map((e) => Map<String, dynamic>.from(e as Map))
                      .toList() ??
                  [];
            case 'timeline':
              _timeline = (data['days'] as List?)
                      ?.map((e) => Map<String, dynamic>.from(e as Map))
                      .toList() ??
                  [];
            case 'heatmap':
              _heatmap = (data['sectors'] as List?)
                      ?.map((e) => Map<String, dynamic>.from(e as Map))
                      .toList() ??
                  [];
          }
        } catch (e) {
          error ??= 'Failed to parse $key: $e';
        }
      }

      if (error != null) {
        _overviewError =
            '$error Backend: ${ApiConfig.baseUrl} — ensure uvicorn + MySQL are running.';
        _toast('Failed to load analytics.', error: true);
      }
    } catch (e) {
      _overviewError =
          'Cannot reach backend at ${ApiConfig.baseUrl}. ($e) Start uvicorn on port 5000 and ensure MySQL (XAMPP) is running.';
      _toast('Failed to load analytics.', error: true);
    }
    if (mounted) setState(() => _overviewLoading = false);
  }

  Future<void> _loadDonors() async {
    setState(() {
      _donorsLoading = true;
      _donorsError = null;
    });
    try {
      final q = Uri.parse('${ApiConfig.baseUrl}/api/admin/donors').replace(
        queryParameters: {
          'page': '$_donorPage',
          'limit': '12',
          if (_donorSearch.isNotEmpty) 'search': _donorSearch,
          if (_donorBloodFilter != 'ALL') 'blood_group': _donorBloodFilter,
        },
      );
      final res =
          await http.get(q, headers: _headers).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = _decodeJsonBody(res) as Map<String, dynamic>;
        _donors = (data['donors'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        _donorTotal = data['total'] as int? ?? 0;
      } else {
        _donorsError = _apiErrorMessage(res);
        _toast('Failed to load donors.', error: true);
      }
    } catch (_) {
      _donorsError =
          'Cannot reach backend at ${ApiConfig.baseUrl}. Start uvicorn and ensure MySQL is running.';
      _toast('Failed to load donors.', error: true);
    }
    if (mounted) setState(() => _donorsLoading = false);
  }

  Future<void> _loadRequests() async {
    setState(() {
      _requestsLoading = true;
      _requestsError = null;
    });
    try {
      final q = Uri.parse('${ApiConfig.baseUrl}/api/admin/requests').replace(
        queryParameters: {
          'page': '$_requestPage',
          'limit': '12',
          if (_requestSearch.isNotEmpty) 'search': _requestSearch,
          if (_requestStatusFilter != 'ALL') 'status': _requestStatusFilter,
          if (_requestBloodFilter != 'ALL') 'blood_group': _requestBloodFilter,
        },
      );
      final res =
          await http.get(q, headers: _headers).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = _decodeJsonBody(res) as Map<String, dynamic>;
        _requests = (data['requests'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        _requestTotal = data['total'] as int? ?? 0;
      } else {
        _requestsError = _apiErrorMessage(res);
        _toast('Failed to load requests.', error: true);
      }
    } catch (_) {
      _requestsError =
          'Cannot reach backend at ${ApiConfig.baseUrl}. Start uvicorn and ensure MySQL is running.';
      _toast('Failed to load requests.', error: true);
    }
    if (mounted) setState(() => _requestsLoading = false);
  }

  Future<void> _saveDonor(Map<String, dynamic> donor, Map<String, dynamic> form) async {
    try {
      final res = await http.put(
        Uri.parse(
            '${ApiConfig.baseUrl}/api/admin/users/${donor['user_id']}/override'),
        headers: _headers,
        body: json.encode({
          'full_name': form['full_name'],
          'phone_number': form['phone_number'],
          'blood_group': form['blood_group'],
          if (form['force_eligible'] == true) 'force_eligible': true,
          if (form['force_deferred'] == true)
            'is_locked': true,
        }),
      );
      if (res.statusCode == 200) {
        _toast('Donor record updated — synced to database.');
        setState(() => _editingDonor = null);
        await _loadDonors();
        await _loadOverview();
      } else {
        _toast('Update failed.', error: true);
      }
    } catch (_) {
      _toast('Network error.', error: true);
    }
  }

  Future<void> _saveRequest(
      Map<String, dynamic> req, Map<String, dynamic> form) async {
    try {
      final res = await http.put(
        Uri.parse(
            '${ApiConfig.baseUrl}/api/admin/requests/${req['request_id']}/override'),
        headers: _headers,
        body: json.encode({
          'recipient_name': form['recipient_name'],
          'status': form['status'],
          'blood_group_needed': form['blood_group'],
          'current_radius_km': double.tryParse(form['radius']?.toString() ?? ''),
          'request_latitude': double.tryParse(form['lat']?.toString() ?? ''),
          'request_longitude': double.tryParse(form['lng']?.toString() ?? ''),
        }),
      );
      if (res.statusCode == 200) {
        _toast('Request updated — mobile users will see changes immediately.');
        setState(() => _editingRequest = null);
        await _loadRequests();
        await _loadOverview();
      } else {
        _toast('Update failed.', error: true);
      }
    } catch (_) {
      _toast('Network error.', error: true);
    }
  }

  Future<void> _logout() => AuthLogout.perform(context);

  void _openDonorEditor(Map<String, dynamic> donor) {
    setState(() => _editingDonor = donor);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scaffoldKey.currentState?.openEndDrawer();
    });
  }

  void _openRequestEditor(Map<String, dynamic> request) {
    setState(() => _editingRequest = request);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scaffoldKey.currentState?.openEndDrawer();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 768;
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: _panel,
          drawer: isMobile ? _buildMobileDrawer() : null,
          bottomNavigationBar: isMobile ? _buildBottomNav() : null,
          endDrawer: _editingDonor != null
              ? _DonorEditSheet(
                  donor: _editingDonor!,
                  onSave: (form) => _saveDonor(_editingDonor!, form),
                  onClose: () {
                    setState(() => _editingDonor = null);
                    Navigator.of(context).maybePop();
                  },
                )
              : _editingRequest != null
                  ? _RequestEditSheet(
                      request: _editingRequest!,
                      onSave: (form) => _saveRequest(_editingRequest!, form),
                      onClose: () {
                        setState(() => _editingRequest = null);
                        Navigator.of(context).maybePop();
                      },
                    )
                  : null,
          onEndDrawerChanged: (open) {
            if (!open) {
              setState(() {
                _editingDonor = null;
                _editingRequest = null;
              });
            }
          },
          body: isMobile
              ? SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      _buildMobileHeader(),
                      Expanded(child: _buildMain(isMobile: true)),
                    ],
                  ),
                )
              : Row(
                  children: [
                    _buildSidebar(),
                    Expanded(child: _buildMain(isMobile: false)),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildMobileHeader() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: _white,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu, color: _text),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          Expanded(
            child: Text(
              ['Overview', 'Donor Grid', 'Requests'][_section],
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: _text,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: _muted),
            onPressed: () {
              _loadOverview();
              _loadDonors();
              _loadRequests();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMobileDrawer() {
    return Drawer(
      backgroundColor: _white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'IBDMS Command Center',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: _text,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_outlined, color: _red),
              title: const Text('Overview'),
              onTap: () {
                setState(() => _section = 0);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.volunteer_activism_outlined, color: _red),
              title: const Text('Donor Grid'),
              onTap: () {
                setState(() => _section = 1);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.emergency_outlined, color: _red),
              title: const Text('Request Stream'),
              onTap: () {
                setState(() => _section = 2);
                Navigator.pop(context);
              },
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.adminName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, color: _text)),
                  const Text('Administrator',
                      style: TextStyle(fontSize: 12, color: _muted)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text('Sign Out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _red,
                      side: const BorderSide(color: _red),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return NavigationBar(
      selectedIndex: _section,
      backgroundColor: _white,
      indicatorColor: _redLight,
      onDestinationSelected: (i) => setState(() => _section = i),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard, color: _red),
          label: 'Overview',
        ),
        NavigationDestination(
          icon: Icon(Icons.volunteer_activism_outlined),
          selectedIcon: Icon(Icons.volunteer_activism, color: _red),
          label: 'Donors',
        ),
        NavigationDestination(
          icon: Icon(Icons.emergency_outlined),
          selectedIcon: Icon(Icons.emergency, color: _red),
          label: 'Requests',
        ),
      ],
    );
  }

  Widget _buildSidebar() {
    final items = [
      (0, Icons.dashboard_outlined, 'Overview'),
      (1, Icons.volunteer_activism_outlined, 'Donor Grid'),
      (2, Icons.emergency_outlined, 'Request Stream'),
    ];
    return Container(
      width: 240,
      color: _white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _border)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.bloodtype, color: _white, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'IBDMS\nCommand Center',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _text,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...items.map((item) {
            final selected = _section == item.$1;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: Material(
                color: selected ? _redLight : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _section = item.$1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Icon(item.$2,
                            size: 20,
                            color: selected ? _red : _muted),
                        const SizedBox(width: 10),
                        Text(
                          item.$3,
                          style: TextStyle(
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? _redDark : _text,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.adminName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: _text)),
                const Text('Administrator',
                    style: TextStyle(fontSize: 11, color: _muted)),
                const SizedBox(height: 8),
                Text(
                  'API: ${ApiConfig.baseUrl}',
                  style: const TextStyle(fontSize: 10, color: _muted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout, size: 16),
                  label: const Text('Sign Out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _red,
                    side: const BorderSide(color: _red),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMain({required bool isMobile}) {
    if (isMobile) {
      return switch (_section) {
        0 => _buildOverview(isMobile: true),
        1 => _buildDonorGrid(isMobile: true),
        _ => _buildRequestStream(isMobile: true),
      };
    }
    return Column(
      children: [
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(
            color: _white,
            border: Border(bottom: BorderSide(color: _border)),
          ),
          child: Row(
            children: [
              Text(
                ['System Overview', 'Master Donor Management', 'Request Control Stream']
                    [_section],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _text,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () {
                  _loadOverview();
                  _loadDonors();
                  _loadRequests();
                },
                icon: const Icon(Icons.refresh, color: _muted),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_section) {
            0 => _buildOverview(isMobile: false),
            1 => _buildDonorGrid(isMobile: false),
            _ => _buildRequestStream(isMobile: false),
          },
        ),
      ],
    );
  }

  // ── Overview ────────────────────────────────────────────────────────────────

  Widget _buildOverview({required bool isMobile}) {
    if (_overviewLoading) return _skeletonOverview(isMobile: isMobile);

    final padding = isMobile ? _mobileContentPadding : const EdgeInsets.all(24);
    final sectionGap = isMobile ? 12.0 : 20.0;
    final blockGap = isMobile ? 12.0 : 16.0;

    return RefreshIndicator(
      onRefresh: _loadOverview,
      color: _red,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        children: [
          if (_overviewError != null) ...[
            _connectionErrorCard(_overviewError!),
            SizedBox(height: sectionGap),
          ],
          if (_stats != null) _statsHeader(_stats!, compact: isMobile),
          if (_stats == null && _overviewError == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No statistics available yet.',
                    style: TextStyle(color: _muted)),
              ),
            ),
          SizedBox(height: sectionGap),
          if (!isMobile)
            LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth > 900;
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _bloodStockChart()),
                    SizedBox(width: blockGap),
                    Expanded(flex: 4, child: _timelineChart()),
                  ],
                );
              }
              return Column(
                children: [
                  _bloodStockChart(),
                  SizedBox(height: blockGap),
                  _timelineChart(),
                ],
              );
            })
          else ...[
            _bloodStockChart(),
            SizedBox(height: blockGap),
            _timelineChart(),
          ],
          SizedBox(height: blockGap),
          _heatmapCard(),
        ],
      ),
    );
  }

  Widget _connectionErrorCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _redLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _red.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.cloud_off, color: _redDark, size: 20),
              SizedBox(width: 8),
              Text(
                'Backend connection failed',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _redDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(fontSize: 13, color: _text)),
          const SizedBox(height: 8),
          Text(
            'API: ${ApiConfig.baseUrl}',
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              _loadOverview();
              _loadDonors();
              _loadRequests();
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry connection'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _redDark,
              side: const BorderSide(color: _red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsHeader(Map<String, dynamic> s, {bool compact = false}) {
    final chips = [
      ('Users', '${s['total_users']}'),
      ('Active Donors', '${s['active_donors']}'),
      ('Pending', '${s['pending_requests']}'),
      ('Fulfilled', '${s['fulfilled_requests']}'),
      ('Fulfilment', '${s['fulfilment_rate_pct']}%'),
    ];
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 20),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Wrap(
        spacing: compact ? 8 : 12,
        runSpacing: compact ? 6 : 8,
        children: chips
            .map((c) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _panel,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _border),
                  ),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13, color: _muted),
                      children: [
                        TextSpan(text: '${c.$1}: '),
                        TextSpan(
                          text: c.$2,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _bloodStockChart() {
    return _chartCard(
      title: 'Blood Stock Levels',
      subtitle: 'Active donor units by blood group',
      height: 280,
      child: _bloodStock.isEmpty
          ? const Center(child: Text('No stock data', style: TextStyle(color: _muted)))
          : BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (_bloodStock
                            .map((g) => g['active_units'] as int? ?? 0)
                            .fold<int>(0, (a, b) => a > b ? a : b) +
                        2)
                    .toDouble(),
                barTouchData: BarTouchData(enabled: true),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= _bloodStock.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _bloodStock[i]['blood_group']?.toString() ?? '',
                            style: const TextStyle(fontSize: 10, color: _muted),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: const TextStyle(fontSize: 10, color: _muted),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: _border, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(_bloodStock.length, (i) {
                  final units = _bloodStock[i]['active_units'] as int? ?? 0;
                  final critical = units <= 1;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: units.toDouble(),
                        color: critical ? _redDark : _red,
                        width: 18,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                    ],
                  );
                }),
              ),
            ),
    );
  }

  Widget _timelineChart() {
    return _chartCard(
      title: 'Request vs. Fulfillment',
      subtitle: 'Last 30 days',
      height: 280,
      child: _timeline.isEmpty
          ? const Center(
              child: Text('No timeline data', style: TextStyle(color: _muted)))
          : LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: _border, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 5,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= _timeline.length || i % 5 != 0) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          _timeline[i]['label']?.toString().split(' ').last ?? '',
                          style: const TextStyle(fontSize: 9, color: _muted),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: const TextStyle(fontSize: 10, color: _muted),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(
                      _timeline.length,
                      (i) => FlSpot(
                        i.toDouble(),
                        (_timeline[i]['requests_created'] as num?)?.toDouble() ?? 0,
                      ),
                    ),
                    isCurved: true,
                    color: _red,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: _redLight.withValues(alpha: 0.5),
                    ),
                  ),
                  LineChartBarData(
                    spots: List.generate(
                      _timeline.length,
                      (i) => FlSpot(
                        i.toDouble(),
                        (_timeline[i]['requests_fulfilled'] as num?)?.toDouble() ?? 0,
                      ),
                    ),
                    isCurved: true,
                    color: const Color(0xFF16A34A),
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _heatmapCard() {
    return _chartCard(
      title: 'Geographic Emergency Density',
      subtitle: 'Active request volumes by coordinate sector',
      height: null,
      child: _heatmap.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                  child: Text('No active emergency clusters',
                      style: TextStyle(color: _muted))),
            )
          : Column(
              children: _heatmap.take(8).map((s) {
                final count = s['count'] as int? ?? 0;
                final critical = s['critical'] as int? ?? 0;
                final intensity = (count / 10).clamp(0.1, 1.0);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(s['sector']?.toString() ?? '',
                            style: const TextStyle(
                                fontSize: 12, color: _text)),
                      ),
                      Expanded(
                        flex: 4,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: intensity,
                            minHeight: 10,
                            backgroundColor: _panel,
                            color: critical > 0 ? _redDark : _red,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('$count req',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _red)),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _chartCard({
    required String title,
    required String subtitle,
    required Widget child,
    double? height,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15, color: _text)),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: _muted)),
          const SizedBox(height: 16),
          if (height != null) SizedBox(height: height, child: child) else child,
        ],
      ),
    );
  }

  // ── Donor grid ──────────────────────────────────────────────────────────────

  Widget _buildDonorGrid({required bool isMobile}) {
    return Column(
      children: [
        _tableToolbar(
          searchCtrl: _donorSearchCtrl,
          hint: 'Search donors by name, phone, email…',
          bloodFilter: _donorBloodFilter,
          isMobile: isMobile,
          onBloodChanged: (v) {
            setState(() { _donorBloodFilter = v; _donorPage = 1; });
            _loadDonors();
          },
          onSearch: () {
            setState(() {
              _donorSearch = _donorSearchCtrl.text.trim();
              _donorPage = 1;
            });
            _loadDonors();
          },
        ),
        if (_donorsError != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _connectionErrorCard(_donorsError!),
          ),
        ],
        Expanded(
          child: _donorsLoading
              ? _skeletonTable()
              : isMobile
                  ? _mobileDonorList()
                  : _dataTable(
                  columns: const [
                    'ID',
                    'Name',
                    'Phone',
                    'Blood',
                    'GPS',
                    'Donations',
                    'Next Eligible',
                    '',
                  ],
                  rows: _donors.map((d) {
                    final locked = d['is_locked'] as bool? ?? false;
                    return [
                      '#${d['donor_id']}',
                      d['full_name']?.toString() ?? '—',
                      d['phone_number']?.toString() ?? '—',
                      d['blood_group']?.toString() ?? '—',
                      '${(d['gps_latitude'] as num?)?.toStringAsFixed(2)}, '
                          '${(d['gps_longitude'] as num?)?.toStringAsFixed(2)}',
                      '${d['lifetime_donations'] ?? 0}',
                      locked
                          ? 'Deferred'
                          : (d['next_eligible_date']?.toString().split('T').first ??
                              'Eligible'),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            size: 18, color: _red),
                        onPressed: () => _openDonorEditor(d),
                      ),
                    ];
                  }).toList(),
                ),
        ),
        _pagination(_donorPage, _donorTotal, 12, (p) {
          setState(() => _donorPage = p);
          _loadDonors();
        }),
      ],
    );
  }

  // ── Request stream ──────────────────────────────────────────────────────────

  Widget _buildRequestStream({required bool isMobile}) {
    return Column(
      children: [
        _tableToolbar(
          searchCtrl: _requestSearchCtrl,
          hint: 'Search by recipient or blood group…',
          bloodFilter: _requestBloodFilter,
          statusFilter: _requestStatusFilter,
          isMobile: isMobile,
          onBloodChanged: (v) {
            setState(() { _requestBloodFilter = v; _requestPage = 1; });
            _loadRequests();
          },
          onStatusChanged: (v) {
            setState(() { _requestStatusFilter = v; _requestPage = 1; });
            _loadRequests();
          },
          onSearch: () {
            setState(() {
              _requestSearch = _requestSearchCtrl.text.trim();
              _requestPage = 1;
            });
            _loadRequests();
          },
        ),
        if (_requestsError != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _connectionErrorCard(_requestsError!),
          ),
        ],
        Expanded(
          child: _requestsLoading
              ? _skeletonTable()
              : isMobile
                  ? _mobileRequestList()
                  : _dataTable(
                  columns: const [
                    'ID',
                    'Recipient',
                    'Blood',
                    'Urgency',
                    'Location',
                    'Radius',
                    'Status',
                    '',
                  ],
                  rows: _requests.map((r) {
                    return [
                      '#${r['request_id']}',
                      r['recipient_name']?.toString() ?? '—',
                      r['blood_group_needed']?.toString() ?? '—',
                      r['urgency_level']?.toString() ?? '—',
                      r['hospital_location']?.toString() ?? '—',
                      '${r['current_radius_km']} km',
                      _statusChip(r['status']?.toString() ?? ''),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            size: 18, color: _red),
                        onPressed: () => _openRequestEditor(r),
                      ),
                    ];
                  }).toList(),
                ),
        ),
        _pagination(_requestPage, _requestTotal, 12, (p) {
          setState(() => _requestPage = p);
          _loadRequests();
        }),
      ],
    );
  }

  Widget _statusChip(String status) {
    Color bg = _panel;
    Color fg = _text;
    if (status == 'Fulfilled') {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF166534);
    } else if (status == 'Pending') {
      bg = _redLight;
      fg = _redDark;
    } else if (status == 'Unfulfilled' || status == 'Expired') {
      bg = const Color(0xFFFEE2E2);
      fg = _redDark;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(status,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  Widget _mobileDonorList() {
    if (_donors.isEmpty) {
      return const Center(child: Text('No donors found.', style: TextStyle(color: _muted)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _donors.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final d = _donors[i];
        return Card(
          child: ListTile(
            title: Text(d['full_name']?.toString() ?? '—',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${d['blood_group']} · ${d['phone_number'] ?? '—'}\n'
              'Donations: ${d['lifetime_donations'] ?? 0}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit_outlined, color: _red),
              onPressed: () => _openDonorEditor(d),
            ),
          ),
        );
      },
    );
  }

  Widget _mobileRequestList() {
    if (_requests.isEmpty) {
      return const Center(child: Text('No requests found.', style: TextStyle(color: _muted)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = _requests[i];
        return Card(
          child: ListTile(
            title: Text(r['recipient_name']?.toString() ?? '—',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '#${r['request_id']} · ${r['blood_group_needed']} · ${r['urgency_level']}\n'
              '${r['hospital_location']}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit_outlined, color: _red),
              onPressed: () => _openRequestEditor(r),
            ),
          ),
        );
      },
    );
  }

  Widget _tableToolbar({
    required TextEditingController searchCtrl,
    required String hint,
    required String bloodFilter,
    required VoidCallback onSearch,
    required ValueChanged<String> onBloodChanged,
    bool isMobile = false,
    String? statusFilter,
    ValueChanged<String>? onStatusChanged,
  }) {
    if (isMobile) {
      return Container(
        padding: const EdgeInsets.all(12),
        color: _white,
        child: Column(
          children: [
            TextField(
              controller: searchCtrl,
              decoration: InputDecoration(
                hintText: hint,
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  onPressed: onSearch,
                ),
              ),
              onSubmitted: (_) => onSearch(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: _filterDropdown(
                        'Blood', bloodFilter, _bloodGroups, onBloodChanged)),
                if (statusFilter != null && onStatusChanged != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                      child: _filterDropdown('Status', statusFilter,
                          _requestStatuses, onStatusChanged)),
                ],
              ],
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      color: _white,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: searchCtrl,
              decoration: InputDecoration(
                hintText: hint,
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  onPressed: onSearch,
                ),
              ),
              onSubmitted: (_) => onSearch(),
            ),
          ),
          const SizedBox(width: 12),
          _filterDropdown('Blood', bloodFilter, _bloodGroups, onBloodChanged),
          if (statusFilter != null && onStatusChanged != null) ...[
            const SizedBox(width: 12),
            _filterDropdown(
                'Status', statusFilter, _requestStatuses, onStatusChanged),
          ],
        ],
      ),
    );
  }

  Widget _filterDropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(8),
        color: _panel,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _dataTable({
    required List<String> columns,
    required List<List<dynamic>> rows,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(_panel),
          columns: columns
              .map((c) => DataColumn(
                    label: Text(c,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: _text)),
                  ))
              .toList(),
          rows: rows.isEmpty
              ? [
                  DataRow(
                    cells: List.generate(
                      columns.length,
                      (_) => const DataCell(Text('No records')),
                    ),
                  ),
                ]
              : rows
                  .map((cells) => DataRow(
                        cells: cells
                            .map((c) => DataCell(
                                  c is Widget
                                      ? c
                                      : Text(c.toString(),
                                          style: const TextStyle(fontSize: 12)),
                                ))
                            .toList(),
                      ))
                  .toList(),
        ),
      ),
    );
  }

  Widget _pagination(int page, int total, int limit, ValueChanged<int> onPage) {
    final pages = (total / limit).ceil().clamp(1, 999);
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: page > 1 ? () => onPage(page - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text('Page $page of $pages  ($total records)',
              style: const TextStyle(fontSize: 12, color: _muted)),
          IconButton(
            onPressed: page < pages ? () => onPage(page + 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  // ── Skeletons ───────────────────────────────────────────────────────────────

  Widget _skeletonOverview({required bool isMobile}) {
    final padding = isMobile ? _mobileContentPadding : const EdgeInsets.all(24);
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      children: [
        _shimmerBox(height: isMobile ? 72 : 80),
        SizedBox(height: isMobile ? 12 : 16),
        if (isMobile) ...[
          _shimmerBox(height: 240),
          const SizedBox(height: 12),
          _shimmerBox(height: 220),
        ] else
          Row(
            children: [
              Expanded(child: _shimmerBox(height: 280)),
              const SizedBox(width: 16),
              Expanded(child: _shimmerBox(height: 280)),
            ],
          ),
        SizedBox(height: isMobile ? 12 : 16),
        _shimmerBox(height: isMobile ? 120 : 160),
      ],
    );
  }

  Widget _skeletonTable() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 8,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _shimmerBox(height: 44),
      ),
    );
  }

  Widget _shimmerBox({required double height}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 0.7),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: _skeleton.withValues(alpha: value),
            borderRadius: BorderRadius.circular(10),
          ),
        );
      },
      onEnd: () {
        if (mounted) setState(() {});
      },
    );
  }
}

// ── Donor edit sheet ──────────────────────────────────────────────────────────

class _DonorEditSheet extends StatefulWidget {
  final Map<String, dynamic> donor;
  final void Function(Map<String, dynamic>) onSave;
  final VoidCallback onClose;
  const _DonorEditSheet({
    required this.donor,
    required this.onSave,
    required this.onClose,
  });

  @override
  State<_DonorEditSheet> createState() => _DonorEditSheetState();
}

class _DonorEditSheetState extends State<_DonorEditSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late String _blood;
  bool _forceEligible = false;
  bool _forceDeferred = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl =
        TextEditingController(text: widget.donor['full_name']?.toString());
    _phoneCtrl =
        TextEditingController(text: widget.donor['phone_number']?.toString());
    _blood = widget.donor['blood_group']?.toString() ?? 'O+';
    _forceDeferred = widget.donor['is_locked'] as bool? ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 400,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Edit Donor Record',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: _text)),
                  ),
                  IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Full Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone Number'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _blood,
                decoration: const InputDecoration(labelText: 'Blood Group'),
                items: _bloodGroups
                    .where((b) => b != 'ALL')
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _blood = v);
                },
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                title: const Text('Force Eligible (bypass 60-day lockout)'),
                subtitle: const Text('Clears deferral immediately',
                    style: TextStyle(fontSize: 11)),
                value: _forceEligible,
                activeThumbColor: _red,
                onChanged: (v) => setState(() {
                  _forceEligible = v;
                  if (_forceEligible) _forceDeferred = false;
                }),
              ),
              SwitchListTile(
                title: const Text('Enforce Deferral'),
                subtitle: const Text('Lock donor for 60 days',
                    style: TextStyle(fontSize: 11)),
                value: _forceDeferred,
                activeThumbColor: _red,
                onChanged: (v) => setState(() {
                  _forceDeferred = v;
                  if (_forceDeferred) _forceEligible = false;
                }),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => widget.onSave({
                  'full_name': _nameCtrl.text.trim(),
                  'phone_number': _phoneCtrl.text.trim(),
                  'blood_group': _blood,
                  'force_eligible': _forceEligible,
                  'force_deferred': _forceDeferred,
                }),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _red,
                  foregroundColor: _white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Save & Sync to Database',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Request edit sheet ───────────────────────────────────────────────────────

class _RequestEditSheet extends StatefulWidget {
  final Map<String, dynamic> request;
  final void Function(Map<String, dynamic>) onSave;
  final VoidCallback onClose;
  const _RequestEditSheet({
    required this.request,
    required this.onSave,
    required this.onClose,
  });

  @override
  State<_RequestEditSheet> createState() => _RequestEditSheetState();
}

class _RequestEditSheetState extends State<_RequestEditSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _latCtrl;
  late final TextEditingController _lngCtrl;
  late final TextEditingController _radiusCtrl;
  late String _blood;
  late String _status;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
        text: widget.request['recipient_name']?.toString());
    _latCtrl = TextEditingController(
        text: widget.request['request_latitude']?.toString());
    _lngCtrl = TextEditingController(
        text: widget.request['request_longitude']?.toString());
    _radiusCtrl = TextEditingController(
        text: widget.request['current_radius_km']?.toString());
    _blood = widget.request['blood_group_needed']?.toString() ?? 'O+';
    _status = widget.request['status']?.toString() ?? 'Pending';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _radiusCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 400,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                        'Edit Request #${widget.request['request_id']}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: _text)),
                  ),
                  IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameCtrl,
                decoration:
                    const InputDecoration(labelText: 'Recipient Name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _blood,
                decoration:
                    const InputDecoration(labelText: 'Blood Group Urgency'),
                items: _bloodGroups
                    .where((b) => b != 'ALL')
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _blood = v);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _status,
                decoration:
                    const InputDecoration(labelText: 'Status Override'),
                items: _requestStatuses
                    .where((s) => s != 'ALL')
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _status = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _radiusCtrl,
                decoration: const InputDecoration(
                    labelText: 'Geofence Radius (km)', hintText: '5 - 50'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _latCtrl,
                decoration:
                    const InputDecoration(labelText: 'Hospital Latitude'),
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _lngCtrl,
                decoration:
                    const InputDecoration(labelText: 'Hospital Longitude'),
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => widget.onSave({
                  'recipient_name': _nameCtrl.text.trim(),
                  'blood_group': _blood,
                  'status': _status,
                  'radius': _radiusCtrl.text.trim(),
                  'lat': _latCtrl.text.trim(),
                  'lng': _lngCtrl.text.trim(),
                }),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _red,
                  foregroundColor: _white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Save & Sync to Database',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
