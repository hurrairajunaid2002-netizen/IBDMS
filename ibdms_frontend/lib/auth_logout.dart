import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'landing_page.dart';
import 'login_screen.dart';

/// Central sign-out: clears cached auth state and routes by platform.
class AuthLogout {
  AuthLogout._();

  static const _authKeys = [
    'access_token',
    'auth_token',
    'refresh_token',
    'user_role',
    'user_name',
    'user_email',
    'admin_token',
    'is_admin',
    'needs_profile',
  ];

  /// Wipe session tokens and third-party auth caches.
  static Future<void> clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in _authKeys) {
        await prefs.remove(key);
      }
    } catch (_) {}

    // Clear Google cached account on native mobile (not web GIS flow).
    if (!kIsWeb) {
      try {
        await GoogleSignIn().signOut();
      } catch (_) {}
      try {
        await GoogleSignIn().disconnect();
      } catch (_) {}
    }
  }

  /// Web → public landing page. Mobile → native login/signup screen.
  static void navigateToEntry(BuildContext context) {
    final Widget destination =
        kIsWeb ? const LandingPage() : const LoginScreen();

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destination),
      (_) => false,
    );
  }

  /// Full sign-out workflow for admin and user panels.
  static Future<void> perform(BuildContext context) async {
    await clearSession();
    if (!context.mounted) return;
    navigateToEntry(context);
  }
}
