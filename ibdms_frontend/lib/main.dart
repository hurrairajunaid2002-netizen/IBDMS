import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // REQUIRED for kIsWeb flag
import 'api_config.dart';
import 'login_screen.dart';
import 'landing_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConfig.initialize();

  // Web client ID is declared in login_screen.dart and index.html.
  // Do NOT create a second GoogleSignIn instance here — it causes
  // google.accounts.id.initialize() to be called twice and the last
  // (potentially wrong) client ID wins, producing invalid_client errors.

  runApp(const IBDMSApp());
}

class IBDMSApp extends StatelessWidget {
  const IBDMSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IBDMS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB71C1C),
          primary: const Color(0xFFB71C1C),
          secondary: const Color(0xFF1565C0),
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFB71C1C),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFB71C1C),
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
      // Web → full marketing landing page; mobile → login screen (unchanged).
      home: kIsWeb ? const LandingPage() : const LoginScreen(),
    );
  }
}