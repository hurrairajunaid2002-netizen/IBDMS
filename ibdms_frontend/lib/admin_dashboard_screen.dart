import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'login_screen.dart';

/// Full Admin Management Panel — v3.0
/// Fetches live stats, user list, and unfulfilled alerts from the backend.
/// Accessible only to users with role == 'Administrator'.
class AdminDashboardScreen extends StatefulWidget {
  final String token;
  const AdminDashboardScreen({super.key, required this.token});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // ── Stats ─────────────────────────────────────────────────────────────────
  Map<String, dynamic>? _stats;
  bool _statsLoading = true;

  // ── Users ─────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _users = [];
  bool _usersLoading = true;
  final int _usersPage = 1;

  // ── Unfulfilled alerts ────────────────────────────────────────────────────
  List<Map<String, dynamic>> _unfulfilled = [];
  bool _unfulfilledLoading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadStats(), _loadUsers(), _loadUnfulfilled()]);
  }

  // ── API calls ─────────────────────────────────────────────────────────────

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json',
      };

  Future<void> _loadStats() async {
    setState(() => _statsLoading = true);
    try {
      final res = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/api/admin/stats'),
              headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (mounted && res.statusCode == 200) {
        setState(() => _stats =
            json.decode(res.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    if (mounted) setState(() => _statsLoading = false);
  }

  Future<void> _loadUsers() async {
    setState(() => _usersLoading = true);
    try {
      final res = await http
          .get(
              Uri.parse(
                  '${ApiConfig.baseUrl}/api/admin/users?page=$_usersPage&limit=30'),
              headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (mounted && res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        setState(() => _users = (data['users'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            []);
      }
    } catch (_) {}
    if (mounted) setState(() => _usersLoading = false);
  }

  Future<void> _loadUnfulfilled() async {
    setState(() => _unfulfilledLoading = true);
    try {
      final res = await http
          .get(
              Uri.parse(
                  '${ApiConfig.baseUrl}/api/admin/requests/unfulfilled'),
              headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (mounted && res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        setState(() => _unfulfilled = (data['requests'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            []);
      }
    } catch (_) {}
    if (mounted) setState(() => _unfulfilledLoading = false);
  }

  Future<void> _toggleUserAvailability(
      int userId, bool currentlyActive) async {
    final newStatus = currentlyActive ? 'Inactive' : 'Active';
    try {
      await http
          .put(
            Uri.parse(
                '${ApiConfig.baseUrl}/api/admin/users/$userId/override'),
            headers: _headers,
            body: json.encode({'availability_status': newStatus}),
          )
          .timeout(const Duration(seconds: 10));
      _loadUsers();
    } catch (_) {}
  }

  Future<void> _overrideRequest(int requestId, String newStatus) async {
    try {
      await http
          .put(
            Uri.parse(
                '${ApiConfig.baseUrl}/api/admin/requests/$requestId/override'),
            headers: _headers,
            body: json.encode({'status': newStatus}),
          )
          .timeout(const Duration(seconds: 10));
      _loadUnfulfilled();
    } catch (_) {}
  }

  void _logout() => Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.indigo.shade800,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: const Text('Admin Control Panel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh All',
            onPressed: _loadAll,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.bar_chart), text: 'Overview'),
            Tab(icon: Icon(Icons.people), text: 'Users'),
            Tab(icon: Icon(Icons.warning_amber), text: 'Alerts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildOverview(),
          _buildUserList(),
          _buildUnfulfilledAlerts(),
        ],
      ),
    );
  }

  // ── Tab 1: Overview ───────────────────────────────────────────────────────

  Widget _buildOverview() {
    if (_statsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final s = _stats;
    if (s == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('Could not load stats.'),
          ElevatedButton(onPressed: _loadStats, child: const Text('Retry')),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header card ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [Colors.indigo.shade800, Colors.indigo.shade500]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.admin_panel_settings,
                      color: Colors.white, size: 32),
                  const SizedBox(height: 8),
                  const Text('IBDMS System Overview',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  Text(
                    'Fulfilment rate: ${s['fulfilment_rate_pct']}%',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Stat grid ────────────────────────────────────────────────
            _statGrid(s),
            const SizedBox(height: 20),

            // ── Quick actions ─────────────────────────────────────────────
            Text('Quick Actions',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700])),
            const SizedBox(height: 10),
            _actionButton(
              'View Unfulfilled Alerts',
              Icons.warning_amber_outlined,
              Colors.orange[700]!,
              () => _tabCtrl.animateTo(2),
            ),
            const SizedBox(height: 8),
            _actionButton(
              'Manage Users',
              Icons.people_outline,
              Colors.blue[700]!,
              () => _tabCtrl.animateTo(1),
            ),
            const SizedBox(height: 8),
            _actionButton(
              'Logout',
              Icons.logout,
              Colors.red[700]!,
              _logout,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statGrid(Map<String, dynamic> s) {
    final items = [
      _StatData('Total Users', '${s['total_users']}',
          Icons.people, Colors.blue.shade600),
      _StatData('Donor Profiles', '${s['total_donor_profiles']}',
          Icons.volunteer_activism, Colors.red.shade600),
      _StatData('Active Donors', '${s['active_donors']}',
          Icons.circle, Colors.green.shade600),
      _StatData('Pending Requests', '${s['pending_requests']}',
          Icons.pending_outlined, Colors.orange.shade600),
      _StatData('Fulfilled', '${s['fulfilled_requests']}',
          Icons.check_circle_outline, Colors.green.shade700),
      _StatData('Unfulfilled', '${s['unfulfilled_requests']}',
          Icons.warning_outlined, Colors.red.shade700),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.6,
      children: items.map((d) => _StatCard(data: d)).toList(),
    );
  }

  Widget _actionButton(
          String label, IconData icon, Color color, VoidCallback onTap) =>
      SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
          icon: Icon(icon, size: 18),
          label: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      );

  // ── Tab 2: Users ──────────────────────────────────────────────────────────

  Widget _buildUserList() {
    if (_usersLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_users.isEmpty) {
      return const Center(child: Text('No users found.'));
    }
    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _users.length,
        separatorBuilder: (context, i) => const SizedBox(height: 6),
        itemBuilder: (_, i) => _UserCard(
          user: _users[i],
          onToggle: () => _toggleUserAvailability(
            _users[i]['user_id'] as int,
            _users[i]['donor_availability'] == 'Active',
          ),
        ),
      ),
    );
  }

  // ── Tab 3: Unfulfilled Alerts ─────────────────────────────────────────────

  Widget _buildUnfulfilledAlerts() {
    if (_unfulfilledLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_unfulfilled.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_outline,
              size: 56, color: Colors.green),
          const SizedBox(height: 12),
          const Text('No unfulfilled alerts.'),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadUnfulfilled,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _unfulfilled.length,
        separatorBuilder: (context, i) => const SizedBox(height: 6),
        itemBuilder: (_, i) => _UnfulfilledCard(
          alert: _unfulfilled[i],
          onOverride: (String status) =>
              _overrideRequest(_unfulfilled[i]['request_id'] as int, status),
        ),
      ),
    );
  }
}


// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatData(this.label, this.value, this.icon, this.color);
}

class _StatCard extends StatelessWidget {
  final _StatData data;
  const _StatCard({required this.data});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
                color: Colors.grey.withAlpha(15),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(data.icon, color: data.color, size: 22),
            const SizedBox(height: 6),
            Text(data.value,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: data.color)),
            Text(data.label,
                style:
                    TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],
        ),
      );
}

class _UserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onToggle;
  const _UserCard({required this.user, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final isDonor = user['has_donor_profile'] as bool? ?? false;
    final availability =
        user['donor_availability'] as String? ?? 'N/A';
    final role = user['role'] as String? ?? '';
    final isAdmin = role == 'Administrator';

    return Card(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 1,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              isAdmin ? Colors.indigo[100] : Colors.red[100],
          child: Icon(
            isAdmin ? Icons.admin_panel_settings : Icons.person,
            color: isAdmin ? Colors.indigo[700] : Colors.red[700],
            size: 20,
          ),
        ),
        title: Text(user['full_name']?.toString() ?? '—',
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user['email']?.toString() ?? '',
                style: const TextStyle(fontSize: 11)),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  user['blood_group']?.toString() ?? '?',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800]),
                ),
              ),
              const SizedBox(width: 6),
              Text(role,
                  style:
                      TextStyle(fontSize: 10, color: Colors.grey[600])),
              if (isDonor) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: availability == 'Active'
                        ? Colors.green[50]
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    availability,
                    style: TextStyle(
                        fontSize: 10,
                        color: availability == 'Active'
                            ? Colors.green[700]
                            : Colors.grey[600]),
                  ),
                ),
              ],
            ]),
          ],
        ),
        trailing: isDonor && !isAdmin
            ? IconButton(
                icon: Icon(
                  availability == 'Active'
                      ? Icons.toggle_on
                      : Icons.toggle_off,
                  size: 28,
                  color: availability == 'Active'
                      ? Colors.green
                      : Colors.grey,
                ),
                onPressed: onToggle,
                tooltip: 'Toggle availability',
              )
            : null,
      ),
    );
  }
}

class _UnfulfilledCard extends StatelessWidget {
  final Map<String, dynamic> alert;
  final void Function(String) onOverride;
  const _UnfulfilledCard({required this.alert, required this.onOverride});

  @override
  Widget build(BuildContext context) {
    final bloodGroup = alert['blood_group_needed']?.toString() ?? '?';
    final urgency = alert['urgency_level']?.toString() ?? '';
    final radius = alert['current_radius_km'] ?? 50;

    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.red[100]!)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.red[50],
                shape: BoxShape.circle,
                border: Border.all(color: Colors.red, width: 1.5),
              ),
              child: Center(
                child: Text(bloodGroup,
                    style: TextStyle(
                        color: Colors.red[800],
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Request #${alert['request_id']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  Text('$urgency  •  Searched up to ${radius.toInt()} km',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[600])),
                  if (alert['created_at'] != null)
                    Text(
                      _timeAgo(alert['created_at']?.toString()),
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey[500]),
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: onOverride,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'Fulfilled', child: Text('Mark Fulfilled')),
                PopupMenuItem(value: 'Cancelled', child: Text('Cancel')),
                PopupMenuItem(value: 'Pending', child: Text('Reopen')),
              ],
              child: const Icon(Icons.more_vert),
            ),
          ],
        ),
      ),
    );
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }
}
