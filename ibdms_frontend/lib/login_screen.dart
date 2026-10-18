import 'dart:convert';
import 'package:flutter/foundation.dart'; // REQUIRED for kIsWeb flag
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';
import 'complete_profile_screen.dart';
import 'home_hub.dart';
import 'admin_dashboard_screen.dart';
import 'widgets/admin_gateway_sheet.dart';

/// Login screen — v3.1 (Web Fixed)
/// Supports: email/password login, Google Sign-In, Forgot Password.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loading = false;
  bool _googleLoading = false;
  bool _obscurePass = true;
  bool _rescanning = false;
  String? _errorMessage;

  // Web OAuth client ID (used as clientId on web, forbidden as serverClientId on web).
  static const _webClientId =
      '162061946822-5bapdpta1k3kjt240ub1pi9rugtm9pte.apps.googleusercontent.com';

  // Android server client ID — the Web client registered in Firebase/google-services.json.
  // Used only on native Android to request an ID token for backend verification.
  // google_sign_in_web asserts serverClientId == null, so it must be null on web.
  static const _androidServerClientId =
      '162061946822-kuokvhgaomuve1g0epevt8vshgvn8goi.apps.googleusercontent.com';

  static final GoogleSignIn _googleSignInClient = GoogleSignIn(
    clientId: kIsWeb ? _webClientId : null,
    // openid is required for the OIDC id_token to be included in the response.
    scopes: ['openid', 'email', 'profile'],
    serverClientId: kIsWeb ? null : _androidServerClientId,
  );

  // RFC 5322-like email regex — same as backend.
  static final _emailRe = RegExp(
    r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
  );

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // ── Routing helper ────────────────────────────────────────────────────────

  void _enterApp(Map<String, dynamic> data) {
    if (!mounted) return;
    final rawToken = data['access_token'];
    if (rawToken is! String || rawToken.trim().isEmpty) {
      setState(() => _errorMessage = 'Login succeeded but no access token was returned.');
      return;
    }
    final token = rawToken.trim();
    final role = data['role'] as String? ?? 'Unassigned';
    final name = data['full_name'] as String? ?? _emailCtrl.text;
    final needsProfile = data['needs_profile'] as bool? ?? false;
    final needsRoleSelection =
        data['needs_role_selection'] as bool? ?? role == 'Unassigned';

    if (needsProfile) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CompleteProfileScreen(token: token, userName: name),
        ),
      );
      return;
    }

    if (role == 'Administrator') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AdminDashboardScreen(token: token, adminName: name),
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomeHub(
          token: token,
          role: role,
          userName: name,
          needsRoleSelection: needsRoleSelection,
        ),
      ),
    );
  }

  // ── Email / password login ────────────────────────────────────────────────

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _errorMessage = null; });

    try {
      final res = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'email': _emailCtrl.text.trim().toLowerCase(),
              'password': _passCtrl.text,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (!mounted) return;
      if (res.statusCode == 200) {
        _enterApp(json.decode(res.body) as Map<String, dynamic>);
      } else {
        final body = json.decode(res.body) as Map<String, dynamic>;
        setState(() =>
            _errorMessage = body['detail']?.toString() ?? 'Login failed.');
      }
    } catch (_) {
      setState(() => _errorMessage =
          'Cannot reach server.\nTap "Scan Network" or set IP manually.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────

  Future<void> _googleSignIn() async {
    setState(() { _googleLoading = true; _errorMessage = null; });
    try {
      // Clear the cached account so Google shows the account chooser every time.
      try {
        await _googleSignInClient.signOut();
      } catch (_) {
        // Non-fatal — still attempt sign-in if sign-out fails.
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final account = await _googleSignInClient.signIn();
      if (account == null) {
        // User pressed Back on the account chooser — not an error.
        setState(() => _googleLoading = false);
        return;
      }

      final auth = await account.authentication;
      final idToken = auth.idToken;
      final accessToken = auth.accessToken;

      // On web, google_sign_in_web token-client flow may not return an id_token
      // even with openid scope. Fall back to access_token + userinfo endpoint.
      if (idToken == null && accessToken == null) {
        setState(() {
          _googleLoading = false;
          _errorMessage =
              'Google Sign-In: could not retrieve token.\n'
              'Ensure the SHA-1 fingerprint is registered in Firebase Console '
              'and google-services.json is up to date.';
        });
        return;
      }

      // Choose the right backend endpoint based on which token is available.
      final endpoint = idToken != null
          ? '${ApiConfig.baseUrl}/api/auth/google'
          : '${ApiConfig.baseUrl}/api/auth/google-web';
      final body = idToken != null
          ? json.encode({'id_token': idToken})
          : json.encode({'access_token': accessToken});

      final res = await http
          .post(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        // Let the Google Sign-In activity finish before navigating heavy screens.
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
        _enterApp(data);
      } else {
        String detail = 'Google login failed.';
        try {
          final body = json.decode(res.body) as Map<String, dynamic>;
          detail = body['detail']?.toString() ?? detail;
        } catch (_) {
          if (res.body.trim().isNotEmpty) {
            detail = 'Server error (${res.statusCode}). Check backend logs.';
          }
        }
        setState(() => _errorMessage = detail);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (msg.contains('ApiException: 10') || msg.contains('sign_in_failed')) {
        setState(() => _errorMessage =
            'Google Sign-In setup error (code 10).\n\n'
            'Fix: Firebase Console → Project Settings → Your Android App\n'
            '→ SHA certificate fingerprints → Add:\n'
            '5C:42:EB:B2:CB:49:F3:29:A8:B3:50:6D:75:01:80:91:F7:41:4B:EA\n\n'
            'Then download and replace google-services.json, rebuild the app.');
      } else {
        setState(() => _errorMessage =
            'Google Sign-In error: ${msg.split('\n').first}');
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  // ── Network discovery ─────────────────────────────────────────────────────

  Future<void> _rescan() async {
    setState(() { _rescanning = true; _errorMessage = null; });
    final found = await ApiConfig.rescan();
    if (!mounted) return;
    setState(() => _rescanning = false);
    if (found == null) {
      setState(() => _errorMessage =
          'No IBDMS server found on this network.\n'
          'Ensure the backend is running and both devices are on the same Wi-Fi.');
    }
  }

  void _showManualIpSheet() {
    final ctrl = TextEditingController(text: ApiConfig.currentServerIp);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.settings_ethernet,
                  color: Color(0xFFB71C1C)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Manual Server IP',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx)),
            ]),
            Text(
              'Run  ipconfig  on your PC to find the Wi-Fi "IPv4 Address".',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Server IP Address',
                hintText: '192.168.x.x',
                prefixIcon: const Icon(Icons.dns_outlined),
                suffixText: ':5000',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                await ApiConfig.setServerIp(ctrl.text);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                setState(() => _errorMessage = null);
              },
              child: const Text('Save & Connect'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              children: [
                // ── Branding ──────────────────────────────────────────────
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFB71C1C),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.bloodtype,
                      color: Colors.white, size: 44),
                ),
                const SizedBox(height: 16),
                Text(
                  'IBDMS',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFB71C1C),
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Intelligent Blood Donor Management',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600]),
                ),

                const SizedBox(height: 12),
                _buildServerBadge(),
                const SizedBox(height: 24),

                // ── Login card ────────────────────────────────────────────
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Login',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 20),

                          // Email
                          TextFormField(
                            controller: _emailCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Email is required.';
                              }
                              if (!_emailRe.hasMatch(v.trim())) {
                                return 'Enter a valid email address.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Password
                          TextFormField(
                            controller: _passCtrl,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon:
                                  const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePass
                                    ? Icons.visibility_off
                                    : Icons.visibility),
                                onPressed: () => setState(
                                    () => _obscurePass = !_obscurePass),
                              ),
                            ),
                            obscureText: _obscurePass,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _login(),
                            validator: (v) =>
                                (v == null || v.length < 6)
                                    ? 'Min 6 characters'
                                    : null,
                          ),

                          // Forgot password link
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const ForgotPasswordScreen()),
                              ),
                              style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap),
                              child: Text(
                                'Forgot password?',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue[700]),
                              ),
                            ),
                          ),

                          // Error message
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.red[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red[200]!),
                              ),
                              child: Text(_errorMessage!,
                                  style: TextStyle(
                                      color: Colors.red[800],
                                      fontSize: 12)),
                            ),
                          ],

                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: _loading ? null : _login,
                            child: _loading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white))
                                : const Text('Login',
                                    style: TextStyle(fontSize: 16)),
                          ),

                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: () => AdminGatewaySheet.show(context),
                            icon: Icon(Icons.admin_panel_settings_outlined,
                                size: 16, color: Colors.grey[600]),
                            label: Text(
                              'Administrator access',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // ── Divider ──────────────────────────────────────
                          Row(children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12),
                              child: Text('or',
                                  style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 12)),
                            ),
                            const Expanded(child: Divider()),
                          ]),
                          const SizedBox(height: 16),

                          // ── Google Sign-In ────────────────────────────────
                          OutlinedButton.icon(
                            onPressed:
                                _googleLoading ? null : _googleSignIn,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12),
                              side: BorderSide(color: Colors.grey[300]!),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: _googleLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.g_mobiledata, size: 24, color: Colors.red),
                            label: Text(
                              _googleLoading
                                  ? 'Signing in…'
                                  : 'Continue with Google',
                              style: TextStyle(
                                  color: Colors.grey[800], fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Bottom actions ────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SignupScreen())),
                      child: const Text('Registration'),
                    ),
                    // UDP network scan only works on mobile (not on web).
                    if (!kIsWeb) ...[
                    Text('·', style: TextStyle(color: Colors.grey[400])),
                    TextButton.icon(
                      onPressed: _rescanning ? null : _rescan,
                      icon: _rescanning
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2))
                          : const Icon(Icons.wifi_find, size: 15),
                      label: Text(
                          _rescanning ? 'Scanning…' : 'Scan Network'),
                      style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFB71C1C)),
                    ),
                    ], // end if (!kIsWeb)
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServerBadge() {
    return ValueListenableBuilder<String>(
      valueListenable: ApiConfig.serverIpNotifier,
      builder: (context, ip, child) {
        // On web, server is always localhost — no discovery, no manual IP needed.
        final isDiscovering = kIsWeb ? false : ApiConfig.isDiscovering;
        return GestureDetector(
          onTap: kIsWeb ? null : _showManualIpSheet,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: isDiscovering ? Colors.orange[50] : Colors.grey[100],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: isDiscovering
                      ? Colors.orange[300]!
                      : Colors.grey[300]!),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDiscovering)
                  const SizedBox(
                    width: 8,
                    height: 8,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.orange),
                  )
                else
                  Icon(Icons.circle, size: 8, color: Colors.green[600]),
                const SizedBox(width: 6),
                Text(
                  ApiConfig.baseUrl,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDiscovering
                        ? Colors.orange[800]
                        : Colors.grey[600],
                  ),
                ),
                if (!kIsWeb) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.edit_outlined, size: 11, color: Colors.grey[400]),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}