import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'home_hub.dart';
import 'login_screen.dart';
import 'web_app_shell.dart';

/// Profile completion screen for Google Sign-In users.
///
/// Blood group and phone number are required before entering the app.
/// Users can go back to the login screen if they want to switch accounts.
class CompleteProfileScreen extends StatefulWidget {
  final String token;
  final String userName;

  const CompleteProfileScreen({
    super.key,
    required this.token,
    required this.userName,
  });

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();

  String _selectedBloodGroup = 'O+';
  DateTime? _selectedDob;
  bool _loading = false;
  String? _error;

  static const _bloodGroups = [
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'
  ];

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25),
      firstDate: DateTime(now.year - 70),
      lastDate: DateTime(now.year - 16),
    );
    if (picked != null) setState(() => _selectedDob = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    final body = <String, dynamic>{
      'phone_number': _phoneCtrl.text.trim(),
      'blood_group': _selectedBloodGroup,
      if (_weightCtrl.text.isNotEmpty)
        'weight_kg': double.tryParse(_weightCtrl.text.trim()),
      if (_selectedDob != null)
        'dob':
            '${_selectedDob!.year}-${_selectedDob!.month.toString().padLeft(2, '0')}-${_selectedDob!.day.toString().padLeft(2, '0')}',
    };

    try {
      final res = await http
          .put(
            Uri.parse('${ApiConfig.baseUrl}/api/auth/complete-profile'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${widget.token}',
            },
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 12));

      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final newToken = data['access_token'] as String? ?? widget.token;
        final role = data['role'] as String? ?? 'Unassigned';
        final needsRoleSelection =
            data['needs_role_selection'] as bool? ?? role == 'Unassigned';

        final destination = kIsWeb
            ? WebAppShell(
                token: newToken,
                role: role,
                userName: widget.userName,
                needsRoleSelection: needsRoleSelection,
              )
            : HomeHub(
                token: newToken,
                role: role,
                userName: widget.userName,
                needsRoleSelection: needsRoleSelection,
              );

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => destination),
        );
      } else {
        final data = json.decode(res.body) as Map<String, dynamic>;
        setState(() => _error = data['detail']?.toString() ?? 'Update failed.');
      }
    } catch (_) {
      setState(() => _error = 'Network error. Check server connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goBackToLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBackToLogin();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Complete Your Profile'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to login',
            onPressed: _goBackToLogin,
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ──────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.red[800]!, Colors.red[500]!],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.account_circle,
                            color: Colors.white, size: 36),
                        const SizedBox(height: 8),
                        Text(
                          'Hi, ${widget.userName.split(' ').first}!',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Your Google account is linked.\n'
                          'Please complete your medical profile to continue.',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Fields ───────────────────────────────────────────────
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number  *',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty)
                            ? 'Phone number is required'
                            : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedBloodGroup,
                    decoration: const InputDecoration(
                      labelText: 'Blood Group  *',
                      prefixIcon: Icon(Icons.bloodtype),
                    ),
                    items: _bloodGroups
                        .map((g) =>
                            DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _selectedBloodGroup = v!),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _weightCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Weight (kg)  — optional',
                      prefixIcon: Icon(Icons.monitor_weight_outlined),
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.grey[400]!),
                    ),
                    leading: const Icon(Icons.cake_outlined),
                    title: Text(
                      _selectedDob == null
                          ? 'Date of Birth — optional'
                          : '${_selectedDob!.day}/${_selectedDob!.month}/${_selectedDob!.year}',
                      style: TextStyle(
                          color: _selectedDob == null
                              ? Colors.grey[600]
                              : Colors.black),
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: _pickDob,
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red[200]!)),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Colors.red[800], fontSize: 12)),
                    ),
                  ],
                  const SizedBox(height: 28),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Save & Enter App',
                            style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
