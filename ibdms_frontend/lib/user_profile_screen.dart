import 'package:flutter/material.dart';
import 'api_config.dart';
import 'login_screen.dart';

/// User Profile & System Settings.
/// Includes server IP configuration for physical-device Wi-Fi deployments.
class UserProfileScreen extends StatefulWidget {
  final String token;
  final String role;
  final String userName;
  final bool embedInShell;

  const UserProfileScreen({
    super.key,
    required this.token,
    required this.role,
    required this.userName,
    this.embedInShell = false,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _ipCtrl = TextEditingController();
  bool _ipSaved = false;

  @override
  void initState() {
    super.initState();
    _ipCtrl.text = ApiConfig.currentServerIp;
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveServerIp() async {
    await ApiConfig.setServerIp(_ipCtrl.text);
    if (!mounted) return;
    setState(() => _ipSaved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Server IP updated: ${ApiConfig.baseUrl}'),
          duration: const Duration(seconds: 2)),
    );
  }

  void _logout() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'Donor':
        return Colors.blue[700]!;
      case 'Recipient':
        return Colors.red[700]!;
      default:
        return Colors.grey[700]!;
    }
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'Donor':
        return Icons.favorite;
      case 'Recipient':
        return Icons.local_hospital;
      default:
        return Icons.admin_panel_settings;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: widget.embedInShell ? null : AppBar(title: const Text('User Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile card
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: _roleColor(widget.role).withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_roleIcon(widget.role),
                          size: 38, color: _roleColor(widget.role)),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.userName,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _roleColor(widget.role).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: _roleColor(widget.role).withOpacity(0.4)),
                      ),
                      child: Text(
                        widget.role,
                        style: TextStyle(
                            color: _roleColor(widget.role),
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Role-based features card
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.role == 'Donor'
                          ? 'Donor Features'
                          : widget.role == 'Recipient'
                              ? 'Recipient Features'
                              : 'System Features',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    if (widget.role == 'Donor') ...[
                      _featureRow(Icons.notifications_active,
                          'Active Alerts Feed', 'Real-time matching requests'),
                      _featureRow(Icons.bloodtype, 'Blood Group Profile',
                          'Stored in donor registry'),
                      _featureRow(Icons.schedule, '56-Day Cooldown',
                          'Auto-tracked by system'),
                      _featureRow(Icons.location_on, 'GPS Radius Matching',
                          'Haversine proximity engine'),
                    ] else if (widget.role == 'Recipient') ...[
                      _featureRow(Icons.map, 'Emergency Map Search',
                          'Radial donor discovery'),
                      _featureRow(Icons.expand_outlined, 'Expanding Radius',
                          '5 → 15 → 30 → 50 km tiers'),
                      _featureRow(Icons.speed, 'Critical Urgency',
                          'Full-tier expansion enabled'),
                    ] else ...[
                      _featureRow(Icons.storage, 'Backend', 'FastAPI + MySQL'),
                      _featureRow(
                          Icons.security, 'Auth', 'JWT Role-Based Access'),
                      _featureRow(Icons.calculate, 'Matching Engine',
                          'Haversine + 56-day filter'),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Network settings card
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.settings_ethernet,
                            size: 18, color: Colors.grey),
                        const SizedBox(width: 8),
                        const Text('Network Settings',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Enter your PC\'s LAN IP for physical device use.\nBackend must run: uvicorn main:app --host 0.0.0.0 --port 5000',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ipCtrl,
                            decoration: InputDecoration(
                              labelText: 'Server IP Address',
                              hintText: 'e.g. 192.168.1.100',
                              prefixIcon: const Icon(Icons.dns_outlined),
                              suffixText: ':5000',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              isDense: true,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (_) =>
                                setState(() => _ipSaved = false),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _saveServerIp,
                          style: ElevatedButton.styleFrom(
                              minimumSize: const Size(64, 48)),
                          child: Icon(_ipSaved ? Icons.check : Icons.save,
                              size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.link, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 6),
                          Text(
                            'Active: ${ApiConfig.baseUrl}',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // System info
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  _infoTile(
                      Icons.info_outline, 'App Version', 'IBDMS v1.0.0 FYP'),
                  const Divider(height: 1),
                  _infoTile(Icons.architecture, 'Stack',
                      'Flutter 3 + FastAPI + MySQL'),
                  const Divider(height: 1),
                  _infoTile(Icons.map_outlined, 'Map Engine',
                      'OpenStreetMap + flutter_map'),
                  const Divider(height: 1),
                  _infoTile(Icons.calculate_outlined, 'Matching',
                      'Haversine Radial (5→15→30→50 km)'),
                ],
              ),
            ),

            const SizedBox(height: 24),

            OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text('Logout',
                  style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _featureRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 18, color: Colors.grey[600]),
      title: Text(label,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600)),
      trailing: Text(value,
          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
    );
  }
}
