import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../providers/app_state.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';
import 'login_screen.dart';
import '../models/safety_status.dart';

const String _kBaseUrl = SocketService.serverUrl;

// ─────────────────────────────────────────────────────────────────────────────
//  Worker Dashboard – multi-page (Home / Session / History)
// ─────────────────────────────────────────────────────────────────────────────
class WorkerDashboard extends StatefulWidget {
  const WorkerDashboard({super.key});
  @override
  State<WorkerDashboard> createState() => _WorkerDashboardState();
}

class _WorkerDashboardState extends State<WorkerDashboard> {
  int _navIndex = 0;
  final AuthService _authService = AuthService();
  String _workerId = '';
  String _username = '';

  @override
  void initState() {
    super.initState();
    _authService.loadSession().then((_) {
      setState(() {
        _workerId = _decodeWorkerIdFromToken(_authService.token ?? '');
        _username = _workerId;
      });
      // Tell backend/socket who this worker is
      context.read<AppState>().socketService.emitEvent('worker_identify', {'workerId': _workerId});
    });
  }

  String _decodeWorkerIdFromToken(String token) {
    try {
      final parts   = token.split('.');
      if (parts.length < 2) return 'worker';
      final payload = base64Url.normalize(parts[1]);
      final decoded = jsonDecode(utf8.decode(base64Url.decode(payload)));
      return decoded['username']?.toString() ?? decoded['id']?.toString() ?? 'worker';
    } catch (_) { return 'worker'; }
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>(); // triggers rebuild on state change
    final pages       = [
      _WorkerHomePage(workerId: _workerId, username: _username, onLogout: _logout),
      _WorkerSessionPage(workerId: _workerId),
      _WorkerHistoryPage(workerId: _workerId),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1C),
      body: pages[_navIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF111827),
        selectedItemColor: const Color(0xFF3B82F6),
        unselectedItemColor: const Color(0xFF6B7280),
        currentIndex: _navIndex,
        onTap: (i) => setState(() => _navIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined),    activeIcon: Icon(Icons.home),    label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.login_outlined),   activeIcon: Icon(Icons.login),   label: 'Session'),
          BottomNavigationBarItem(icon: Icon(Icons.history_outlined), activeIcon: Icon(Icons.history), label: 'History'),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PAGE 1: HOME — Status + Gas + Safety Indicator
// ─────────────────────────────────────────────────────────────────────────────
class _WorkerHomePage extends StatefulWidget {
  final String workerId;
  final String username;
  final VoidCallback onLogout;
  const _WorkerHomePage({required this.workerId, required this.username, required this.onLogout});
  @override State<_WorkerHomePage> createState() => _WorkerHomePageState();
}

class _WorkerHomePageState extends State<_WorkerHomePage> with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double>   _pulse;
  Map<String, dynamic>? _prediction;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _anim  = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(_anim);
    _fetchPrediction();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _fetchPrediction());
  }

  Future<void> _fetchPrediction() async {
    if (widget.workerId.isEmpty) return;
    try {
      final res = await http.get(Uri.parse('$_kBaseUrl/api/worker/predict/${widget.workerId}')).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200 && mounted) setState(() => _prediction = jsonDecode(res.body));
    } catch (_) {}
  }

  @override
  void dispose() { _anim.dispose(); _pollTimer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final state       = context.watch<AppState>();
    final sensor      = state.bottomData;
    final safetyStr   = state.overallStatus == SafetyStatus.block   ? 'DANGER'
                      : state.overallStatus == SafetyStatus.caution ? 'CAUTION' : 'SAFE';

    Color   statusColor;
    IconData statusIcon;
    String  statusText;

    if (safetyStr == 'DANGER')       { statusColor = const Color(0xFFF44336); statusIcon = Icons.warning_rounded;      statusText = 'EXIT IMMEDIATELY'; }
    else if (safetyStr == 'CAUTION') { statusColor = const Color(0xFFFFC107); statusIcon = Icons.priority_high_rounded; statusText = 'BE ALERT'; }
    else                             { statusColor = const Color(0xFF22C55E); statusIcon = Icons.check_circle_outline;  statusText = 'SAFE TO WORK'; }

    final predLabel = _prediction?['prediction'] as String? ?? '-';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Top Bar ──
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(color: Color(0xFF1F2937), shape: BoxShape.circle),
                  child: const Icon(Icons.engineering, color: Color(0xFF3B82F6), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('WORKER: ${widget.username.toUpperCase()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
                IconButton(icon: const Icon(Icons.logout, color: Color(0xFF6B7280)), onPressed: widget.onLogout),
              ],
            ),
            const SizedBox(height: 24),

            // ── Status Indicator ──
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Transform.scale(
                scale: safetyStr == 'DANGER' ? _pulse.value : 1.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.6), width: 2),
                    boxShadow: [BoxShadow(color: statusColor.withOpacity(0.15), blurRadius: 20, spreadRadius: 2)],
                  ),
                  child: Column(
                    children: [
                      Icon(statusIcon, color: statusColor, size: 56),
                      const SizedBox(height: 12),
                      Text(statusText, style: TextStyle(color: statusColor, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                        child: Text(safetyStr, style: TextStyle(color: statusColor, fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Live Gas Data ──
            _buildGasGrid(sensor),
            const SizedBox(height: 16),

            // ── Alert Banner ──
            if (state.activeAlerts.isNotEmpty) ...[
              _buildAlertBanner(state.activeAlerts.first.message),
              const SizedBox(height: 16),
            ],

            // ── Prediction ──
            _buildPredictionCard(predLabel),
          ],
        ),
      ),
    );
  }



  Widget _buildGasGrid(dynamic sensor) {
    final gasValues = [
      {'label': 'H₂S', 'value': '${sensor.h2s.toStringAsFixed(1)} ppm', 'danger': sensor.h2s > 5},
      {'label': 'CH₄', 'value': '${sensor.ch4.toStringAsFixed(1)} %',   'danger': sensor.ch4 > 0.5},
      {'label': 'CO',  'value': '${sensor.co.toStringAsFixed(1)} ppm',  'danger': sensor.co > 25},
      {'label': 'O₂',  'value': '${sensor.o2.toStringAsFixed(1)} %',    'danger': sensor.o2 < 20.0},
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.4,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: gasValues.map((g) {
        final isDanger = g['danger'] as bool;
        final c = isDanger ? const Color(0xFFF44336) : const Color(0xFF22C55E);
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isDanger ? c.withOpacity(0.6) : const Color(0xFF1F2937)),
          ),
          child: Row(
            children: [
              Container(width: 3, height: 28, color: c, margin: const EdgeInsets.only(right: 8)),
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(g['label'] as String, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10)),
                Text(g['value'] as String, style: TextStyle(color: c, fontSize: 15, fontWeight: FontWeight.bold)),
              ]),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAlertBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
      ),
      child: Row(children: [
        const Icon(Icons.campaign_rounded, color: Colors.redAccent, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
      ]),
    );
  }

  Widget _buildPredictionCard(String prediction) {
    Color predColor;
    if (prediction == 'BLOCK')        predColor = const Color(0xFFF44336);
    else if (prediction == 'CAUTION') predColor = const Color(0xFFFFC107);
    else                              predColor = const Color(0xFF22C55E);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: predColor.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.psychology_outlined, color: predColor, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('AI SAFETY PREDICTION', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 10, letterSpacing: 1.2)),
            const SizedBox(height: 4),
            Text(prediction, style: TextStyle(color: predColor, fontSize: 16, fontWeight: FontWeight.bold)),
          ])),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PAGE 2: SESSION — Entry Flow + Timer
// ─────────────────────────────────────────────────────────────────────────────
class _WorkerSessionPage extends StatefulWidget {
  final String workerId;
  const _WorkerSessionPage({required this.workerId});
  @override State<_WorkerSessionPage> createState() => _WorkerSessionPageState();
}

class _WorkerSessionPageState extends State<_WorkerSessionPage> {
  // Timer state
  Timer? _exposureTimer;
  int    _elapsedSeconds = 0;
  bool   _timerRunning   = false;

  // Session tracking
  String  _manholeId      = 'MH-SOLAPUR-01';
  String? _sessionId;
  DateTime? _startTime;
  bool    _isSendingScan  = false;
  bool    _isPanic        = false;

  // Exposure data for history
  double _avgGas = 0;
  double _maxGas = 0;
  int    _gasReadings = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Listen for approval/block events from AppState
      context.read<AppState>().addListener(_onStateChanged);
    });
  }

  void _onStateChanged() {
    if (!mounted) return;
    setState(() {}); // just trigger rebuild; state is read in build
  }

  @override
  void dispose() {
    _exposureTimer?.cancel();
    try { context.read<AppState>().removeListener(_onStateChanged); } catch (_) {}
    super.dispose();
  }

  // ── SCAN – sends HTTP + socket entry_request ──────────────────────────────
  Future<void> _doScan() async {
    if (_isSendingScan) return;
    setState(() => _isSendingScan = true);
    try {
      // 1. Register scan with backend
      final res = await http.post(
        Uri.parse('$_kBaseUrl/api/worker/entry-scan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'workerId': widget.workerId, 'manholeId': _manholeId}),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        // 2. Send entry request via socket → goes to supervisor
        final state = context.read<AppState>();
        state.sendEntryRequest(workerId: widget.workerId, manholeId: _manholeId);
        _sessionId = state.entrySessionId;
        _showSnack('📡 Request sent [${_sessionId ?? ""}] — Awaiting supervisor…', const Color(0xFF3B82F6));
      } else {
        _showSnack('⚠️ Scan failed. Try again.', const Color(0xFFF44336));
      }
    } catch (_) {
      _showSnack('⚠️ Network error', const Color(0xFFF44336));
    } finally {
      if (mounted) setState(() => _isSendingScan = false);
    }
  }

  // ── ENTER – only if approved; starts timer ────────────────────────────────
  void _doEnter() {
    final state = context.read<AppState>();
    if (state.entryStatus != EntryStatus.approved) return;
    setState(() {
      _startTime     = DateTime.now();
      _timerRunning  = true;
      _elapsedSeconds = 0;
    });
    _exposureTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
      // Track gas for averaging
      final sensor = context.read<AppState>().bottomData;
      _gasReadings++;
      _avgGas = (_avgGas * (_gasReadings - 1) + sensor.h2s) / _gasReadings;
      if (sensor.h2s > _maxGas) _maxGas = sensor.h2s;
    });
    _showSnack('⏱ Timer started — stay safe!', const Color(0xFF22C55E));
  }

  // ── EXIT – stops timer + saves history ──────────────────────────────────
  Future<void> _doExit() async {
    _exposureTimer?.cancel();
    setState(() => _timerRunning = false);
    final endTime = DateTime.now();

    // Save exposure history
    if (_startTime != null) {
      try {
        await http.post(
          Uri.parse('$_kBaseUrl/exposure/save'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'workerId':  widget.workerId,
            'manholeId': _manholeId,
            'startTime': _startTime!.toIso8601String(),
            'endTime':   endTime.toIso8601String(),
            'duration':  _elapsedSeconds,
            'avgGas':    _avgGas,
            'maxGas':    _maxGas,
          }),
        ).timeout(const Duration(seconds: 6));
      } catch (_) {}
    }

    // Reset entry status
    context.read<AppState>().setEntryStatus(EntryStatus.idle);
    setState(() {
      _elapsedSeconds = 0;
      _startTime      = null;
      _sessionId      = null;
      _avgGas         = 0;
      _maxGas         = 0;
      _gasReadings    = 0;
    });
    _showSnack('✅ Session ended. Stay safe!', const Color(0xFF22C55E));
  }

  // ── PANIC ─────────────────────────────────────────────────────────────────
  Future<void> _doPanic() async {
    if (_isPanic) return;
    setState(() => _isPanic = true);
    try {
      await http.post(
        Uri.parse('$_kBaseUrl/api/worker/panic'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'workerId': widget.workerId, 'manholeId': _manholeId}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
    _showPanicDialog();
  }

  void _showPanicDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.red.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('🚨 PANIC TRIGGERED', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        content: const Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Help is on the way.\nStay calm.', style: TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
          SizedBox(height: 16),
          Icon(Icons.check_circle, color: Colors.greenAccent, size: 50),
        ]),
        actions: [
          SizedBox(width: double.infinity, child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: () { if (mounted) setState(() => _isPanic = false); Navigator.pop(context); },
            child: const Text('ACKNOWLEDGE', style: TextStyle(color: Colors.white, letterSpacing: 1.5)),
          )),
        ],
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 2)));
  }

  String get _timerDisplay {
    final m = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedSeconds  % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final state       = context.watch<AppState>();
    final entryStatus = state.entryStatus;
    final sensor      = state.bottomData;

    Color entryBgColor;
    String entryLabel;
    IconData entryIcon;

    switch (entryStatus) {
      case EntryStatus.approved: entryBgColor = const Color(0xFF22C55E); entryLabel = 'APPROVED'; entryIcon = Icons.check_circle; break;
      case EntryStatus.blocked:  entryBgColor = const Color(0xFFF44336); entryLabel = 'BLOCKED';  entryIcon = Icons.block;         break;
      case EntryStatus.waiting:  entryBgColor = const Color(0xFFFFC107); entryLabel = 'WAITING';  entryIcon = Icons.hourglass_top; break;
      default:                   entryBgColor = const Color(0xFF374151); entryLabel = 'IDLE';     entryIcon = Icons.radio_button_unchecked;
    }

    final canEnter = entryStatus == EntryStatus.approved && !_timerRunning;
    final canExit  = _timerRunning;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──
            const Text('SESSION CONTROL', style: TextStyle(color: Color(0xFF6B7280), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            const SizedBox(height: 16),

            // ── Entry Status Card ──
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: entryBgColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: entryBgColor.withOpacity(0.6), width: 2),
              ),
              child: Column(
                children: [
                  Icon(entryIcon, color: entryBgColor, size: 36),
                  const SizedBox(height: 10),
                  Text('ENTRY STATUS: $entryLabel', style: TextStyle(color: entryBgColor, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  if (entryStatus == EntryStatus.waiting) ...[
                    const SizedBox(height: 8),
                    const Text('Awaiting supervisor approval…', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                  ],
                  if (entryStatus == EntryStatus.blocked) ...[
                    const SizedBox(height: 8),
                    const Text('Entry denied by supervisor. Do NOT enter.', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Manhole ID input ──
            TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Manhole ID',
                labelStyle: const TextStyle(color: Color(0xFF6B7280)),
                filled: true, fillColor: const Color(0xFF111827),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                hintText: 'e.g. MH-001',
                hintStyle: const TextStyle(color: Color(0xFF374151)),
              ),
              onChanged: (v) => setState(() => _manholeId = v.isNotEmpty ? v : 'MH-SOLAPUR-01'),
            ),
            const SizedBox(height: 16),

            // ── Action Buttons ──
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _actionBtn('SCAN MH', Icons.search, const Color(0xFF3B82F6), entryStatus == EntryStatus.idle || entryStatus == EntryStatus.blocked ? _doScan : null, loading: _isSendingScan),
                _actionBtn('ENTER',   Icons.login,  const Color(0xFF22C55E), canEnter ? _doEnter : null),
                _actionBtn('EXIT',    Icons.logout, const Color(0xFFF59E0B), canExit  ? _doExit  : null),
              ],
            ),
            const SizedBox(height: 20),

            // ── Exposure Timer ──
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _timerRunning ? const Color(0xFF22C55E).withOpacity(0.5) : const Color(0xFF1F2937)),
              ),
              child: Row(
                children: [
                  Icon(Icons.timer_outlined, color: _timerRunning ? const Color(0xFF22C55E) : const Color(0xFF4B5563), size: 28),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('EXPOSURE TIMER', style: TextStyle(color: Color(0xFF6B7280), fontSize: 10, letterSpacing: 1.2)),
                    Text(_timerDisplay, style: TextStyle(color: _timerRunning ? const Color(0xFF22C55E) : Colors.white54, fontSize: 28, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                  ])),
                  if (_timerRunning)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFF22C55E).withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.5))),
                      child: const Text('ACTIVE', style: TextStyle(color: Color(0xFF22C55E), fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Live gas summary ──
            _buildLiveGasSummary(sensor),
            const SizedBox(height: 24),

            // ── PANIC button ──
            GestureDetector(
              onTap: _doPanic,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: Colors.red.shade800.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.7), width: 2),
                  boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.2), blurRadius: 15)],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
                    SizedBox(width: 12),
                    Text('EMERGENCY PANIC', style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback? onTap, {bool loading = false}) {
    return Opacity(
      opacity: onTap == null ? 0.38 : 1.0,
      child: ElevatedButton.icon(
        icon: loading ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: color)) : Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.1),
          foregroundColor: color,
          side: BorderSide(color: color.withOpacity(0.6)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildLiveGasSummary(dynamic sensor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF1F2937))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('LIVE GAS LEVELS', style: TextStyle(color: Color(0xFF6B7280), fontSize: 10, letterSpacing: 1.2)),
        const SizedBox(height: 10),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _pill('H₂S', '${sensor.h2s.toStringAsFixed(1)} ppm', sensor.h2s > 5),
          _pill('CH₄', '${sensor.ch4.toStringAsFixed(1)} %',   sensor.ch4 > 0.5),
          _pill('CO',  '${sensor.co.toStringAsFixed(1)} ppm',  sensor.co > 25),
          _pill('O₂',  '${sensor.o2.toStringAsFixed(1)} %',    sensor.o2 < 20.0),
        ]),
      ]),
    );
  }

  Widget _pill(String label, String value, bool danger) {
    final c = danger ? const Color(0xFFF44336) : const Color(0xFF22C55E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: c.withOpacity(0.4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 10)),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 11)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PAGE 3: HISTORY — Exposure Records
// ─────────────────────────────────────────────────────────────────────────────
class _WorkerHistoryPage extends StatefulWidget {
  final String workerId;
  const _WorkerHistoryPage({required this.workerId});
  @override State<_WorkerHistoryPage> createState() => _WorkerHistoryPageState();
}

class _WorkerHistoryPageState extends State<_WorkerHistoryPage> {
  List<dynamic> _history = [];
  bool _loading = true;
  Map<String, dynamic>? _prediction;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (widget.workerId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final resList = await Future.wait([
        http.get(Uri.parse('$_kBaseUrl/exposure/history/${widget.workerId}')).timeout(const Duration(seconds: 6)),
        http.get(Uri.parse('$_kBaseUrl/api/worker/predict/${widget.workerId}')).timeout(const Duration(seconds: 6)),
      ]);

      if (mounted) {
        setState(() {
          _loading = false;
          if (resList[0].statusCode == 200) {
            final data = jsonDecode(resList[0].body);
            _history = (data['records'] as List? ?? []).reversed.toList();
          }
          if (resList[1].statusCode == 200) {
            _prediction = jsonDecode(resList[1].body);
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final predLabel = _prediction?['prediction'] as String? ?? '-';
    final totalExp  = _prediction?['totalExposure'] as int?  ?? 0;

    Color predColor;
    if (predLabel == 'BLOCK')        predColor = const Color(0xFFF44336);
    else if (predLabel == 'CAUTION') predColor = const Color(0xFFFFC107);
    else                             predColor = const Color(0xFF22C55E);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Expanded(child: Text('EXPOSURE HISTORY', style: TextStyle(color: Color(0xFF6B7280), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5))),
              IconButton(icon: const Icon(Icons.refresh, color: Color(0xFF6B7280), size: 20), onPressed: _fetch),
            ]),
            const SizedBox(height: 16),

            // ── Prediction summary ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: predColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: predColor.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, color: predColor, size: 28),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('24H SAFETY PREDICTION', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 10, letterSpacing: 1.2)),
                    const SizedBox(height: 4),
                    Text(predLabel, style: TextStyle(color: predColor, fontSize: 18, fontWeight: FontWeight.bold)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    const Text('TOTAL EXP.', style: TextStyle(color: Color(0xFF6B7280), fontSize: 9)),
                    Text('$totalExp', style: TextStyle(color: predColor, fontSize: 20, fontWeight: FontWeight.bold)),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (_loading)
              const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)))
            else if (_history.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Column(children: [
                  Icon(Icons.history, color: Color(0xFF374151), size: 48),
                  SizedBox(height: 12),
                  Text('No exposure records yet', style: TextStyle(color: Color(0xFF6B7280))),
                  SizedBox(height: 4),
                  Text('Records appear after you EXIT a session', style: TextStyle(color: Color(0xFF374151), fontSize: 12)),
                ])),
              )
            else
              ..._history.map((r) => _buildHistoryCard(r)),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(dynamic r) {
    final duration = r['duration'] as int? ?? 0;
    final m = (duration ~/ 60).toString().padLeft(2, '0');
    final s = (duration  % 60).toString().padLeft(2, '0');
    final date = r['startTime'] != null
        ? DateTime.tryParse(r['startTime'].toString())?.toLocal()
        : null;
    final avgGas = (r['avgGas'] as num?)?.toStringAsFixed(1) ?? '-';
    final maxGas = (r['maxGas'] as num?)?.toStringAsFixed(1) ?? '-';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFF3B82F6).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.timeline, color: Color(0xFF3B82F6), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r['manholeId']?.toString() ?? 'Unknown Manhole', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              date != null ? '${date.day}/${date.month}/${date.year}  ${date.hour}:${date.minute.toString().padLeft(2,'0')}' : 'Unknown date',
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
            ),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$m:$s', style: const TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'monospace')),
            const SizedBox(height: 2),
            Text('Avg H₂S: $avgGas  Max: $maxGas', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 10)),
          ]),
        ],
      ),
    );
  }
}
