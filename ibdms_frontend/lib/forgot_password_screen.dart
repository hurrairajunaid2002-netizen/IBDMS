import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';

/// Two-step forgot-password flow:
///   Step 1 — User enters email → backend sends OTP.
///   Step 2 — User enters the 6-digit OTP + new password → backend resets.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  int _step = 1; // 1 = email entry, 2 = OTP + new password

  // Step 1
  final _emailCtrl = TextEditingController();

  // Step 2
  final _otpCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _loading = false;
  bool _obscurePass = true;
  String? _error;
  String? _info;
  String _submittedEmail = '';

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() { _loading = true; _error = null; _info = null; });

    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email}),
      ).timeout(const Duration(seconds: 12));

      if (!mounted) return;
      // Backend always returns 200 to prevent account enumeration.
      _submittedEmail = email;
      setState(() {
        _step = 2;
        _info = 'A 6-digit OTP has been sent to $email (valid 15 min).';
      });
    } catch (_) {
      setState(() => _error = 'Network error. Check server connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final otp = _otpCtrl.text.trim();
    final pass = _newPassCtrl.text;
    final confirm = _confirmPassCtrl.text;

    if (otp.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your email.');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (pass != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': _submittedEmail,
          'otp': otp,
          'new_password': pass,
        }),
      ).timeout(const Duration(seconds: 12));

      if (!mounted) return;
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password reset! You can now log in.')),
          );
          Navigator.pop(context);
        }
      } else {
        final data = json.decode(res.body) as Map<String, dynamic>;
        setState(() => _error = data['detail']?.toString() ?? 'Reset failed.');
      }
    } catch (_) {
      setState(() => _error = 'Network error. Check server connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icon + step indicator
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB71C1C).withAlpha(20),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _step == 1 ? Icons.email_outlined : Icons.lock_reset,
                    color: const Color(0xFFB71C1C),
                    size: 44,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _step == 1
                    ? 'Forgot your password?'
                    : 'Enter reset code',
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _step == 1
                    ? 'Enter your registered email address. We\'ll send a 6-digit OTP.'
                    : 'Check your inbox for the 6-digit code, then set a new password.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              if (_step == 1) ...[
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email_outlined),
                    hintText: 'you@example.com',
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _requestOtp(),
                ),
              ] else ...[
                // OTP field
                TextFormField(
                  controller: _otpCtrl,
                  decoration: InputDecoration(
                    labelText: '6-Digit OTP Code',
                    prefixIcon: const Icon(Icons.pin_outlined),
                    helperText: 'Sent to $_submittedEmail',
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(
                      fontSize: 22,
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _newPassCtrl,
                  decoration: InputDecoration(
                    labelText: 'New Password',
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
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmPassCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Confirm New Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  obscureText: _obscurePass,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _resetPassword(),
                ),
              ],

              // Messages
              if (_info != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Text(_info!,
                      style: TextStyle(color: Colors.blue[800], fontSize: 12)),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Text(_error!,
                      style: TextStyle(color: Colors.red[800], fontSize: 12)),
                ),
              ],

              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loading
                    ? null
                    : (_step == 1 ? _requestOtp : _resetPassword),
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(
                        _step == 1 ? 'Send Reset Code' : 'Reset Password',
                        style: const TextStyle(fontSize: 16),
                      ),
              ),
              if (_step == 2) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => setState(() {
                    _step = 1;
                    _error = null;
                    _info = null;
                  }),
                  child: const Text('← Back to email entry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
