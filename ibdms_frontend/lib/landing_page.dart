import 'package:flutter/material.dart';
import 'web_login_screen.dart';
import 'web_signup_screen.dart';

// ── Brand constants ──────────────────────────────────────────────────────────
const _red = Color(0xFFDC2626);
const _redDark = Color(0xFFB91C1C);
const _redLight = Color(0xFFFEE2E2);
const _slate900 = Color(0xFF0F172A);
const _slate700 = Color(0xFF334155);
const _slate500 = Color(0xFF64748B);
const _slate100 = Color(0xFFF1F5F9);
const _white = Colors.white;

// ── Entry point ──────────────────────────────────────────────────────────────

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final _scroll = ScrollController();
  static const double _navbarHeight = 64;

  // Section keys for scroll-to navigation
  final _featuresKey = GlobalKey();
  final _eligibilityKey = GlobalKey();
  final _downloadKey = GlobalKey();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _goLogin() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WebLoginScreen()),
      );

  void _goSignup() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WebSignupScreen()),
      );


  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    // Convert the widget's top-left corner to the scroll view's coordinate space.
    final target = box.localToGlobal(Offset.zero);
    // `_scroll.offset` = current scroll position; `target.dy` = visible-area Y.
    // Subtract navbar height so the section headline is visible, not hidden behind the bar.
    _scroll.animateTo(
      (_scroll.offset + target.dy - _navbarHeight).clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
    );
  }

  void _goHome() => _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _white,
      body: Column(
        children: [
          _Navbar(
            onSignIn: _goLogin,
            onHome: _goHome,
            onFeatures: () => _scrollTo(_featuresKey),
            onDownload: () => _scrollTo(_downloadKey),
            onAbout: () => _scrollTo(_eligibilityKey),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              child: Column(
                children: [
                  _HeroSection(onCreateAccount: _goSignup, onDownload: () => _scrollTo(_downloadKey)),
                  _ReliabilitySection(key: _featuresKey),
                  _EligibilitySection(key: _eligibilityKey),
                  _DownloadSection(key: _downloadKey),
                  _Footer(onSignIn: _goLogin),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// NAVBAR
// ══════════════════════════════════════════════════════════════════════════════

class _Navbar extends StatelessWidget {
  final VoidCallback onSignIn;
  final VoidCallback onFeatures;
  final VoidCallback onDownload;
  final VoidCallback onAbout;
  final VoidCallback onHome;
  const _Navbar({
    required this.onSignIn,
    required this.onFeatures,
    required this.onDownload,
    required this.onAbout,
    required this.onHome,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: _white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                // Logo — click to scroll to top
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: onHome,
                    child: Row(children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.bloodtype,
                            color: _white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'IBDMS',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: _slate900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ]),
                  ),
                ),
                const Spacer(),
                // Nav links — order: Features → About → Download
                _NavLink(label: 'Features', onTap: onFeatures),
                const SizedBox(width: 28),
                _NavLink(label: 'About', onTap: onAbout),
                const SizedBox(width: 28),
                _NavLink(label: 'Download', onTap: onDownload),
                const SizedBox(width: 32),
                // Sign In button with hover fill
                _HoverOutlinedButton(
                  label: 'Sign In',
                  onPressed: onSignIn,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Nav link with red highlight on hover
class _NavLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _NavLink({required this.label, required this.onTap});

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 150),
          style: TextStyle(
            fontSize: 14,
            color: _hovered ? _red : _slate700,
            fontWeight: _hovered ? FontWeight.w700 : FontWeight.w500,
          ),
          child: Text(widget.label),
        ),
      ),
    );
  }
}

// Outlined button that fills red on hover
class _HoverOutlinedButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  const _HoverOutlinedButton(
      {required this.label, required this.onPressed});

  @override
  State<_HoverOutlinedButton> createState() => _HoverOutlinedButtonState();
}

class _HoverOutlinedButtonState extends State<_HoverOutlinedButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered ? _red : Colors.transparent,
            border: Border.all(color: _red),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: _hovered ? _white : _red,
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// HERO SECTION
// ══════════════════════════════════════════════════════════════════════════════

class _HeroSection extends StatelessWidget {
  final VoidCallback onCreateAccount;
  final VoidCallback onDownload;
  const _HeroSection(
      {required this.onCreateAccount, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _white,
      padding: const EdgeInsets.symmetric(vertical: 96, horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            children: [
              // Badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _redLight,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Text(
                  '🩸  Pakistan\'s First AI-Powered Blood Network',
                  style: TextStyle(
                    fontSize: 13,
                    color: _redDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Headline
              RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 58,
                    fontWeight: FontWeight.w900,
                    color: _slate900,
                    height: 1.12,
                    letterSpacing: -1.5,
                  ),
                  children: [
                    TextSpan(text: 'Intelligent Blood\nManagement. '),
                    TextSpan(
                      text: 'Seconds\nSave Lives.',
                      style: TextStyle(color: _red),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Subtitle
              const Text(
                'IBDMS connects blood seekers with verified donors in real-time with GPS-based\n'
                'proximity matching. AI-powered chatbot guides you, and automated\n'
                'blood-bank coordination handles everything in between.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  color: _slate500,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 36),

              // CTA buttons
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  ElevatedButton(
                    onPressed: onCreateAccount,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _red,
                      foregroundColor: _white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ).copyWith(
                      backgroundColor: WidgetStateProperty.resolveWith((s) =>
                          s.contains(WidgetState.hovered) ? _redDark : _red),
                      elevation: WidgetStateProperty.resolveWith((s) =>
                          s.contains(WidgetState.hovered) ? 6 : 0),
                    ),
                    child: const Text('Create Account',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  OutlinedButton.icon(
                    onPressed: onDownload,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      foregroundColor: _slate700,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ).copyWith(
                      side: WidgetStateProperty.resolveWith((s) => BorderSide(
                          color: s.contains(WidgetState.hovered)
                              ? _red
                              : const Color(0xFFCBD5E1))),
                      foregroundColor: WidgetStateProperty.resolveWith((s) =>
                          s.contains(WidgetState.hovered) ? _red : _slate700),
                      elevation: WidgetStateProperty.resolveWith((s) =>
                          s.contains(WidgetState.hovered) ? 4 : 0),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Download App',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 64),

              // Stats row
              const _StatsRow(),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    const stats = [
      ('10k+', 'Live Donors'),
      ('50k+', 'Volunteers'),
      ('< 5 Min', 'Match Time'),
      ('96.4%', 'Success Rate'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 32),
      decoration: BoxDecoration(
        color: _slate100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: stats
            .map((s) => _StatItem(value: s.$1, label: s.$2))
            .toList(),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: _red,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: _slate500,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// RELIABILITY / FEATURES SECTION
// ══════════════════════════════════════════════════════════════════════════════

class _ReliabilitySection extends StatelessWidget {
  const _ReliabilitySection({super.key});
  final _features = const [
    (
      Icons.bolt_rounded,
      'High-Speed Match Engine',
      'Haversine-formula radius escalation finds the nearest compatible donor in under 2 minutes per stage, automatically widening the search if needed.'
    ),
    (
      Icons.smart_toy_outlined,
      'AI-Powered Chatbot',
      'RAG-based chatbot answers eligibility questions, guides donors through the process, and provides 24/7 blood-bank information instantly.'
    ),
    (
      Icons.location_on_outlined,
      'Live GPS Tracking',
      'Real-time GPS captures donor and patient location. The matching engine calculates the fastest route and optimal blood-bank assignment.'
    ),
    (
      Icons.notifications_active_outlined,
      'Instant Push Alerts',
      'Firebase Cloud Messaging delivers emergency blood requests to every nearby eligible donor within seconds of a request being submitted.'
    ),
    (
      Icons.security_outlined,
      'Secure Authentication',
      'JWT-secured endpoints with Google OAuth 2.0 support. Every request is authenticated and role-checked before data is returned.'
    ),
    (
      Icons.bar_chart_rounded,
      'Admin Analytics Dashboard',
      'Administrators get a full-spectrum dashboard with real-time request tracking, donor availability heatmaps, and fulfillment metrics.'
    ),
  ];


  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(vertical: 88, horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              // Section badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: _redLight,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Text(
                  'ENTERPRISE FEATURES',
                  style: TextStyle(
                    fontSize: 11,
                    color: _redDark,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Built for Emergency-Grade Reliability',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  color: _slate900,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Every component of IBDMS is engineered to perform under pressure,\n'
                'because every second counts in a blood emergency.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: _slate500,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 56),

              // 3-column grid
              LayoutBuilder(builder: (context, constraints) {
                final cols = constraints.maxWidth > 800 ? 3 : (constraints.maxWidth > 500 ? 2 : 1);
                return _FeatureGrid(features: _features, columns: cols);
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  final List<(IconData, String, String)> features;
  final int columns;
  const _FeatureGrid({required this.features, required this.columns});

  @override
  Widget build(BuildContext context) {
    final rows = <List<(IconData, String, String)>>[];
    for (var i = 0; i < features.length; i += columns) {
      rows.add(features.sublist(i, (i + columns).clamp(0, features.length)));
    }
    return Column(
      children: rows
          .map((row) => Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...row.map((f) => Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            child: _FeatureCard(
                                icon: f.$1, title: f.$2, desc: f.$3),
                          ),
                        )),
                    // fill empty slots in last row
                    if (row.length < columns)
                      ...List.generate(
                          columns - row.length,
                          (_) => const Expanded(child: SizedBox())),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

class _FeatureCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String desc;
  const _FeatureCard(
      {required this.icon, required this.title, required this.desc});

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hovered ? _red : const Color(0xFFE2E8F0),
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: _red.withOpacity(0.10),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _hovered ? _red : _redLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(widget.icon,
                  color: _hovered ? _white : _red, size: 24),
            ),
            const SizedBox(height: 18),
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _slate900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.desc,
              style: const TextStyle(
                fontSize: 13.5,
                color: _slate500,
                height: 1.65,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BLOOD ELIGIBILITY FINDER
// ══════════════════════════════════════════════════════════════════════════════

class _EligibilitySection extends StatefulWidget {
  const _EligibilitySection({super.key});

  @override
  State<_EligibilitySection> createState() => _EligibilitySectionState();
}

class _EligibilitySectionState extends State<_EligibilitySection> {
  String? _selected;

  static const _types = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  static const _canDonateTo = {
    'A+': ['A+', 'AB+'],
    'A-': ['A+', 'A-', 'AB+', 'AB-'],
    'B+': ['B+', 'AB+'],
    'B-': ['B+', 'B-', 'AB+', 'AB-'],
    'AB+': ['AB+'],
    'AB-': ['AB+', 'AB-'],
    'O+': ['A+', 'B+', 'AB+', 'O+'],
    'O-': ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'],
  };

  static const _canReceiveFrom = {
    'A+': ['A+', 'A-', 'O+', 'O-'],
    'A-': ['A-', 'O-'],
    'B+': ['B+', 'B-', 'O+', 'O-'],
    'B-': ['B-', 'O-'],
    'AB+': ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'],
    'AB-': ['A-', 'B-', 'AB-', 'O-'],
    'O+': ['O+', 'O-'],
    'O-': ['O-'],
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _white,
      padding: const EdgeInsets.symmetric(vertical: 88, horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: _redLight,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Text(
                  'ELIGIBILITY TOOL',
                  style: TextStyle(
                    fontSize: 11,
                    color: _redDark,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Know Before You Donate',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  color: _slate900,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Select your blood type to instantly see who you can donate to\nand who can donate to you.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: _slate500,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 44),

              // Blood type card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(36),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'Select your blood type',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _slate700,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Blood type buttons
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: _types.map((type) {
                        final isSelected = _selected == type;
                        return GestureDetector(
                          onTap: () => setState(() => _selected =
                              isSelected ? null : type),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 68,
                            height: 52,
                            decoration: BoxDecoration(
                              color: isSelected ? _red : _white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? _red
                                    : const Color(0xFFCBD5E1),
                                width: isSelected ? 2 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: _red.withOpacity(0.25),
                                        blurRadius: 12,
                                        offset: const Offset(0, 3),
                                      )
                                    ]
                                  : [],
                            ),
                            child: Center(
                              child: Text(
                                type,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: isSelected ? _white : _slate700,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    // Compatibility results
                    if (_selected != null) ...[
                      const SizedBox(height: 28),
                      const Divider(color: Color(0xFFE2E8F0)),
                      const SizedBox(height: 24),
                      LayoutBuilder(builder: (context, constraints) {
                        final wide = constraints.maxWidth > 500;
                        return wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                      child: _CompatBlock(
                                    icon: Icons.volunteer_activism_rounded,
                                    label: 'Can Donate To',
                                    types: _canDonateTo[_selected!]!,
                                    color: _red,
                                  )),
                                  const SizedBox(width: 24),
                                  Expanded(
                                      child: _CompatBlock(
                                    icon: Icons.favorite_rounded,
                                    label: 'Can Receive From',
                                    types: _canReceiveFrom[_selected!]!,
                                    color: const Color(0xFF2563EB),
                                  )),
                                ],
                              )
                            : Column(children: [
                                _CompatBlock(
                                  icon: Icons.volunteer_activism_rounded,
                                  label: 'Can Donate To',
                                  types: _canDonateTo[_selected!]!,
                                  color: _red,
                                ),
                                const SizedBox(height: 16),
                                _CompatBlock(
                                  icon: Icons.favorite_rounded,
                                  label: 'Can Receive From',
                                  types: _canReceiveFrom[_selected!]!,
                                  color: const Color(0xFF2563EB),
                                ),
                              ]);
                      }),
                    ] else ...[
                      const SizedBox(height: 24),
                      Center(
                        child: Text(
                          'Tap a blood type above to see compatibility',
                          style: TextStyle(
                            fontSize: 14,
                            color: _slate500.withOpacity(0.7),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompatBlock extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<String> types;
  final Color color;
  const _CompatBlock(
      {required this.icon,
      required this.label,
      required this.types,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: types
              .map((t) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withOpacity(0.25)),
                    ),
                    child: Text(
                      t,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DOWNLOAD SECTION
// ══════════════════════════════════════════════════════════════════════════════

class _DownloadSection extends StatelessWidget {
  const _DownloadSection({super.key});

  static const _steps = [
    ('1', 'Create Account', 'Sign up with your email or Google account in under 60 seconds.'),
    ('2', 'Complete Your Profile', 'Add blood type, location, and health details to activate matching.'),
    ('3', 'Open the App', 'Download on Android — iOS coming soon.'),
    ('4', 'Confirm Scanner', 'Run the QR scanner or tap the download link below.'),
    ('5', 'Enable Notifications', 'Allow push alerts so you never miss an emergency request near you.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(vertical: 88, horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: _redLight,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Text(
                  'DOWNLOAD',
                  style: TextStyle(
                    fontSize: 11,
                    color: _redDark,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Download IBDMS for Android',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  color: _slate900,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'The mobile app is the primary interface for blood requesting and emergency.\n'
                'Only 7.3 MB. Works even on low-end Android devices.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: _slate500,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 52),

              // 2-column layout: left = app card, right = steps
              LayoutBuilder(builder: (context, constraints) {
                if (constraints.maxWidth > 800) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: _AppCard()),
                      const SizedBox(width: 48),
                      Expanded(flex: 7, child: _StepsList(steps: _steps)),
                    ],
                  );
                }
                return Column(children: [
                  _AppCard(),
                  const SizedBox(height: 36),
                  _StepsList(steps: _steps),
                ]);
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          // App icon
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _red,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.bloodtype, color: _white, size: 40),
          ),
          const SizedBox(height: 16),
          const Text(
            'IBDMS Mobile',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _slate900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Version 2.0 · Android 5.0+',
            style: TextStyle(fontSize: 13, color: _slate500),
          ),
          const SizedBox(height: 6),
          const Text(
            '7.3 MB · Free',
            style: TextStyle(fontSize: 13, color: _slate500),
          ),
          const SizedBox(height: 28),

          // QR code placeholder
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xFFF8FAFC),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.qr_code_2_rounded,
                    size: 100, color: _slate900),
                const SizedBox(height: 4),
                Text('Scan to Download',
                    style: TextStyle(
                        fontSize: 11,
                        color: _slate500,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: _red,
                foregroundColor: _white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ).copyWith(
                backgroundColor: WidgetStateProperty.resolveWith((s) =>
                    s.contains(WidgetState.hovered) ? _redDark : _red),
                elevation: WidgetStateProperty.resolveWith((s) =>
                    s.contains(WidgetState.hovered) ? 6 : 0),
              ),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download APK',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepsList extends StatelessWidget {
  final List<(String, String, String)> steps;
  const _StepsList({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Step-by-Step Installation',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _slate900,
          ),
        ),
        const SizedBox(height: 24),
        ...steps.asMap().entries.map((e) {
          final isLast = e.key == steps.length - 1;
          final step = e.value;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _red,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        step.$1,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _white,
                        ),
                      ),
                    ),
                  ),
                  if (!isLast)
                    Container(
                        width: 2, height: 40, color: const Color(0xFFE2E8F0)),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      Text(
                        step.$2,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _slate900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        step.$3,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: _slate500,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FOOTER
// ══════════════════════════════════════════════════════════════════════════════

class _Footer extends StatelessWidget {
  final VoidCallback onSignIn;
  const _Footer({required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _slate900,
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              // Top row
              LayoutBuilder(builder: (context, constraints) {
                if (constraints.maxWidth > 700) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _FooterBrand()),
                      const SizedBox(width: 48),
                      Expanded(
                          child: _FooterLinks('Product', [
                        'Features',
                        'Download',
                        'Changelog',
                        'Roadmap',
                      ])),
                      const SizedBox(width: 24),
                      Expanded(
                          child: _FooterLinks('Support', [
                        'Documentation',
                        'FAQ',
                        'Contact',
                        'Status',
                      ])),
                      const SizedBox(width: 24),
                      Expanded(
                          child: _FooterLinks('Legal', [
                        'Privacy Policy',
                        'Terms of Use',
                        'Cookie Policy',
                      ])),
                    ],
                  );
                }
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FooterBrand(),
                      const SizedBox(height: 32),
                      _FooterLinks('Product',
                          ['Features', 'Download', 'Changelog', 'Roadmap']),
                      const SizedBox(height: 24),
                      _FooterLinks('Support',
                          ['Documentation', 'FAQ', 'Contact', 'Status']),
                    ]);
              }),
              const SizedBox(height: 48),
              const Divider(color: Color(0xFF1E293B)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '© 2026 IBDMS — Intelligent Blood Donor Management System. All rights reserved.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  TextButton(
                    onPressed: onSignIn,
                    child: const Text(
                      'Sign In →',
                      style: TextStyle(
                          fontSize: 12,
                          color: _red,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterBrand extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _red,
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(Icons.bloodtype, color: _white, size: 16),
          ),
          const SizedBox(width: 8),
          const Text(
            'IBDMS',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _white,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        const SizedBox(
          width: 260,
          child: Text(
            'Real-time AI-powered blood donor management for Pakistan. Connecting lives through technology.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF94A3B8),
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }
}

class _FooterLinks extends StatelessWidget {
  final String heading;
  final List<String> links;
  const _FooterLinks(this.heading, this.links);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _white,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 14),
        ...links.map((l) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                l,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF94A3B8),
                ),
              ),
            )),
      ],
    );
  }
}
