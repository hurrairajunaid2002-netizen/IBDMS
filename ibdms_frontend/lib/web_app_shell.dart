import 'package:flutter/material.dart';
import 'emergency_screen.dart';
import 'chatbot_screen.dart';
import 'active_alerts_screen.dart';
import 'user_profile_screen.dart';
import 'landing_page.dart';
import 'widgets/role_selection_gate.dart';

const _red = Color(0xFFDC2626);
const _redLight = Color(0xFFFEE2E2);
const _slate900 = Color(0xFF0F172A);
const _slate700 = Color(0xFF334155);
const _slate500 = Color(0xFF64748B);
const _slate100 = Color(0xFFF1F5F9);
const _white = Colors.white;

/// Desktop web shell — sidebar + main content area.
/// Mobile users never reach this; they use HomeHub directly.
class WebAppShell extends StatefulWidget {
  final String token;
  final String role;
  final String userName;
  final bool needsRoleSelection;

  const WebAppShell({
    super.key,
    required this.token,
    required this.role,
    required this.userName,
    this.needsRoleSelection = false,
  });

  @override
  State<WebAppShell> createState() => _WebAppShellState();
}

class _WebAppShellState extends State<WebAppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;
  bool _sidebarCollapsed = false;
  late String _token;
  late String _role;
  late bool _needsRoleSelection;

  late final List<_NavItem> _navItems;

  @override
  void initState() {
    super.initState();
    _token = widget.token;
    _role = widget.role;
    _needsRoleSelection =
        widget.needsRoleSelection || _role == 'Unassigned';
    _navItems = _buildNavItems();
    _selectedIndex = _role == 'Donor' ? 2 : 0;
  }

  void _onRoleSelected(RoleSelectionResult result) {
    setState(() {
      _token = result.token;
      _role = result.role;
      _needsRoleSelection = false;
      _selectedIndex = result.role == 'Donor' ? 2 : 0;
    });
  }

  List<_NavItem> _buildNavItems() {
    final items = [
      _NavItem(0, Icons.emergency_outlined, Icons.emergency, 'Emergency', 'Request Blood'),
      _NavItem(1, Icons.smart_toy_outlined, Icons.smart_toy, 'AI Chatbot', 'Ask Anything'),
      _NavItem(2, Icons.notifications_outlined, Icons.notifications, 'Alerts', 'Active Requests'),
      _NavItem(3, Icons.person_outline, Icons.person, 'Profile', 'My Account'),
    ];
    return items;
  }

  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0:
        return EmergencyScreen(
            token: _token,
            userName: widget.userName,
            role: _role,
            embedInShell: true);
      case 1:
        return ChatbotScreen(token: _token, embedInShell: true);
      case 2:
        return ActiveAlertsScreen(
            token: _token,
            userName: widget.userName,
            role: _role,
            embedInShell: true);
      case 3:
        return UserProfileScreen(
            token: _token,
            role: _role,
            userName: widget.userName,
            embedInShell: true);
      default:
        return EmergencyScreen(
            token: _token,
            userName: widget.userName,
            role: _role,
            embedInShell: true);
    }
  }

  Widget _buildMainPanel({VoidCallback? onOpenDrawer}) {
    return Column(
      children: [
        _TopBar(
          title: _navItems
              .firstWhere((n) => n.index == _selectedIndex,
                  orElse: () => _navItems.first)
              .label,
          subtitle: _navItems
              .firstWhere((n) => n.index == _selectedIndex,
                  orElse: () => _navItems.first)
              .subtitle,
          userName: widget.userName,
          role: _role,
          onMenu: onOpenDrawer,
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            decoration: BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: _buildContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspace({required bool useDrawer}) {
    if (useDrawer) {
      return _buildMainPanel(
        onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
      );
    }

    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          width: _sidebarCollapsed ? 64 : 240,
          child: _Sidebar(
            items: _navItems,
            selectedIndex: _selectedIndex,
            collapsed: _sidebarCollapsed,
            userName: widget.userName,
            role: _role,
            onSelect: (i) => setState(() => _selectedIndex = i),
            onToggleCollapse: () =>
                setState(() => _sidebarCollapsed = !_sidebarCollapsed),
            onLogout: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LandingPage()),
              (r) => false,
            ),
          ),
        ),
        Expanded(child: _buildMainPanel()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useDrawer = constraints.maxWidth < 900;

        return Scaffold(
          key: useDrawer ? _scaffoldKey : null,
          backgroundColor: _slate100,
          drawer: useDrawer
              ? Drawer(
                  width: 260,
                  backgroundColor: _slate900,
                  child: _Sidebar(
                    items: _navItems,
                    selectedIndex: _selectedIndex,
                    collapsed: false,
                    userName: widget.userName,
                    role: _role,
                    onSelect: (i) {
                      setState(() => _selectedIndex = i);
                      Navigator.of(context).pop();
                    },
                    onToggleCollapse: () => Navigator.of(context).pop(),
                    onLogout: () => Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LandingPage()),
                      (r) => false,
                    ),
                    showCollapseToggle: false,
                  ),
                )
              : null,
          body: Stack(
            fit: StackFit.expand,
            children: [
              AbsorbPointer(
                absorbing: _needsRoleSelection,
                child: _buildWorkspace(useDrawer: useDrawer),
              ),
              if (_needsRoleSelection)
                RoleSelectionGate(
                  token: _token,
                  userName: widget.userName,
                  onComplete: _onRoleSelected,
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── Nav item model ─────────────────────────────────────────────────────────────

class _NavItem {
  final int index;
  final IconData icon;
  final IconData iconFilled;
  final String label;
  final String subtitle;
  const _NavItem(
      this.index, this.icon, this.iconFilled, this.label, this.subtitle);
}

// ── Sidebar ───────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final List<_NavItem> items;
  final int selectedIndex;
  final bool collapsed;
  final String userName;
  final String role;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggleCollapse;
  final VoidCallback onLogout;
  final bool showCollapseToggle;

  const _Sidebar({
    required this.items,
    required this.selectedIndex,
    required this.collapsed,
    required this.userName,
    required this.role,
    required this.onSelect,
    required this.onToggleCollapse,
    required this.onLogout,
    this.showCollapseToggle = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        color: _slate900,
        border: Border(right: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Column(
        children: [
          // Logo + collapse button
          _SidebarHeader(
            collapsed: collapsed,
            showCollapseToggle: showCollapseToggle,
            onToggleCollapse: onToggleCollapse,
          ),

          const SizedBox(height: 12),

          // Nav items
          ...items.map((item) => _SidebarItem(
                item: item,
                isSelected: selectedIndex == item.index,
                collapsed: collapsed,
                onTap: () => onSelect(item.index),
              )),

          const Spacer(),

          // Logout
          Padding(
            padding: const EdgeInsets.all(12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onLogout,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    mainAxisAlignment: collapsed
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: [
                      const Icon(Icons.logout_rounded, color: Colors.white38, size: 18),
                      if (!collapsed) ...[
                        const SizedBox(width: 10),
                        const Text('Sign Out',
                            style: TextStyle(fontSize: 13, color: Colors.white38)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          // User avatar at bottom
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: _red,
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                    style: const TextStyle(color: _white, fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName.split(' ').first,
                          style: const TextStyle(color: _white, fontSize: 13, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          role,
                          style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  final bool collapsed;
  final bool showCollapseToggle;
  final VoidCallback onToggleCollapse;

  const _SidebarHeader({
    required this.collapsed,
    required this.showCollapseToggle,
    required this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: collapsed
          ? Center(
              child: IconButton(
                tooltip: 'Expand sidebar',
                icon: const Icon(Icons.menu_open, color: Colors.white54, size: 22),
                onPressed: onToggleCollapse,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _red,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.bloodtype, color: _white, size: 18),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'IBDMS',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _white,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  if (showCollapseToggle)
                    IconButton(
                      tooltip: 'Collapse sidebar',
                      icon: const Icon(Icons.menu, color: Colors.white54, size: 20),
                      onPressed: onToggleCollapse,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                ],
              ),
            ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  final _NavItem item;
  final bool isSelected;
  final bool collapsed;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.item,
    required this.isSelected,
    required this.collapsed,
    required this.onTap,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isSelected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(
              horizontal: widget.collapsed ? 0 : 12,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: active
                  ? _red.withOpacity(0.18)
                  : _hovered
                      ? Colors.white.withOpacity(0.06)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: active
                  ? Border.all(color: _red.withOpacity(0.35))
                  : null,
            ),
            child: Row(
              mainAxisAlignment: widget.collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  active ? widget.item.iconFilled : widget.item.icon,
                  size: 18,
                  color: active ? _red : Colors.white54,
                ),
                if (!widget.collapsed) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.item.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        color: active ? _white : Colors.white60,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final String userName;
  final String role;
  final VoidCallback? onMenu;

  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.userName,
    required this.role,
    this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 900;

    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 24),
      margin: EdgeInsets.fromLTRB(narrow ? 8 : 16, 16, narrow ? 8 : 16, 8),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (onMenu != null) ...[
            IconButton(
              tooltip: 'Open menu',
              icon: const Icon(Icons.menu, color: _slate700),
              onPressed: onMenu,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _slate900)),
                Text(subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: _slate500)),
              ],
            ),
          ),
          if (!narrow) ...[
            // Role badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: role == 'Admin' ? const Color(0xFFEFF6FF) : _redLight,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(children: [
                Icon(
                  role == 'Admin'
                      ? Icons.admin_panel_settings
                      : Icons.volunteer_activism,
                  size: 12,
                  color: role == 'Admin' ? const Color(0xFF2563EB) : _red,
                ),
                const SizedBox(width: 5),
                Text(
                  role,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: role == 'Admin' ? const Color(0xFF2563EB) : _red,
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 16),
            // User chip
            Row(children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: _red,
                child: Text(
                  userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                  style: const TextStyle(
                      color: _white, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                userName.split(' ').first,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: _slate700),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}
