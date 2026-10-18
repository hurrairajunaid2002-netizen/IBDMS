import 'package:flutter/material.dart';
import 'emergency_screen.dart';
import 'chatbot_screen.dart';
import 'active_alerts_screen.dart';
import 'user_profile_screen.dart';
import 'widgets/role_selection_gate.dart';

/// Central 4-tab navigation shell.
///
/// Dual-Mode Architecture
/// ─────────────────────
/// Any user (Donor OR Recipient) can switch freely between:
///   • Recipient Mode — Tab 0: Emergency Blood Search map
///   • Donor Mode     — Tab 2: Active Alerts donor feed
///
/// The mode toggle (SegmentedButton in the AppBar) is the primary
/// navigation aid.  The bottom nav tabs remain fully accessible so
/// power users can jump directly.
class HomeHub extends StatefulWidget {
  final String token;
  final String role;
  final String userName;
  final int initialTab;
  final bool needsRoleSelection;

  const HomeHub({
    super.key,
    required this.token,
    required this.role,
    required this.userName,
    this.initialTab = 0,
    this.needsRoleSelection = false,
  });

  @override
  State<HomeHub> createState() => _HomeHubState();
}

class _HomeHubState extends State<HomeHub> {
  late int _currentIndex;
  late String _token;
  late String _role;
  late bool _needsRoleSelection;

  // Active mode drives which tab is highlighted by default and which
  // tab the mode-toggle snaps to.
  late bool _donorMode; // false = Recipient / Search; true = Donor / Alerts

  // Only build tabs after the user visits them — avoids loading map + GPS
  // for every tab at once (can crash low-RAM devices after Google Sign-In).
  final Set<int> _visitedTabs = {};

  @override
  void initState() {
    super.initState();
    _token = widget.token;
    _role = widget.role;
    _needsRoleSelection =
        widget.needsRoleSelection || _role == 'Unassigned';
    _donorMode = _role == 'Donor';
    _currentIndex = widget.initialTab != 0
        ? widget.initialTab
        : (_donorMode ? 2 : 0);
    _visitedTabs.add(_currentIndex);
  }

  void _onRoleSelected(RoleSelectionResult result) {
    setState(() {
      _token = result.token;
      _role = result.role;
      _needsRoleSelection = false;
      _donorMode = result.role == 'Donor';
      _currentIndex = _donorMode ? 2 : 0;
      _visitedTabs.add(_currentIndex);
    });
  }

  Widget _tabAt(int index) {
    if (!_visitedTabs.contains(index)) {
      return const SizedBox.shrink();
    }
    switch (index) {
      case 0:
        return EmergencyScreen(
          token: _token,
          userName: widget.userName,
          role: _role,
        );
      case 1:
        return ChatbotScreen(token: _token);
      case 2:
        return ActiveAlertsScreen(
          token: _token,
          userName: widget.userName,
          role: _role,
        );
      case 3:
        return UserProfileScreen(
          token: _token,
          role: _role,
          userName: widget.userName,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _selectTab(int index) {
    setState(() {
      _currentIndex = index;
      _visitedTabs.add(index);
    });
  }

  // ── Mode toggle ───────────────────────────────────────────────────────────

  void _switchMode(bool toDonor) {
    setState(() {
      _donorMode = toDonor;
      _currentIndex = toDonor ? 2 : 0;
      _visitedTabs.add(_currentIndex);
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Stack(
        fit: StackFit.expand,
        children: [
          AbsorbPointer(
            absorbing: _needsRoleSelection,
            child: IndexedStack(
              index: _currentIndex,
              children: [
                _tabAt(0),
                _tabAt(1),
                _tabAt(2),
                _tabAt(3),
              ],
            ),
          ),
          if (_needsRoleSelection)
            RoleSelectionGate(
              token: _token,
              userName: widget.userName,
              onComplete: _onRoleSelected,
            ),
        ],
      ),
      bottomNavigationBar: _needsRoleSelection ? null : _buildBottomNav(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      automaticallyImplyLeading: false,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('IBDMS',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text(
            'Hi, ${widget.userName.split(' ').first}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
          ),
        ],
      ),
      actions: [
        // ── Dual-Mode Switch ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: _ModeToggle(
            isDonorMode: _donorMode,
            onChanged: _switchMode,
          ),
        ),
      ],
    );
  }

  // ── Bottom nav ────────────────────────────────────────────────────────────

  Widget _buildBottomNav() {
    const activeColor = Color(0xFFB71C1C);
    const inactiveColor = Color(0xFF757575);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              _navItem(
                index: 0,
                icon: Icons.bloodtype,
                label: 'Request',
                sublabel: 'Blood',
                activeColor: activeColor,
                inactiveColor: inactiveColor,
              ),
              _navItem(
                index: 1,
                icon: Icons.smart_toy_outlined,
                label: 'AI Health',
                sublabel: 'Chatbot',
                activeColor: activeColor,
                inactiveColor: inactiveColor,
              ),
              _navItem(
                index: 2,
                icon: Icons.notifications_active_outlined,
                label: 'Active',
                sublabel: 'Alerts',
                activeColor: activeColor,
                inactiveColor: inactiveColor,
              ),
              _navItem(
                index: 3,
                icon: Icons.account_circle_outlined,
                label: 'Profile',
                sublabel: null,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem({
    required int index,
    required IconData icon,
    required String label,
    String? sublabel,
    required Color activeColor,
    required Color inactiveColor,
  }) {
    final isActive = _currentIndex == index;
    final color = isActive ? activeColor : inactiveColor;
    return Expanded(
      child: GestureDetector(
        onTap: () => _selectTab(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: isActive
              ? BoxDecoration(
                  border:
                      Border(top: BorderSide(color: activeColor, width: 2.5)),
                )
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight:
                        isActive ? FontWeight.bold : FontWeight.normal,
                    color: color,
                  )),
              if (sublabel != null)
                Text(sublabel,
                    style: TextStyle(fontSize: 9, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Mode Toggle Widget ────────────────────────────────────────────────────────

/// Compact two-segment toggle that switches between Recipient and Donor mode.
/// Sits in the AppBar without eating too much horizontal space.
class _ModeToggle extends StatelessWidget {
  final bool isDonorMode;
  final ValueChanged<bool> onChanged;

  const _ModeToggle({required this.isDonorMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(80), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            label: 'Request',
            icon: Icons.bloodtype,
            active: !isDonorMode,
            onTap: () => onChanged(false),
          ),
          _segment(
            label: 'Donate',
            icon: Icons.volunteer_activism,
            active: isDonorMode,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color: active ? const Color(0xFFB71C1C) : Colors.white70),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight:
                    active ? FontWeight.bold : FontWeight.normal,
                color: active ? const Color(0xFFB71C1C) : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
