import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api_config.dart';
import '../admin_dashboard_screen.dart';

const _white = Color(0xFFFFFFFF);
const _red = Color(0xFFDC2626);
const _redDark = Color(0xFFB91C1C);
const _text = Color(0xFF1E293B);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);

/// Discrete admin login gateway — opened from the standard Sign-In screen only.
class AdminGatewaySheet {
  AdminGatewaySheet._();

  static Future<void> show(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 600;
    if (wide) {
      return showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => Dialog(
          backgroundColor: _white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: const Padding(
              padding: EdgeInsets.all(28),
              child: _AdminGatewayForm(),
            ),
          ),
        ),
      );
    }
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: const _AdminGatewayForm(),
      ),
    );
  }
}

class _AdminGatewayForm extends StatefulWidget {
  const _AdminGatewayForm();

  @override
  State<_AdminGatewayForm> createState() => _AdminGatewayFormState();
}

class _AdminGatewayFormState extends State<_AdminGatewayForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/login'),
        headers: ApiConfig.jsonHeaders,
        body: json.encode({
          'email': _emailCtrl.text.trim().toLowerCase(),
          'password': _passCtrl.text,
        }),
      ).timeout(const Duration(seconds: 12));

      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final token = (data['access_token'] as String? ?? '').trim();
        final name = data['full_name'] as String? ?? 'Administrator';
        if (token.isEmpty) {
          setState(() => _error = 'No access token returned.');
          return;
        }
        Navigator.of(context).pop();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                AdminDashboardScreen(token: token, adminName: name),
          ),
        );
        return;
      }
      try {
        final body = json.decode(res.body) as Map<String, dynamic>;
        setState(() => _error = body['detail']?.toString() ?? 'Access denied.');
      } catch (_) {
        setState(() => _error = 'Admin login failed.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Cannot reach backend at ${ApiConfig.baseUrl}. Start uvicorn on port 5000 and ensure MySQL (XAMPP) is running.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(100),
            ),
            child: const Text(
              'ADMIN GATEWAY',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _redDark,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Administrator Sign-In',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _text,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Restricted access — not available via public registration.',
            style: TextStyle(fontSize: 12, color: _muted),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _emailCtrl,
            decoration: InputDecoration(
              labelText: 'Admin email',
              prefixIcon: const Icon(Icons.admin_panel_settings_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            validator: (v) =>
                (v == null || !v.contains('@')) ? 'Enter admin email' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onFieldSubmitted: (_) => _submit(),
            validator: (v) =>
                (v == null || v.length < 6) ? 'Enter password' : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _border),
              ),
              child: Text(_error!,
                  style: const TextStyle(fontSize: 12, color: _redDark)),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: _white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _white),
                  )
                : const Text('Enter Command Center',
                    style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to standard sign-in',
                style: TextStyle(color: _muted)),
          ),
        ],
      ),
    );
  }
}
