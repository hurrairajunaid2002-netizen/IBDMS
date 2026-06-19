import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

/// Universal Registration Screen — v3.0
///
/// All users are registered as universal entities.  There is no role selector.
/// Blood Group is mandatory for every account so the dual-mode system
/// (Request Blood ↔ Donate Blood) works immediately after signup.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();

  String _selectedBloodGroup = 'O+';
  DateTime? _selectedDob;

  bool _loading = false;
  bool _obscurePass = true;
  String? _errorMessage;
  String? _successMessage;

  static const _bloodGroups = [
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'
  ];

  // RFC 5322-like email regex — mirrors backend validation.
  static final _emailRe = RegExp(
    r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
  );

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
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
      helpText: 'Select Date of Birth',
    );
    if (picked != null) setState(() => _selectedDob = picked);
  }

  Future<Position?> _getLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
      return null;
    }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.medium)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDob == null) {
      setState(() => _errorMessage = 'Please select your date of birth.');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final pos = await _getLocation();

    final body = <String, dynamic>{
      'full_name': _nameCtrl.text.trim(),
      'email': _emailCtrl.text.trim().toLowerCase(),
      'password': _passCtrl.text,
      'phone_number': _phoneCtrl.text.trim(),
      'blood_group': _selectedBloodGroup,
      'weight_kg': double.tryParse(_weightCtrl.text.trim()) ?? 70.0,
      'dob':
          '${_selectedDob!.year}-${_selectedDob!.month.toString().padLeft(2, '0')}-${_selectedDob!.day.toString().padLeft(2, '0')}',
      'gps_latitude': pos?.latitude ?? 24.8607,
      'gps_longitude': pos?.longitude ?? 67.0011,
    };

    try {
      final res = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (res.statusCode == 201) {
        setState(() => _successMessage =
            'Account created! You can now log in with your email and password.');
      } else {
        final data = json.decode(res.body) as Map<String, dynamic>;
        setState(() => _errorMessage =
            (data['detail'] as String?) ?? 'Registration failed.');
      }
    } catch (_) {
      setState(() => _errorMessage =
          'Network error. Verify server at ${ApiConfig.baseUrl}.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Create Account'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red[100]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.red[800], size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'One account. Switch freely between requesting blood and donating.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.red[800]),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Personal details ──────────────────────────────────────
                _section('Personal Information'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v == null || v.trim().length < 3)
                      ? 'Enter your full name'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email_outlined),
                    hintText: 'you@example.com',
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Email is required.';
                    if (!_emailRe.hasMatch(v.trim())) {
                      return 'Enter a valid email address (e.g. you@example.com)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    prefixIcon: Icon(Icons.phone_outlined),
                    hintText: '+92 300 0000000',
                  ),
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Phone number is required.';
                    }
                    final digits =
                        v.replaceAll(RegExp(r'[\s\-\+\(\)]'), '');
                    if (!RegExp(r'^\d+$').hasMatch(digits) ||
                        digits.length < 7) {
                      return 'Enter a valid phone number.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // ── Medical profile ───────────────────────────────────────
                _section('Medical Profile (Universal)'),
                const SizedBox(height: 4),
                Text(
                  'Required for both blood request and donation matching.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedBloodGroup,
                  decoration: const InputDecoration(
                    labelText: 'Blood Group',
                    prefixIcon: Icon(Icons.bloodtype),
                  ),
                  items: _bloodGroups
                      .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedBloodGroup = v!),
                  validator: (v) =>
                      v == null ? 'Please select your blood group' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _weightCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Weight (kg)  — optional',
                    prefixIcon: Icon(Icons.monitor_weight_outlined),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final val = double.tryParse(v.trim());
                    if (val == null || val < 30) {
                      return 'Enter a realistic weight (≥ 30 kg)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                        color: _selectedDob == null
                            ? Colors.grey[400]!
                            : Colors.green[400]!),
                  ),
                  leading: const Icon(Icons.cake_outlined),
                  title: Text(
                    _selectedDob == null
                        ? 'Select Date of Birth  *'
                        : '${_selectedDob!.day}/${_selectedDob!.month}/${_selectedDob!.year}',
                    style: TextStyle(
                      color: _selectedDob == null
                          ? Colors.grey[600]
                          : Colors.black,
                    ),
                  ),
                  trailing: Icon(
                    Icons.calendar_today,
                    color: _selectedDob == null ? null : Colors.green,
                  ),
                  onTap: _pickDob,
                ),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.location_on_outlined,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'GPS captured automatically for local donor matching.',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),

                // ── Password ──────────────────────────────────────────────
                _section('Security'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passCtrl,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePass
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                  obscureText: _obscurePass,
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      (v == null || v.length < 6) ? 'Min 6 characters' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmPassCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  obscureText: _obscurePass,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _register(),
                  validator: (v) =>
                      v != _passCtrl.text ? 'Passwords do not match' : null,
                ),

                // ── Messages ──────────────────────────────────────────────
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  _messageBox(_errorMessage!, isError: true),
                ],
                if (_successMessage != null) ...[
                  const SizedBox(height: 14),
                  _messageBox(_successMessage!, isError: false),
                ],

                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loading ? null : _register,
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Create Account',
                          style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Already have an account? Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.red[800],
            fontSize: 13,
          ),
        ),
      );

  Widget _messageBox(String msg, {required bool isError}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isError ? Colors.red[50] : Colors.green[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isError ? Colors.red[200]! : Colors.green[200]!,
          ),
        ),
        child: Text(
          msg,
          style: TextStyle(
            color: isError ? Colors.red[800] : Colors.green[800],
            fontSize: 12,
          ),
        ),
      );
}
