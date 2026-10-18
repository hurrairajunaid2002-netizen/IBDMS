import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'web_signup_screen.dart';
import 'web_app_shell.dart';
import 'admin_dashboard_screen.dart';
import 'widgets/admin_gateway_sheet.dart';
import 'complete_profile_screen.dart';
import 'forgot_password_screen.dart';

const _red = Color(0xFFDC2626);
const _redDark = Color(0xFFB91C1C);
const _slate900 = Color(0xFF0F172A);
const _slate700 = Color(0xFF334155);
const _slate500 = Color(0xFF64748B);
const _slate100 = Color(0xFFF1F5F9);

// File-scope so both _WebLoginScreenState and _LoginForm can access it.
final _emailRe = RegExp(
    r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$');

class WebLoginScreen extends StatefulWidget {
  const WebLoginScreen({super.key});

  @override
  State<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends State<WebLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loading = false;
  bool _googleLoading = false;
  bool _obscurePass = true;
  String? _error;

  static const _webClientId =
      '162061946822-5bapdpta1k3kjt240ub1pi9rugtm9pte.apps.googleusercontent.com';
  static const _androidServerClientId =
      '162061946822-kuokvhgaomuve1g0epevt8vshgvn8goi.apps.googleusercontent.com';

  static final GoogleSignIn _gsi = GoogleSignIn(
    clientId: kIsWeb ? _webClientId : null,
    scopes: ['openid', 'email', 'profile'],
    serverClientId: kIsWeb ? null : _androidServerClientId,
  );


  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _enterApp(Map<String, dynamic> data) {
    if (!mounted) return;
    final token = (data['access_token'] as String? ?? '').trim();
    if (token.isEmpty) {
      setState(() => _error = 'Login succeeded but no token returned.');
      return;
    }
    final role = data['role'] as String? ?? 'Unassigned';
    final name = data['full_name'] as String? ?? _emailCtrl.text;
    final needsProfile = data['needs_profile'] as bool? ?? false;
    final needsRoleSelection =
        data['needs_role_selection'] as bool? ?? role == 'Unassigned';

    if (needsProfile) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => CompleteProfileScreen(token: token, userName: name),
      ));
      return;
    }
    if (role == 'Administrator') {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => AdminDashboardScreen(token: token, adminName: name),
      ));
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => WebAppShell(
        token: token,
        role: role,
        userName: name,
        needsRoleSelection: needsRoleSelection,
      ),
    ));
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': _emailCtrl.text.trim().toLowerCase(),
          'password': _passCtrl.text,
        }),
      ).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      if (res.statusCode == 200) {
        _enterApp(json.decode(res.body) as Map<String, dynamic>);
      } else {
        final body = json.decode(res.body) as Map<String, dynamic>;
        setState(() => _error = body['detail']?.toString() ?? 'Login failed.');
      }
    } catch (_) {
      setState(() => _error = 'Cannot reach server. Check your connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() { _googleLoading = true; _error = null; });
    try {
      try { await _gsi.signOut(); } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final account = await _gsi.signIn();
      if (account == null) { setState(() => _googleLoading = false); return; }

      final auth = await account.authentication;
      final idToken = auth.idToken;
      final accessToken = auth.accessToken;

      if (idToken == null && accessToken == null) {
        setState(() { _googleLoading = false; _error = 'Could not retrieve Google token.'; });
        return;
      }

      final endpoint = idToken != null
          ? '${ApiConfig.baseUrl}/api/auth/google'
          : '${ApiConfig.baseUrl}/api/auth/google-web';
      final body = idToken != null
          ? json.encode({'id_token': idToken})
          : json.encode({'access_token': accessToken});

      final res = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (res.statusCode == 200) {
        _enterApp(json.decode(res.body) as Map<String, dynamic>);
      } else {
        final b = json.decode(res.body) as Map<String, dynamic>;
        setState(() => _error = b['detail']?.toString() ?? 'Google login failed.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Google Sign-In error: ${e.toString().split('\n').first}');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _slate100,
      body: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth > 900;
        if (wide) return _DesktopLayout(state: this);
        return _MobileLayout(state: this);
      }),
    );
  }
}

// ── Desktop 2-column layout ───────────────────────────────────────────────────

class _DesktopLayout extends StatelessWidget {
  final _WebLoginScreenState state;
  const _DesktopLayout({required this.state});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left branding panel
        Expanded(
          flex: 5,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF7F1D1D), Color(0xFFDC2626), Color(0xFFB91C1C)],
              ),
            ),
            padding: const EdgeInsets.all(56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back to site
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Row(children: [
                    const Icon(Icons.arrow_back_ios, color: Colors.white54, size: 14),
                    const SizedBox(width: 4),
                    Text('Back to site',
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
                  ]),
                ),
                const Spacer(),
                // Logo
                Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.bloodtype, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 12),
                  const Text('IBDMS',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                ]),
                const SizedBox(height: 32),
                const Text(
                  'Saving lives through\nsmart blood coordination.',
                  style: TextStyle(
                    fontSize: 36, fontWeight: FontWeight.w800,
                    color: Colors.white, height: 1.2, letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Pakistan\'s first AI-powered blood donor network.\nReal-time GPS matching. Emergency alerts in seconds.',
                  style: TextStyle(
                    fontSize: 15, color: Colors.white.withOpacity(0.8), height: 1.6,
                  ),
                ),
                const SizedBox(height: 48),
                // Testimonial
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '"IBDMS found a compatible donor within 3 minutes during my father\'s emergency surgery. It literally saved his life."',
                        style: TextStyle(
                          fontSize: 14, color: Colors.white.withOpacity(0.9),
                          fontStyle: FontStyle.italic, height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.white.withOpacity(0.3),
                          child: const Text('A', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 10),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Ahmed R.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                          Text('Karachi, Pakistan', style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 11)),
                        ]),
                      ]),
                    ],
                  ),
                ),
                const Spacer(),
                // Stats
                Row(children: [
                  _BrandStat('10k+', 'Donors'),
                  const SizedBox(width: 32),
                  _BrandStat('< 5min', 'Match Time'),
                  const SizedBox(width: 32),
                  _BrandStat('96.4%', 'Success'),
                ]),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),

        // Right form panel
        Expanded(
          flex: 4,
          child: Container(
            color: Colors.white,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _LoginForm(state: state),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BrandStat extends StatelessWidget {
  final String value;
  final String label;
  const _BrandStat(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7))),
      ],
    );
  }
}

// ── Mobile compact layout ─────────────────────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  final _WebLoginScreenState state;
  const _MobileLayout({required this.state});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 36, height: 36,
              decoration: BoxDecoration(color: _red, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.bloodtype, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            const Text('IBDMS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _slate900)),
          ]),
          const SizedBox(height: 36),
          _LoginForm(state: state),
        ],
      ),
    );
  }
}

// ── Shared login form ─────────────────────────────────────────────────────────

class _LoginForm extends StatelessWidget {
  final _WebLoginScreenState state;
  const _LoginForm({required this.state});

  @override
  Widget build(BuildContext context) {
    return Form(
      key: state._formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Welcome back',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _slate900, letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Row(children: [
            Text('Don\'t have an account? ', style: TextStyle(fontSize: 14, color: _slate500)),
            GestureDetector(
              onTap: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const WebSignupScreen())),
              child: const Text('Sign up',
                  style: TextStyle(fontSize: 14, color: _red, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 32),

          // Email
          _WebField(
            label: 'Email address',
            controller: state._emailCtrl,
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!_emailRe.hasMatch(v.trim())) return 'Enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Password
          _WebField(
            label: 'Password',
            controller: state._passCtrl,
            icon: Icons.lock_outline,
            obscureText: state._obscurePass,
            onToggleObscure: () => state.setState(() => state._obscurePass = !state._obscurePass),
            validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
            onSubmit: (_) => state._login(),
          ),

          // Forgot password
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 4)),
              child: const Text('Forgot password?',
                  style: TextStyle(fontSize: 13, color: _red, fontWeight: FontWeight.w500)),
            ),
          ),
          const SizedBox(height: 4),

          // Error
          if (state._error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: _red, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(state._error!,
                    style: const TextStyle(fontSize: 13, color: _redDark))),
              ]),
            ),
            const SizedBox(height: 12),
          ],

          // Login button
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: state._loading ? null : state._login,
              style: ElevatedButton.styleFrom(
                backgroundColor: _red, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: state._loading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Sign In', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => AdminGatewaySheet.show(context),
            icon: Icon(Icons.admin_panel_settings_outlined,
                size: 18, color: _slate500),
            label: Text(
              'Administrator access',
              style: TextStyle(fontSize: 13, color: _slate500),
            ),
          ),
          const SizedBox(height: 16),

          // Divider
          Row(children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text('or continue with', style: TextStyle(fontSize: 12, color: _slate500)),
            ),
            const Expanded(child: Divider()),
          ]),
          const SizedBox(height: 20),

          // Google Sign-In
          SizedBox(
            height: 50,
            child: OutlinedButton(
              onPressed: state._googleLoading ? null : state._googleSignIn,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE2E8F0)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                foregroundColor: _slate700,
              ),
              child: state._googleLoading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _GoogleIcon(),
                      const SizedBox(width: 10),
                      const Text('Continue with Google',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ]),
            ),
          ),
          const SizedBox(height: 28),

          // Privacy note
          Text(
            'By signing in you agree to our Terms of Service and Privacy Policy.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: _slate500.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18, height: 18,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    canvas.drawCircle(center, r, Paint()..color = const Color(0xFFEA4335));
    canvas.drawArc(Rect.fromCircle(center: center, radius: r),
        -1.05, 2.1, true, Paint()..color = const Color(0xFF4285F4));
    canvas.drawArc(Rect.fromCircle(center: center, radius: r),
        1.05, 2.1, true, Paint()..color = const Color(0xFF34A853));
    canvas.drawArc(Rect.fromCircle(center: center, radius: r),
        3.15, 2.1, true, Paint()..color = const Color(0xFFFBBC05));
    canvas.drawCircle(center, r * 0.55, Paint()..color = Colors.white);
    final paint = Paint()..color = const Color(0xFF4285F4);
    canvas.drawRect(Rect.fromLTWH(r, r - r * 0.15, r, r * 0.3), paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Shared web text field ─────────────────────────────────────────────────────

class _WebField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final VoidCallback? onToggleObscure;
  final void Function(String)? onSubmit;

  const _WebField({
    required this.label,
    required this.controller,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.onToggleObscure,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _slate700)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          onFieldSubmitted: onSubmit,
          validator: validator,
          style: const TextStyle(fontSize: 14, color: _slate900),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18, color: _slate500),
            suffixIcon: onToggleObscure != null
                ? IconButton(
                    icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility,
                        size: 18, color: _slate500),
                    onPressed: onToggleObscure,
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _red, width: 1.5),
            ),
            filled: true,
            fillColor: const Color(0xFFFAFAFA),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }
}
