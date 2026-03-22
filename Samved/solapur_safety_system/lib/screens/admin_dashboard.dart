import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../providers/app_state.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';
import 'login_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Colors & Theme - Government-Grade Dark Theme
// ─────────────────────────────────────────────────────────────────────────────
const _bg          = Color(0xFF0A0F1C);
const _surface     = Color(0xFF111827);
const _surfaceAlt  = Color(0xFF1A2235);
const _border      = Color(0xFF1F2D40);
const _textPrimary = Color(0xFFFFFFFF);
const _textSub     = Color(0xFF9CA3AF);

const _green  = Color(0xFF22C55E);
const _amber  = Color(0xFFF59E0B);
const _red    = Color(0xFFEF4444);
const _blue   = Color(0xFF3B82F6);

Color _statusColor(String s) {
  switch (s.toUpperCase()) {
    case 'SAFE':    return _green;
    case 'CAUTION': return _amber;
    case 'BLOCK':   return _red;
    case 'DANGER':  return _red;
    default:        return _textSub;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main Admin Dashboard (Navigation Wrapper)
// ─────────────────────────────────────────────────────────────────────────────
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;
  String _currentTime = '';
  Timer? _clockTimer;
  final AuthService _authService = AuthService();

  final List<Widget> _pages = [
    const _OverviewPage(),
    const _UsersPage(),
    const _ManholesPage(),
    const _AssignmentsPage(),
    const _AlertsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _authService.loadSession();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      if (mounted) {
        setState(() {
          _currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
        });
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.admin_panel_settings, color: _blue, size: 24),
            const SizedBox(width: 12),
            const Flexible(
              child: Text(
                'Admin Control Panel',
                style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: Text(
              _currentTime,
              style: const TextStyle(color: _textSub, fontFamily: 'monospace', fontSize: 14),
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.logout, color: _red),
            tooltip: 'Logout',
            onPressed: () async {
              await _authService.logout();
              if (mounted) {
                // ignore: use_build_context_synchronously
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              }
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: _border, height: 1),
        ),
      ),
      body: isWide
          ? Row(
              children: [
                NavigationRail(
                  backgroundColor: _surface,
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (i) => setState(() => _currentIndex = i),
                  extended: MediaQuery.of(context).size.width > 1000,
                  unselectedLabelTextStyle: const TextStyle(color: _textSub),
                  selectedLabelTextStyle: const TextStyle(color: _blue, fontWeight: FontWeight.bold),
                  unselectedIconTheme: const IconThemeData(color: _textSub),
                  selectedIconTheme: const IconThemeData(color: _blue),
                  destinations: const [
                    NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: Text('Overview')),
                    NavigationRailDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: Text('Users')),
                    NavigationRailDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: Text('Manholes')),
                    NavigationRailDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: Text('Assignments')),
                    NavigationRailDestination(icon: Icon(Icons.warning_amber_outlined), selectedIcon: Icon(Icons.warning), label: Text('Alerts')),
                  ],
                ),
                Container(width: 1, color: _border),
                Expanded(child: _pages[_currentIndex]),
              ],
            )
          : _pages[_currentIndex],
      bottomNavigationBar: isWide
          ? null
          : BottomNavigationBar(
              backgroundColor: _surface,
              currentIndex: _currentIndex,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: _blue,
              unselectedItemColor: _textSub,
              onTap: (i) => setState(() => _currentIndex = i),
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Overview'),
                BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Users'),
                BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Manholes'),
                BottomNavigationBarItem(icon: Icon(Icons.assignment), label: 'Assign'),
                BottomNavigationBarItem(icon: Icon(Icons.warning), label: 'Alerts'),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  1. Overview (Dashboard) Page
// ─────────────────────────────────────────────────────────────────────────────
class _OverviewPage extends StatelessWidget {
  const _OverviewPage();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isWide = MediaQuery.of(context).size.width > 800;

    // Insights Logic
    final recentAlerts = state.activeAlerts.where((a) => DateTime.now().difference(a.timestamp).inHours < 1).length;
    List<Map<String, dynamic>> insights = [];
    if (recentAlerts > 0) {
      insights.add({'icon': Icons.warning_amber_rounded, 'color': _red, 'text': '$recentAlerts alerts in the last hour. Investigate immediately.'});
    } else {
      insights.add({'icon': Icons.check_circle_outline, 'color': _green, 'text': 'System operating within safe parameters. No recent alerts.'});
    }
    if (state.currentData.h2s > 5) {
      insights.add({'icon': Icons.air, 'color': _amber, 'text': 'H2S levels elevated (${state.currentData.h2s.toStringAsFixed(1)} ppm). Monitor closely.'});
    }
    if (state.activeWorkers.isNotEmpty) {
      insights.add({'icon': Icons.person, 'color': _blue, 'text': '${state.activeWorkers.length} worker(s) currently active in the field.'});
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('SYSTEM OVERVIEW', style: TextStyle(color: _textSub, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 16),
          // Summary Grid
          GridView.count(
            crossAxisCount: isWide ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: isWide ? 2.5 : 1.5,
            children: [
              _summaryCard('Total Alerts', '${state.activeAlerts.length}', Icons.notifications, _red),
              _summaryCard('Active Workers', '${state.activeWorkers.length}', Icons.person, _blue),
              _summaryCard('Safety Status', state.overallStatus.name.toUpperCase(), Icons.shield, _statusColor(state.overallStatus.name)),
              _summaryCard('Connected Devices', '${state.devices.length}', Icons.devices, _green),
            ],
          ),
          const SizedBox(height: 24),
          // System Insights
          _sectionCard(
            title: 'SYSTEM INSIGHTS',
            child: Column(
              children: insights.map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(i['icon'], color: i['color'], size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(i['text'], style: const TextStyle(color: _textPrimary), overflow: TextOverflow.ellipsis, maxLines: 2)),
                  ],
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.10), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: const TextStyle(color: _textSub, fontSize: 11), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(color: _textPrimary, fontSize: 20, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  2. Users Page
// ─────────────────────────────────────────────────────────────────────────────
class _UsersPage extends StatefulWidget {
  const _UsersPage();
  @override
  State<_UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<_UsersPage> {
  // Each page gets its own AuthService instance so the token is loaded fresh
  final AuthService _auth = AuthService();
  List<dynamic> _users = [];
  List<dynamic> _assignments = [];
  bool _isLoading = true;
  bool _isCreating = false;

  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  // Admin CANNOT create 'admin'. Only worker or supervisor.
  String _role = 'worker';

  @override
  void initState() {
    super.initState();
    _initAndFetch();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// Load auth session FIRST, then fetch data so that _auth.token is populated.
  Future<void> _initAndFetch() async {
    await _auth.loadSession();
    await _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final u = await _auth.fetchUsers();
      final aRes = await http.get(Uri.parse('${SocketService.serverUrl}/api/assignments'));
      List<dynamic> a = [];
      if (aRes.statusCode == 200) {
        a = jsonDecode(aRes.body);
      }
      if (mounted) {
        setState(() {
          _users = u;
          _assignments = a;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createUser() async {
    final u = _userCtrl.text.trim();
    final p = _passCtrl.text.trim();
    if (u.isEmpty || p.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username and password are required'), backgroundColor: _amber),
      );
      return;
    }

    setState(() => _isCreating = true);
    final res = await _auth.registerUser(u, p, _role);
    if (!mounted) return;
    setState(() => _isCreating = false);

    if (res['success'] == true) {
      _userCtrl.clear();
      _passCtrl.clear();
      _fetchData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User created successfully'), backgroundColor: _green));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${res['error']}'), backgroundColor: _red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final workers = _users.where((u) => u['role'] == 'worker').toList();
    final sups = _users.where((u) => u['role'] == 'supervisor').toList();
    final isWide = MediaQuery.of(context).size.width > 800;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('USER MANAGEMENT', style: TextStyle(color: _textSub, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 16),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 1,
                  child: _buildCreateForm(),
                ),
                const SizedBox(width: 24),
                Expanded(flex: 2, child: _buildUserLists(workers, sups)),
              ],
            )
          else ...[
            _buildCreateForm(),
            const SizedBox(height: 24),
            _buildUserLists(workers, sups),
          ],
        ],
      ),
    );
  }

  Widget _buildCreateForm() {
    return _sectionCard(
      title: 'CREATE NEW USER',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _input('Username', _userCtrl, obscure: false),
          const SizedBox(height: 12),
          _input('Password', _passCtrl, obscure: true),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _role,
            dropdownColor: _surfaceAlt,
            style: const TextStyle(color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Role',
              labelStyle: const TextStyle(color: _textSub),
              filled: true,
              fillColor: _bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
            items: const [
              DropdownMenuItem(value: 'worker', child: Text('WORKER')),
              DropdownMenuItem(value: 'supervisor', child: Text('SUPERVISOR')),
            ],
            onChanged: (v) => setState(() => _role = v!),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _blue, padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: _isCreating ? null : _createUser,
            child: _isCreating
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('CREATE USER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildUserLists(List workers, List sups) {
    if (_isLoading) return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    return Column(
      children: [
        _sectionCard(
          title: 'REGISTERED SUPERVISORS (${sups.length})',
          child: sups.isEmpty
              ? const Text('No supervisors registered.', style: TextStyle(color: _textSub))
              : Column(
                  children: sups.map((u) {
                    final assignedZones = _assignments.where((a) => a['type'] == 'supervisor_zone' && a['supervisorId'] == u['id']).map((a) => a['zoneId']).join(', ');
                    final activeWorkers = _assignments.where((a) => a['type'] == 'worker_supervisor' && a['supervisorId'] == u['id']).length;
                    return ListTile(
                      leading: const Icon(Icons.shield, color: _amber),
                      title: Text(u['username'], style: const TextStyle(color: _textPrimary), overflow: TextOverflow.ellipsis),
                      subtitle: Text(assignedZones.isEmpty ? 'No Zone Assigned | Workers: $activeWorkers' : 'Zones: $assignedZones | Workers: $activeWorkers', style: const TextStyle(color: _textSub, fontSize: 11), overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 24),
        _sectionCard(
          title: 'REGISTERED WORKERS (${workers.length})',
          child: workers.isEmpty
              ? const Text('No workers registered.', style: TextStyle(color: _textSub))
              : Column(
                  children: workers.map((u) {
                    final assignedSup = _assignments.firstWhere((a) => a['type'] == 'worker_supervisor' && a['workerId'] == u['id'], orElse: () => null);
                    String supText = 'Unassigned';
                    if (assignedSup != null) {
                      final s = _users.firstWhere((x) => x['id'] == assignedSup['supervisorId'], orElse: () => null);
                      if (s != null) supText = 'Sup: ${s['username']}';
                    }
                    return ListTile(
                      leading: const Icon(Icons.person, color: _blue),
                      title: Text(u['username'], style: const TextStyle(color: _textPrimary), overflow: TextOverflow.ellipsis),
                      subtitle: Text('Status: Active | $supText', style: const TextStyle(color: _textSub, fontSize: 11), overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _input(String label, TextEditingController ctrl, {bool obscure = false}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(color: _textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _textSub),
        filled: true,
        fillColor: _bg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  3. Manholes Page
// ─────────────────────────────────────────────────────────────────────────────
class _ManholesPage extends StatefulWidget {
  const _ManholesPage();
  @override
  State<_ManholesPage> createState() => _ManholesPageState();
}

class _ManholesPageState extends State<_ManholesPage> {
  List<dynamic> _manholes = [];
  bool _loading = true;
  bool _adding = false;

  final _idCtrl  = TextEditingController();
  final _locCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _locCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('${SocketService.serverUrl}/api/manholes'));
      if (res.statusCode == 200) {
        if (mounted) setState(() { _manholes = jsonDecode(res.body); _loading = false; });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final id  = _idCtrl.text.trim();
    final loc = _locCtrl.text.trim();
    if (id.isEmpty || loc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Manhole ID and Location are required'), backgroundColor: _amber),
      );
      return;
    }
    setState(() => _adding = true);
    try {
      final res = await http.post(
        Uri.parse('${SocketService.serverUrl}/api/manholes'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': id, 'location': loc}),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        _idCtrl.clear();
        _locCtrl.clear();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Manhole added'), backgroundColor: _green));
        _fetch();
      } else {
        final data = jsonDecode(res.body);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${data['error'] ?? 'Failed to add'}'), backgroundColor: _red));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Network error'), backgroundColor: _red));
    }
    if (mounted) setState(() => _adding = false);
  }

  Future<void> _delete(String id) async {
    try {
      await http.delete(Uri.parse('${SocketService.serverUrl}/api/manholes/$id'));
      _fetch();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('MANHOLE MANAGEMENT', style: TextStyle(color: _textSub, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 16),
          _sectionCard(
            title: 'ADD NEW MANHOLE',
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                SizedBox(
                  width: 200,
                  child: TextField(
                    style: const TextStyle(color: _textPrimary),
                    controller: _idCtrl,
                    decoration: InputDecoration(
                      labelText: 'Manhole ID',
                      labelStyle: const TextStyle(color: _textSub),
                      hintText: 'e.g. MH-003',
                      hintStyle: const TextStyle(color: _textSub),
                      filled: true,
                      fillColor: _bg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: TextField(
                    style: const TextStyle(color: _textPrimary),
                    controller: _locCtrl,
                    decoration: InputDecoration(
                      labelText: 'Location',
                      labelStyle: const TextStyle(color: _textSub),
                      hintText: 'e.g. Solapur 3rd Street',
                      hintStyle: const TextStyle(color: _textSub),
                      filled: true,
                      fillColor: _bg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                  ),
                  onPressed: _adding ? null : _add,
                  child: _adding
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('ADD MANHOLE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _sectionCard(
            title: 'CONFIGURED MANHOLES',
            child: _loading
                ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                : _manholes.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No manholes configured.', style: TextStyle(color: _textSub)),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(_surfaceAlt),
                          columns: const [
                            DataColumn(label: Text('ID', style: TextStyle(color: _textSub, fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Location', style: TextStyle(color: _textSub, fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Status', style: TextStyle(color: _textSub, fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Action', style: TextStyle(color: _textSub, fontWeight: FontWeight.bold))),
                          ],
                          rows: _manholes.map((m) => DataRow(cells: [
                            DataCell(Text(m['id'] ?? '', style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.bold))),
                            DataCell(Text(m['location'] ?? '', style: const TextStyle(color: _textPrimary))),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _statusColor(m['status'] ?? 'SAFE').withAlpha(30),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  m['status'] ?? 'SAFE',
                                  style: TextStyle(color: _statusColor(m['status'] ?? 'SAFE'), fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            DataCell(
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: _red, size: 20),
                                tooltip: 'Delete Manhole',
                                onPressed: () => _delete(m['id']),
                              ),
                            ),
                          ])).toList(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  4. Assignments Page
// ─────────────────────────────────────────────────────────────────────────────
class _AssignmentsPage extends StatefulWidget {
  const _AssignmentsPage();
  @override
  State<_AssignmentsPage> createState() => _AssignmentsPageState();
}

class _AssignmentsPageState extends State<_AssignmentsPage> {
  final AuthService _auth = AuthService();
  List<dynamic> _users = [];
  List<dynamic> _manholes = [];
  List<dynamic> _assignments = [];

  String? _supId;
  String? _workerId;
  String? _zoneId;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await _auth.loadSession();
    _users = await _auth.fetchUsers();
    try {
      final rm = await http.get(Uri.parse('${SocketService.serverUrl}/api/manholes'));
      if (rm.statusCode == 200) _manholes = jsonDecode(rm.body);

      final ra = await http.get(Uri.parse('${SocketService.serverUrl}/api/assignments'));
      if (ra.statusCode == 200) _assignments = jsonDecode(ra.body);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _assignSupToZone() async {
    if (_supId == null || _zoneId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select Supervisor and Zone'), backgroundColor: _amber));
      return;
    }
    try {
      await http.post(
        Uri.parse('${SocketService.serverUrl}/api/assignments'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'supervisorId': _supId, 'zoneId': _zoneId}),
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Supervisor assigned to zone'), backgroundColor: _green));
      _loadAll();
    } catch (_) {}
  }

  Future<void> _assignWorkerToSup() async {
    if (_workerId == null || _supId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select Worker and Supervisor'), backgroundColor: _amber));
      return;
    }
    try {
      await http.post(
        Uri.parse('${SocketService.serverUrl}/api/assignments'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'workerId': _workerId, 'supervisorId': _supId}),
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Worker assigned to supervisor'), backgroundColor: _green));
      _loadAll();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final sups    = _users.where((u) => u['role'] == 'supervisor').toList();
    final workers = _users.where((u) => u['role'] == 'worker').toList();
    final isWide  = MediaQuery.of(context).size.width > 800;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('WORKFORCE ASSIGNMENTS', style: TextStyle(color: _textSub, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 16),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildSupZoneCard(sups)),
                const SizedBox(width: 24),
                Expanded(child: _buildWorkerSupCard(workers, sups)),
              ],
            )
          else ...[
            _buildSupZoneCard(sups),
            const SizedBox(height: 24),
            _buildWorkerSupCard(workers, sups),
          ],
          const SizedBox(height: 24),
          _sectionCard(
            title: 'CURRENT ASSIGNMENTS',
            child: _assignments.isEmpty
                ? const Text('No assignments configured.', style: TextStyle(color: _textSub))
                : Column(
                    children: _assignments.map((a) {
                      if (a['type'] == 'supervisor_zone') {
                        final s = _users.firstWhere((x) => x['id'] == a['supervisorId'], orElse: () => {'username': 'Unknown'} as dynamic);
                        return ListTile(
                          leading: const Icon(Icons.shield, color: _amber),
                          title: Text('Supervisor: ${s['username']}', style: const TextStyle(color: _textPrimary), overflow: TextOverflow.ellipsis),
                          subtitle: Text('Assigned to Manhole: ${a['zoneId']}', style: const TextStyle(color: _textSub), overflow: TextOverflow.ellipsis),
                        );
                      } else {
                        final w = _users.firstWhere((x) => x['id'] == a['workerId'], orElse: () => {'username': 'Unknown'} as dynamic);
                        final s = _users.firstWhere((x) => x['id'] == a['supervisorId'], orElse: () => {'username': 'Unknown'} as dynamic);
                        return ListTile(
                          leading: const Icon(Icons.person, color: _blue),
                          title: Text('Worker: ${w['username']}', style: const TextStyle(color: _textPrimary), overflow: TextOverflow.ellipsis),
                          subtitle: Text('Reports to: ${s['username']}', style: const TextStyle(color: _textSub), overflow: TextOverflow.ellipsis),
                        );
                      }
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupZoneCard(List sups) {
    return _sectionCard(
      title: 'ASSIGN SUPERVISOR → MANHOLE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _supId,
            dropdownColor: _surfaceAlt,
            style: const TextStyle(color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Select Supervisor',
              labelStyle: const TextStyle(color: _textSub),
              filled: true,
              fillColor: _bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
            items: sups.map((s) => DropdownMenuItem<String>(value: s['id'], child: Text(s['username'], overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => _supId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _zoneId,
            dropdownColor: _surfaceAlt,
            style: const TextStyle(color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Select Manhole',
              labelStyle: const TextStyle(color: _textSub),
              filled: true,
              fillColor: _bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
            items: _manholes.map((m) => DropdownMenuItem<String>(value: m['id'], child: Text('${m['id']} — ${m['location']}', overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => _zoneId = v),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _blue, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _assignSupToZone,
            child: const Text('ASSIGN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerSupCard(List workers, List sups) {
    return _sectionCard(
      title: 'ASSIGN WORKER → SUPERVISOR',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _workerId,
            dropdownColor: _surfaceAlt,
            style: const TextStyle(color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Select Worker',
              labelStyle: const TextStyle(color: _textSub),
              filled: true,
              fillColor: _bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
            items: workers.map((w) => DropdownMenuItem<String>(value: w['id'], child: Text(w['username'], overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => _workerId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _supId,
            dropdownColor: _surfaceAlt,
            style: const TextStyle(color: _textPrimary),
            decoration: InputDecoration(
              labelText: 'Select Supervisor',
              labelStyle: const TextStyle(color: _textSub),
              filled: true,
              fillColor: _bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
            items: sups.map((s) => DropdownMenuItem<String>(value: s['id'], child: Text(s['username'], overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => _supId = v),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _green, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _assignWorkerToSup,
            child: const Text('ASSIGN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  5. Alerts Page
// ─────────────────────────────────────────────────────────────────────────────
class _AlertsPage extends StatelessWidget {
  const _AlertsPage();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('REAL-TIME INCIDENT LOG', style: TextStyle(color: _textSub, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 16),
          _sectionCard(
            title: 'LATEST ALERTS (${state.activeAlerts.length})',
            child: state.activeAlerts.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(Icons.check_circle_outline, color: _green, size: 48),
                          SizedBox(height: 12),
                          Text('No active alerts.', style: TextStyle(color: _textSub)),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: state.activeAlerts.map((a) {
                      final isCrit = a.severity == AlertSeverity.critical;
                      final clr    = isCrit ? _red : _amber;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: clr.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border(left: BorderSide(color: clr, width: 4)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(isCrit ? Icons.warning_amber_rounded : Icons.info_outline, color: clr),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a.message, style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 2),
                                  const SizedBox(height: 4),
                                  Text(
                                    a.timestamp.toLocal().toString().split('.')[0],
                                    style: const TextStyle(color: _textSub, fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Shared UI Components
// ─────────────────────────────────────────────────────────────────────────────
Widget _sectionCard({required String title, required Widget child}) {
  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _border),
      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: const TextStyle(color: _textSub, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 16),
        Container(height: 1, color: _border),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}
