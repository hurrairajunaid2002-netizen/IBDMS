import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'web_login_screen.dart';

const _red = Color(0xFFDC2626);
const _redDark = Color(0xFFB91C1C);
const _slate900 = Color(0xFF0F172A);
const _slate700 = Color(0xFF334155);
const _slate500 = Color(0xFF64748B);

class WebSignupScreen extends StatefulWidget {
  const WebSignupScreen({super.key});

  @override
  State<WebSignupScreen> createState() => _WebSignupScreenState();
}

class _WebSignupScreenState extends State<WebSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  String _bloodGroup = 'O+';
  bool _loading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String? _error;
  String? _success;

  static const _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  static final _emailRe = RegExp(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$');

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _phoneCtrl.dispose();
    _passCtrl.dispose(); _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; _success = null; });
    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'full_name': _nameCtrl.text.trim(),
          'email': _emailCtrl.text.trim().toLowerCase(),
          'phone_number': _phoneCtrl.text.trim(),
          'password': _passCtrl.text,
          'blood_group': _bloodGroup,
        }),
      ).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 201) {
        setState(() => _success = 'Account created! You can now sign in.');
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const WebLoginScreen()));
        }
      } else {
        final b = json.decode(res.body) as Map<String, dynamic>;
        setState(() => _error = b['detail']?.toString() ?? 'Registration failed.');
      }
    } catch (_) {
      setState(() => _error = 'Cannot reach server. Check your connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth > 900) return _DesktopLayout(state: this);
        return _MobileLayout(state: this);
      }),
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  final _WebSignupScreenState state;
  const _DesktopLayout({required this.state});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left branding panel
        Expanded(
          flex: 4,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF334155)],
              ),
            ),
            padding: const EdgeInsets.all(56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Row(children: [
                    const Icon(Icons.arrow_back_ios, color: Colors.white54, size: 14),
                    const SizedBox(width: 4),
                    Text('Back', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
                  ]),
                ),
                const Spacer(),
                Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: _red, borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.bloodtype, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 12),
                  const Text('IBDMS',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                ]),
                const SizedBox(height: 32),
                const Text(
                  'Join Pakistan\'s blood\ndonor network today.',
                  style: TextStyle(
                    fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white,
                    height: 1.2, letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Register once. Save lives forever.\nYour blood type profile activates automatic emergency matching.',
                  style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.75), height: 1.65),
                ),
                const SizedBox(height: 48),
                ...[
                  _BenefitRow(Icons.bolt_rounded, 'Instant emergency matching'),
                  _BenefitRow(Icons.location_on_outlined, 'GPS-based nearby donors'),
                  _BenefitRow(Icons.notifications_outlined, 'Push alerts for your area'),
                  _BenefitRow(Icons.smart_toy_outlined, 'AI chatbot guidance 24/7'),
                ],
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.shield_outlined, color: Colors.white70, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your data is protected. We never share personal information without consent.',
                        style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7), height: 1.5),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),

        // Right form
        Expanded(
          flex: 5,
          child: Container(
            color: Colors.white,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: _SignupForm(state: state),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _BenefitRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: _red.withOpacity(0.25), borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, color: Colors.white, size: 15),
        ),
        const SizedBox(width: 12),
        Text(text, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.85))),
      ]),
    );
  }
}

class _MobileLayout extends StatelessWidget {
  final _WebSignupScreenState state;
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
          _SignupForm(state: state),
        ],
      ),
    );
  }
}

class _SignupForm extends StatelessWidget {
  final _WebSignupScreenState state;
  const _SignupForm({required this.state});

  @override
  Widget build(BuildContext context) {
    return Form(
      key: state._formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Create your account',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _slate900, letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Row(children: [
            Text('Already have an account? ', style: TextStyle(fontSize: 14, color: _slate500)),
            GestureDetector(
              onTap: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const WebLoginScreen())),
              child: const Text('Sign in',
                  style: TextStyle(fontSize: 14, color: _red, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 28),

          // Name + Email row
          LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth > 400) {
              return Row(children: [
                Expanded(child: _WebField2(label: 'Full Name', controller: state._nameCtrl,
                    icon: Icons.person_outline,
                    validator: (v) => (v == null || v.trim().length < 3) ? 'Min 3 chars' : null)),
                const SizedBox(width: 14),
                Expanded(child: _WebField2(label: 'Email', controller: state._emailCtrl,
                    icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (!_emailRe.hasMatch(v.trim())) return 'Invalid email';
                      return null;
                    })),
              ]);
            }
            return Column(children: [
              _WebField2(label: 'Full Name', controller: state._nameCtrl, icon: Icons.person_outline,
                  validator: (v) => (v == null || v.trim().length < 3) ? 'Min 3 chars' : null),
              const SizedBox(height: 14),
              _WebField2(label: 'Email', controller: state._emailCtrl,
                  icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (!_emailRe.hasMatch(v.trim())) return 'Invalid email';
                    return null;
                  }),
            ]);
          }),
          const SizedBox(height: 14),

          // Phone
          _WebField2(label: 'Phone Number', controller: state._phoneCtrl,
              icon: Icons.phone_outlined, keyboardType: TextInputType.phone,
              validator: (v) => (v == null || v.trim().length < 7) ? 'Invalid phone' : null),
          const SizedBox(height: 14),

          // Blood group
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Blood Group',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _slate700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: _WebSignupScreenState._bloodGroups.map((bg) {
                  final sel = state._bloodGroup == bg;
                  return GestureDetector(
                    onTap: () => state.setState(() => state._bloodGroup = bg),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 52, height: 40,
                      decoration: BoxDecoration(
                        color: sel ? _red : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: sel ? _red : const Color(0xFFE2E8F0)),
                      ),
                      child: Center(
                        child: Text(bg,
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700,
                                color: sel ? Colors.white : _slate700)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Password row
          LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth > 400) {
              return Row(children: [
                Expanded(child: _WebField2(label: 'Password', controller: state._passCtrl,
                    icon: Icons.lock_outline, obscureText: state._obscurePass,
                    onToggleObscure: () => state.setState(() => state._obscurePass = !state._obscurePass),
                    validator: (v) => (v == null || v.length < 6) ? 'Min 6 chars' : null)),
                const SizedBox(width: 14),
                Expanded(child: _WebField2(label: 'Confirm Password', controller: state._confirmCtrl,
                    icon: Icons.lock_outline, obscureText: state._obscureConfirm,
                    onToggleObscure: () => state.setState(() => state._obscureConfirm = !state._obscureConfirm),
                    validator: (v) => v != state._passCtrl.text ? 'Passwords don\'t match' : null)),
              ]);
            }
            return Column(children: [
              _WebField2(label: 'Password', controller: state._passCtrl,
                  icon: Icons.lock_outline, obscureText: state._obscurePass,
                  onToggleObscure: () => state.setState(() => state._obscurePass = !state._obscurePass),
                  validator: (v) => (v == null || v.length < 6) ? 'Min 6 chars' : null),
              const SizedBox(height: 14),
              _WebField2(label: 'Confirm Password', controller: state._confirmCtrl,
                  icon: Icons.lock_outline, obscureText: state._obscureConfirm,
                  onToggleObscure: () => state.setState(() => state._obscureConfirm = !state._obscureConfirm),
                  validator: (v) => v != state._passCtrl.text ? 'Passwords don\'t match' : null),
            ]);
          }),
          const SizedBox(height: 20),

          // Error/Success
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
          if (state._success != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_outline, color: Color(0xFF16A34A), size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(state._success!,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF15803D)))),
              ]),
            ),
            const SizedBox(height: 12),
          ],

          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: state._loading ? null : state._register,
              style: ElevatedButton.styleFrom(
                backgroundColor: _red, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: state._loading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create Account',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'By creating an account you agree to our Terms of Service and Privacy Policy.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: _slate500.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }
}

final _emailRe = RegExp(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$');

class _WebField2 extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final VoidCallback? onToggleObscure;

  const _WebField2({
    required this.label,
    required this.controller,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.onToggleObscure,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _slate700)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
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
                borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _red, width: 1.5)),
            filled: true, fillColor: const Color(0xFFFAFAFA),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }
}
