import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';
import '../providers/app_state.dart';
import '../models/sensor_data.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import '../models/safety_status.dart';
import '../services/socket_service.dart';
import 'package:http/http.dart' as http;

// ─── Chart data point ────────────────────────────────────────────────────────
class _ChartPoint {
  final int index;
  final double h2s;
  final double ch4;
  _ChartPoint(this.index, this.h2s, this.ch4);
}

class SupervisorDashboard extends StatefulWidget {
  const SupervisorDashboard({super.key});
  @override
  State<SupervisorDashboard> createState() => _SupervisorDashboardState();
}

class _SupervisorDashboardState extends State<SupervisorDashboard> {
  late Timer _timer;
  String _currentTime = '';
  final AuthService _authService = AuthService();

  // ── Simulation Control ──────────────────────────────────────────────────────
  // bool _isManualMode = false;
  bool isPreEntryMode = true;

  String _currentMode = 'AUTO'; // 'AUTO' or 'MANUAL'
  double _manualH2S = 2.0;
  double _manualCH4 = 0.1;
  double _manualCO  = 1.0;
  double _manualO2  = 20.9;

  // Default target device for manual control
  static const String _controlDeviceId = 'SOLAPUR_PROBE_BOTTOM';

  // ── Worker Selection ────────────────────────────────────────────────────────
  String? _selectedWorkerId;
  // Predefined worker list (in production fetch from backend)
  final List<Map<String, String>> _workerList = [
    {'id': 'WORKER_001', 'name': 'Worker #001'},
    {'id': 'WORKER_002', 'name': 'Worker #002'},
    {'id': 'WORKER_003', 'name': 'Worker #003'},
  ];

  // ── Gas Trend Chart ─────────────────────────────────────────────────────────
  final List<_ChartPoint> _chartData = [];
  int _chartIndex = 0;
  static const int _maxChartPoints = 25;

  @override
  void initState() {
    super.initState();
    _authService.loadSession();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateTime();
    });
    // Listen for new sensor data to update chart
     
      WidgetsBinding.instance.addPostFrameCallback((_) {
            final socket = context.read<AppState>().socketService;
            socket.onEvent('mode_changed', (data) {
                  if (!mounted) {
                      return;
                }
            setState((){
               _currentMode = data['mode'] ;// Update mode if sent by backend
         });
       
     });

   
      context.read<AppState>().addListener(_onStateChanged);
    });
  }

  void _onStateChanged() {
      if (!mounted) return;

      final state = context.read<AppState>();
      final d = state.currentData;

  // CRITICAL FIX: ignore AUTO when manual mode
      if (_currentMode == "MANUAL" && d.source == 'auto') {
        return;
      }

      setState(() {
        _chartData.add(_ChartPoint(_chartIndex++, d.h2s, d.ch4));
        if (_chartData.length > _maxChartPoints) {
      _chartData.removeAt(0);
    }
    });
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _currentTime =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    context.read<AppState>().removeListener(_onStateChanged);
    super.dispose();
  }

  // ── Mode switch ─────────────────────────────────────────────────────────────
  // ✅ FIXED: Uses correct socket events that STOP simulation when MANUAL
  void _setMode(bool manual) {
    setState(() => _currentMode = manual ? 'MANUAL' : 'AUTO');
    final state = context.read<AppState>();

    if (manual) {
      debugPrint('[SUPERVISOR] MANUAL MODE ON — simulation will pause');
      // Emit set_manual_mode with current values → backend stops simulation
      state.socketService.emitEvent('set_manual_mode', {
        'h2s': _manualH2S,
        'ch4': _manualCH4,
        'co':  _manualCO,
        'o2':  _manualO2,
      });
    } else {
      debugPrint('[SUPERVISOR] AUTO MODE — simulation resumes');
      state.socketService.emitEvent('set_auto_mode', null);
      setState(() {
        _manualH2S = 2.0;
        _manualCH4 = 0.1;
        _manualCO  = 1.0;
        _manualO2  = 20.9;
      });
    }
    // ignore: unawaited_futures
    http.post(
      Uri.parse('${SocketService.serverUrl}/api/simulation/mode'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'mode': manual ? 'manual' : 'auto'}),
    ).whenComplete(() {}).catchError((_) => http.Response('', 0));
  }

  // ── Apply manual values (APPLY button) ─────────────────────────────────────
  // Sends manual_sensor_update which also sets global mode=MANUAL
  void _applyManualValues() {
    if (_currentMode != 'MANUAL') return;
    final payload = {
      'deviceId': _controlDeviceId,
      'h2s': _manualH2S,
      'ch4': _manualCH4,
      'co':  _manualCO,
      'o2':  _manualO2,
      'mode': 'MANUAL',
    };
    debugPrint('[SUPERVISOR] Emitting manual_sensor_update: $payload');
    context.read<AppState>().socketService.emitEvent('manual_sensor_update', payload);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✓ Manual values applied & broadcast'),
        backgroundColor: Color(0xFF1A3A1A),
        duration: Duration(seconds: 1),
      ),
    );
  }

  // ── Live emit on slider change ─────────────────────────────────────────────
  // ✅ CRITICAL: called every time a slider moves in MANUAL mode
  void _emitLiveManualUpdate() {
    if (_currentMode != 'MANUAL') return;
    context.read<AppState>().socketService.emitEvent('update_manual_values', {
      'h2s': _manualH2S,
      'ch4': _manualCH4,
      'co':  _manualCO,
      'o2':  _manualO2,
    });
  }

  // ── Worker assignment ───────────────────────────────────────────────────────
  void _assignWorker(String workerId) {
    setState(() => _selectedWorkerId = workerId);
    debugPrint('[SUPERVISOR] Assigning active worker: $workerId');
    context.read<AppState>().socketService.emitEvent('assign_worker', {'workerId': workerId});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Active worker set: $workerId'),
        backgroundColor: const Color(0xFF1A2A3A),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ── Entry control (affects selected worker) ─────────────────────────────────
  void _approveEntry(AppState state) {
    final wId = _selectedWorkerId;
    if (wId == null) {
      _showNoWorkerSnack();
      return;
    }
    state.socketService.emitEvent('approve_entry', {
      'workerId': wId,
      'reason': 'Supervisor Approved Entry',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    // ScaffoldMessenger.of(context).showSnackBar(
    //   const SnackBar(content: Text('Entry Approved'), backgroundColor: Color.fromARGB(255, 157, 186, 157)),
    // );

    ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: const Text(
      'Entry Approved',
      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
    ),
    backgroundColor: const Color(0xFF16A34A), // brighter green
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.all(12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    ),
    duration: const Duration(seconds: 2),
  ),
);
    setState(() => isPreEntryMode = false);
  }

  void _blockEntry(AppState state) {
    final wId = _selectedWorkerId;
    if (wId == null) {
      _showNoWorkerSnack();
      return;
    }
    state.socketService.emitEvent('block_entry', {
      'workerId': wId,
      'reason': 'Supervisor Blocked Entry',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Entry Blocked'), backgroundColor: Color(0xFF3A1A1A)),
    );
  }

  void _showNoWorkerSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Select a worker first'),
        backgroundColor: Color(0xFF3A2A00),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Color _statusColor(SafetyStatus status) {
    switch (status) {
      case SafetyStatus.safe:    return const Color(0xFF4CAF50);
      case SafetyStatus.caution: return const Color(0xFFFFC107);
      case SafetyStatus.block:   return const Color(0xFFF44336);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final statusColor = _statusColor(state.overallStatus);
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: _buildAppBar(state, statusColor),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatusHeader(state, statusColor),
              const SizedBox(height: 10),
              _buildModeBanner(),
              const SizedBox(height: 16),
              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: _buildLeftColumn(state, statusColor)),
                    const SizedBox(width: 16),
                    Expanded(flex: 3, child: _buildRightColumn(state)),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildLeftColumn(state, statusColor),
                    const SizedBox(height: 16),
                    _buildRightColumn(state),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar(AppState state, Color statusColor) {
    return AppBar(
      backgroundColor: const Color(0xFF111827),
      elevation: 0,
      leading: const Padding(
        padding: EdgeInsets.all(10),
        child: Icon(Icons.shield_outlined, color: Color(0xFF3B82F6), size: 24),
      ),
      title: const Text(
        'Global Command Center',
        style: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w700,
          fontSize: 17,
          color: Colors.white,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.logout, color: Color(0xFF9CA3AF), size: 20),
          onPressed: () async {
            await _authService.logout();
            if (mounted) {
              // ignore: use_build_context_synchronously
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            }
          },
        ),
      ],
    );
  }

  // ── Mode Banner ─────────────────────────────────────────────────────────────
  Widget _buildModeBanner() {
    final isPreEntry = isPreEntryMode;
    final color   = isPreEntry ? const Color(0xFFF59E0B) : const Color(0xFF22C55E);
    final icon    = isPreEntry ? Icons.lock_clock    : Icons.sensors;
    final label   = isPreEntry ? 'PRE-ENTRY MODE'    : 'LIVE MONITORING MODE';
    final subtext = isPreEntry
        ? 'Check manhole safety before approving worker entry'
        : 'Worker is inside — monitoring vitals & gas in real-time';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 1.2)),
            Text(subtext, style: TextStyle(color: color.withOpacity(0.7), fontSize: 10)),
          ],
        )),
        if (!isPreEntry)
          GestureDetector(
            onTap: () => setState(() => isPreEntryMode = true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.5)),
              ),
              child: const Text('← PRE-ENTRY', style: TextStyle(color: Color(0xFF3B82F6), fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ),
      ]),
    );
  }

  // ── Status Header ───────────────────────────────────────────────────────────
  Widget _buildStatusHeader(AppState state, Color statusColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: _card(),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _statusBadge(state.overallStatus.name.toUpperCase(), statusColor),
          _headerChip(Icons.people_outline, '${state.activeWorkers.length} Workers'),
          _headerChip(Icons.access_time_outlined, _currentTime),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2A40),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFD97706).withOpacity(0.6)),
            ),
            child: const Text(
              'SUPERVISOR',
              style: TextStyle(
                color: Color(0xFFD97706),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.7)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 13,
          letterSpacing: 1.4,
        ),
      ),
    );
  }

  Widget _headerChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFF9CA3AF), size: 16),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 13)),
      ],
    );
  }

  // ── Columns ─────────────────────────────────────────────────────────────────
  Widget _buildLeftColumn(AppState state, Color statusColor) {
    if (isPreEntryMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ✅ Entry Requests Panel (top priority)
          if (state.pendingEntryRequests.isNotEmpty) ...[
            _buildEntryRequestsPanel(state),
            const SizedBox(height: 16),
          ],
          _buildPreEntryPanel(statusColor, state.overallStatus, state),
          const SizedBox(height: 16),
          _buildWorkerSelector(state),
          const SizedBox(height: 16),
          _buildControlActions(state),
          const SizedBox(height: 16),
          _buildSimulationControlPanel(),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLiveMonitoring(state),
          const SizedBox(height: 16),
          _buildControlActionsLive(state),
        ],
      );
    }
  }

  // ── Pending Entry Requests Panel ────────────────────────────────────────────
  Widget _buildEntryRequestsPanel(AppState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.6), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.notifications_active, color: Color(0xFFF59E0B), size: 16),
            const SizedBox(width: 6),
            _sectionTitle('PENDING ENTRY REQUESTS (${state.pendingEntryRequests.length})', color: const Color(0xFFF59E0B)),
          ]),
          const SizedBox(height: 12),
          ...state.pendingEntryRequests.map((req) {
            final sensor   = state.bottomData;
            final safeStr  = state.overallStatus.name.toUpperCase();
            final safeColor = _statusColor(state.overallStatus);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2235),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1F2937)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.person, color: Color(0xFF3B82F6), size: 16),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Worker: ${req.workerId}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: safeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: safeColor.withOpacity(0.5))),
                      child: Text(safeStr, style: TextStyle(color: safeColor, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text('Manhole: ${req.manholeId}', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
                  const SizedBox(height: 4),
                  Text(
                    'H₂S: ${sensor.h2s.toStringAsFixed(1)} ppm  CH₄: ${sensor.ch4.toStringAsFixed(1)} %  CO: ${sensor.co.toStringAsFixed(1)} ppm  O₂: ${sensor.o2.toStringAsFixed(1)} %',
                    style: const TextStyle(color: Color(0xFF6B7280), fontSize: 10),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_outline, size: 15),
                      label: const Text('APPROVE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50).withOpacity(0.1),
                        foregroundColor: const Color(0xFF4CAF50),
                        side: const BorderSide(color: Color(0xFF4CAF50)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        state.approveWorkerEntry(sessionId: req.sessionId, workerId: req.workerId);
                        setState(() => isPreEntryMode = false);
                      },
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: ElevatedButton.icon(
                      icon: const Icon(Icons.block, size: 15),
                      label: const Text('BLOCK', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF44336).withOpacity(0.1),
                        foregroundColor: const Color(0xFFF44336),
                        side: const BorderSide(color: Color(0xFFF44336)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => state.blockWorkerEntry(sessionId: req.sessionId, workerId: req.workerId),
                    )),
                  ]),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRightColumn(AppState state) {
    if (isPreEntryMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildRealTimeGraph(),
          const SizedBox(height: 16),
          if (state.currentData.mlInsights != null) ...[
            _buildMLInsightsPanel(state.currentData),
          ],
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAlertFeed(state),
        ],
      );
    }
  }

  // ── Pre-Entry Panel ─────────────────────────────────────────────────────────
  Widget _buildPreEntryPanel(Color statusColor, SafetyStatus status, AppState state) {
    final ins = state.currentData.mlInsights;
    final floodRisk  = ins?['flood_risk']  ?? 'LOW';
    final spikeRisk  = ins?['spike_risk']  == true;
    final spikeProb  = ((ins?['spike_probability'] ?? 0.0) as num).toDouble();
    final anomaly    = ins?['anomaly']     == true;
    final expLevel   = ins?['exposure_level'] ?? 'LOW';

    Color riskColor(String v) {
      if (v == 'HIGH') return const Color(0xFFF44336);
      if (v == 'MEDIUM') return const Color(0xFFFFC107);
      return const Color(0xFF4CAF50);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section header ──
          Row(children: [
            const Icon(Icons.sensors, color: Color(0xFF3B82F6), size: 15),
            const SizedBox(width: 6),
            _sectionTitle('GAS PROBE DATA'),
          ]),
          const SizedBox(height: 12),
          // ── TOP / MID / BOTTOM rows ──
          _gasRow('TOP', state.topData),
          const Divider(color: Color(0xFF1F2937), height: 14),
          _gasRow('MID', state.midData),
          const Divider(color: Color(0xFF1F2937), height: 14),
          _gasRow('BTM', state.bottomData),
          const SizedBox(height: 16),
          // ── AI / Risk section ──
          Row(children: [
            const Icon(Icons.psychology_outlined, color: Color(0xFF7C3AED), size: 15),
            const SizedBox(width: 6),
            _sectionTitle('AI / RISK ASSESSMENT', color: const Color(0xFF7C3AED)),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.3)),
            ),
            child: Column(
              children: [
                _aiRiskRow(Icons.foundation, 'Structural Risk', anomaly ? 'DETECTED' : 'Normal',
                    anomaly ? const Color(0xFFF44336) : const Color(0xFF4CAF50)),
                const SizedBox(height: 6),
                _aiRiskRow(Icons.water, 'Flood Risk', floodRisk, riskColor(floodRisk)),
                const SizedBox(height: 6),
                _aiRiskRow(Icons.bolt, 'Gas Spike Prediction',
                    spikeRisk ? 'HIGH (${(spikeProb * 100).toStringAsFixed(0)}%)' : 'Low',
                    spikeRisk ? const Color(0xFFF44336) : const Color(0xFF4CAF50)),
                const SizedBox(height: 6),
                _aiRiskRow(Icons.thermostat, 'Exposure Level', expLevel, riskColor(expLevel)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // ── Final Status badge ──
          Row(children: [
            const Icon(Icons.verified_outlined, color: Color(0xFF9CA3AF), size: 15),
            const SizedBox(width: 6),
            _sectionTitle('FINAL STATUS'),
          ]),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor.withOpacity(0.7), width: 2),
            ),
            child: Text(
              status.name.toUpperCase(),
              style: TextStyle(
                color: statusColor,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiRiskRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 6),
        Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _gasRow(String label, SensorData data) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(label, style: const TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.w700, fontSize: 12)),
        ),
        Expanded(
          child: Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _gasPill('H₂S', data.h2s, 'ppm'),
              _gasPill('CH₄', data.ch4, '%'),
              _gasPill('CO',  data.co,  'ppm'),
              _gasPill('O₂',  data.o2,  '%'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _gasPill(String label, double value, String unit) {
    return Column(
      children: [
        Text(value.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        Text('$label($unit)', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 10)),
      ],
    );
  }

  // ── Worker Selector ─────────────────────────────────────────────────────────
  Widget _buildWorkerSelector(AppState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('SELECT ACTIVE WORKER'),
          const SizedBox(height: 12),
          ..._workerList.map((w) {
            final isSelected = _selectedWorkerId == w['id'];
            return GestureDetector(
              onTap: () => _assignWorker(w['id']!),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF1A2A40) : const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFF1F2937),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFF4B5563),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      w['name']!,
                      style: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFF9CA3AF),
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    if (isSelected)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.5)),
                        ),
                        child: const Text(
                          'SELECTED',
                          style: TextStyle(color: Color(0xFF3B82F6), fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Live Worker Monitoring ──────────────────────────────────────────────────
  Widget _buildLiveMonitoring(AppState state) {
    final allWorkers = state.activeWorkers;
    final workers = _selectedWorkerId == null
        ? allWorkers
        : allWorkers.where((w) => w.workerId == _selectedWorkerId).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.sensors_outlined, color: Color(0xFF22C55E), size: 15),
            const SizedBox(width: 6),
            Expanded(child: _sectionTitle('LIVE WORKER MONITORING', color: const Color(0xFF22C55E))),
            Container(
              width: 8, height: 8,
              decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            const Text('LIVE', style: TextStyle(color: Color(0xFF22C55E), fontSize: 10, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          if (workers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(children: [
                  Icon(Icons.person_off_outlined, color: Color(0xFF374151), size: 36),
                  SizedBox(height: 8),
                  Text('No active workers inside', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
                  SizedBox(height: 4),
                  Text('Worker must be inside the manhole', style: TextStyle(color: Color(0xFF374151), fontSize: 11)),
                ]),
              ),
            )
          else
            ...workers.map((worker) {
              final mData = worker.resolveData(state.deviceData);
              final sColor = _statusColor(worker.status);
              final hrOk   = mData.heartRate > 0;
              final spo2Ok = mData.spo2 > 0;
              final motion = mData.vibration > 10 ? 'High Vibration' : (mData.vibration > 0 ? 'Active' : 'Stable');
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sColor.withOpacity(0.4), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Worker header
                    Row(children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: sColor.withOpacity(0.15),
                        child: Icon(Icons.person, color: sColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(worker.displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                          Text(worker.workerId, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
                        ],
                      )),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: sColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: sColor.withOpacity(0.6)),
                        ),
                        child: Text(worker.status.name.toUpperCase(),
                            style: TextStyle(color: sColor, fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    // Vital Band data
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF1F2937)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.watch_outlined, color: Color(0xFF60A5FA), size: 12),
                            const SizedBox(width: 4),
                            const Text('VITAL BAND', style: TextStyle(color: Color(0xFF60A5FA), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                          ]),
                          const SizedBox(height: 8),
                          Wrap(spacing: 16, runSpacing: 6, children: [
                            _vitalChip(Icons.favorite, 'HR', hrOk ? '${mData.heartRate} bpm' : '--',
                                mData.heartRate > 100 ? const Color(0xFFF44336) : const Color(0xFF22C55E)),
                            _vitalChip(Icons.air, 'SpO₂', spo2Ok ? '${mData.spo2}%' : '--',
                                mData.spo2 < 95 ? const Color(0xFFF44336) : const Color(0xFF22C55E)),
                            _vitalChip(Icons.vibration, 'Motion', motion, const Color(0xFF94A3B8)),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Gas Badge data
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF1F2937)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.badge_outlined, color: Color(0xFFF97316), size: 12),
                            const SizedBox(width: 4),
                            const Text('GAS BADGE', style: TextStyle(color: Color(0xFFF97316), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                          ]),
                          const SizedBox(height: 8),
                          Wrap(spacing: 16, runSpacing: 6, children: [
                            _vitalChip(Icons.science, 'H₂S', '${mData.h2s.toStringAsFixed(1)} ppm',
                                mData.h2s > 10 ? const Color(0xFFF44336) : const Color(0xFF22D3EE)),
                            _vitalChip(Icons.science, 'CH₄', '${mData.ch4.toStringAsFixed(1)} %',
                                mData.ch4 > 1 ? const Color(0xFFF44336) : const Color(0xFFF97316)),
                            _vitalChip(Icons.science, 'CO', '${mData.co.toStringAsFixed(1)} ppm',
                                mData.co > 25 ? const Color(0xFFF44336) : const Color(0xFF94A3B8)),
                            _vitalChip(Icons.science, 'O₂', '${mData.o2.toStringAsFixed(1)} %',
                                mData.o2 < 19.5 ? const Color(0xFFF44336) : const Color(0xFF34D399)),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _vitalChip(IconData icon, String label, String value, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 12),
      const SizedBox(width: 4),
      Text('$label: ', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
      Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    ]);
  }

  // ── Entry Control Actions ───────────────────────────────────────────────────
  Widget _buildControlActions(AppState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('ENTRY CONTROL'),
          if (_selectedWorkerId != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                'Applies to: $_selectedWorkerId',
                style: const TextStyle(color: Color(0xFF3B82F6), fontSize: 11),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 8),
              child: Text('⚠ Select a worker above first', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11)),
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _actionBtn('APPROVE ENTRY', const Color(0xFF4CAF50), Icons.check_circle_outline, () => _approveEntry(state)),
              _actionBtn('BLOCK ENTRY', const Color(0xFFF59E0B), Icons.block, () => _blockEntry(state)),
              _actionBtn('EMERGENCY EVACUATE', const Color(0xFFF44336), Icons.warning_amber_rounded, () {
                state.socketService.emitEvent('manual_evacuate', {
                  'workerId': _selectedWorkerId ?? 'ALL',
                  'reason': 'CRITICAL SUPERVISOR EVACUATION',
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                });
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF1A0000),
                    title: const Text('⚠ EVACUATION ORDER SENT', style: TextStyle(color: Color(0xFFF44336), fontWeight: FontWeight.w800)),
                    content: const Text('Emergency evacuation broadcast sent to all field operatives.', style: TextStyle(color: Colors.white70)),
                    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ACKNOWLEDGE', style: TextStyle(color: Color(0xFFF44336))))],
                  ),
                );
              }, danger: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlActionsLive(AppState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('LIVE COMMANDS'),
          if (_selectedWorkerId != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                'Applies to: $_selectedWorkerId',
                style: const TextStyle(color: Color(0xFF3B82F6), fontSize: 11),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 8),
              child: Text('⚠ Select a worker above first', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11)),
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _actionBtn('BLOCK ENTRY', const Color(0xFFF59E0B), Icons.block, () => _blockEntry(state)),
              _actionBtn('EMERGENCY EVACUATE', const Color(0xFFF44336), Icons.warning_amber_rounded, () {
                state.socketService.emitEvent('manual_evacuate', {
                  'workerId': _selectedWorkerId ?? 'ALL',
                  'reason': 'CRITICAL SUPERVISOR EVACUATION',
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                });
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF1A0000),
                    title: const Text('⚠ EVACUATION ORDER SENT', style: TextStyle(color: Color(0xFFF44336), fontWeight: FontWeight.w800)),
                    content: const Text('Emergency evacuation broadcast sent to all field operatives.', style: TextStyle(color: Colors.white70)),
                    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ACKNOWLEDGE', style: TextStyle(color: Color(0xFFF44336))))],
                  ),
                );
              }, danger: true),
              _actionBtn('RETURN TO PRE-ENTRY', const Color(0xFF3B82F6), Icons.arrow_back, () {
                setState(() => isPreEntryMode = true);
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, Color color, IconData icon, VoidCallback onPressed, {bool danger = false}) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.08),
        side: BorderSide(color: color.withOpacity(0.6)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onPressed,
    );
  }

  // ── Simulation Control Panel (Overflow Safe) ──────────────────────────────
  Widget _buildSimulationControlPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _currentMode == "MANUAL" ? const Color(0xFFF59E0B).withOpacity(0.6) : const Color(0xFF1F2937),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "SIMULATION CONTROL",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.4),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("AUTO", style: TextStyle(color: _currentMode == "MANUAL" ? const Color(0xFF3B82F6) : const Color(0xFF4B5563), fontWeight: FontWeight.bold, fontSize: 11)),
                  Switch(
                    value: _currentMode == "MANUAL",
                    activeColor: const Color(0xFFF59E0B),
                    activeTrackColor: const Color(0xFFF59E0B).withOpacity(0.3),
                    inactiveThumbColor: const Color(0xFF3B82F6),
                    inactiveTrackColor: const Color(0xFF3B82F6).withOpacity(0.3),
                    onChanged: (val) {
                      _setMode(val);
                    },
                  ),
                  Text("MANUAL", style: TextStyle(color: _currentMode == "MANUAL" ? const Color(0xFFF59E0B) : const Color(0xFF4B5563), fontWeight: FontWeight.bold, fontSize: 11)),
                ],
              )
            ],
          ),

          if (_currentMode == "MANUAL") ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.tune, color: Color(0xFFF59E0B), size: 14),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text('MANUAL MODE ACTIVE — Auto simulation paused', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // ✅ LIVE EMIT: each slider change immediately broadcasts to all clients
            _buildGasSlider('H₂S', _manualH2S, 0, 100, 'ppm', const Color(0xFF22D3EE), (v) { setState(() => _manualH2S = v); _emitLiveManualUpdate(); }),
            _buildGasSlider('CH₄', _manualCH4, 0, 10, '%', const Color(0xFFF97316), (v) { setState(() => _manualCH4 = v); _emitLiveManualUpdate(); }),
            _buildGasSlider('CO',  _manualCO,  0, 50, 'ppm', const Color(0xFF94A3B8), (v) { setState(() => _manualCO  = v); _emitLiveManualUpdate(); }),
            _buildGasSlider('O₂',  _manualO2,  18, 21, '%', const Color(0xFF34D399), (v) { setState(() => _manualO2  = v); _emitLiveManualUpdate(); }),
            const SizedBox(height: 14),
            // Preset + Apply + Reset row
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _presetChip('SAFE',    const Color(0xFF4CAF50), 2.0,  0.1, 1.0,  20.9),
                _presetChip('CAUTION', const Color(0xFFFFC107), 8.0,  0.5, 5.0,  20.5),
                _presetChip('DANGER',  const Color(0xFFF44336), 20.0, 2.0, 15.0, 19.0),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6).withOpacity(0.15),
                      side: const BorderSide(color: Color(0xFF3B82F6), width: 1),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _applyManualValues,
                    child: const Text('✓  APPLY TO WORKERS', style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.04),
                      side: BorderSide(color: Colors.white.withOpacity(0.1)),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      setState(() {
                        _manualH2S = 2.0; _manualCH4 = 0.1; _manualCO = 1.0; _manualO2 = 20.9;
                      });
                      _emitLiveManualUpdate();
                    },
                    child: const Text('↺  RESET', style: TextStyle(color: Color(0xFF9CA3AF), fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _modeTab(String label, bool selected, VoidCallback onTap, {bool active = false}) {
    final color = active ? const Color(0xFFF59E0B) : const Color(0xFF4B5563);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? color : const Color(0xFF1F2937)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : const Color(0xFF4B5563),
            fontWeight: FontWeight.w700,
            fontSize: 11,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildGasSlider(String gas, double value, double min, double max, String unit, Color color, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Text(gas, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: color,
                inactiveTrackColor: color.withOpacity(0.15),
                thumbColor: color,
                overlayColor: color.withOpacity(0.15),
              ),
              child: Slider(value: value, min: min, max: max, onChanged: onChanged),
            ),
          ),
          SizedBox(
            width: 62,
            child: Text(
              '${value.toStringAsFixed(1)} $unit',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetChip(String label, Color color, double h2s, double ch4, double co, double o2) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _manualH2S = h2s; _manualCH4 = ch4; _manualCO = co; _manualO2 = o2;
        });
        _applyManualValues();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    );
  }

  // ── Real-Time Gas Trends Graph ──────────────────────────────────────────────
  Widget _buildRealTimeGraph() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle('REAL-TIME GAS TRENDS')),
              _legendDot('H₂S', const Color(0xFF22D3EE)),
              const SizedBox(width: 12),
              _legendDot('CH₄', const Color(0xFFF97316)),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Last 25 readings · auto-updates on every sensor event',
            style: TextStyle(color: Color(0xFF4B5563), fontSize: 10),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: _chartData.length < 2
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.show_chart, color: Color(0xFF1F2937), size: 36),
                        SizedBox(height: 8),
                        Text('Waiting for sensor data…', style: TextStyle(color: Color(0xFF4B5563), fontSize: 12)),
                      ],
                    ),
                  )
                : CustomPaint(
                    size: const Size(double.infinity, 160),
                    painter: _GasTrendPainter(
                      points: _chartData,
                      h2sMax: 20.0,
                      ch4Max: 5.0,
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          // X-axis label
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Older', style: TextStyle(color: Color(0xFF374151), fontSize: 10)),
              const Text('Time →', style: TextStyle(color: Color(0xFF4B5563), fontSize: 10)),
              const Text('Live', style: TextStyle(color: Color(0xFF374151), fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11)),
      ],
    );
  }

  // ── ML Insights ─────────────────────────────────────────────────────────────
  Widget _buildMLInsightsPanel(SensorData d) {
    final ins = d.mlInsights!;
    final spikeRisk = ins['spike_risk'] == true;
    final prob = (ins['spike_probability'] ?? 0.0).toDouble();
    final anomaly = ins['anomaly'] == true;
    final score = (ins['anomaly_score'] ?? 0.0).toDouble();
    final flood = ins['flood_risk'] ?? 'LOW';
    final exp = ins['exposure_level'] ?? 'LOW';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.psychology_outlined, color: Color(0xFF7C3AED), size: 16),
            SizedBox(width: 6),
            Text('AI PREDICTIVE INSIGHTS', style: TextStyle(color: Color(0xFF7C3AED), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          ]),
          const SizedBox(height: 10),
          _insightRow('Gas Spike Risk', spikeRisk ? 'HIGH (${(prob * 100).toStringAsFixed(0)}%)' : 'Low', spikeRisk ? const Color(0xFFF44336) : const Color(0xFF4CAF50)),
          _insightRow('Anomaly', anomaly ? 'Detected (${score.toStringAsFixed(2)})' : 'Normal', anomaly ? const Color(0xFFF97316) : const Color(0xFF4CAF50)),
          _insightRow('Flood Risk', flood, flood == 'HIGH' ? const Color(0xFFF44336) : flood == 'MEDIUM' ? const Color(0xFFF97316) : const Color(0xFF4CAF50)),
          _insightRow('Exposure', exp, exp == 'HIGH' ? const Color(0xFFF44336) : exp == 'MEDIUM' ? const Color(0xFFF97316) : const Color(0xFF4CAF50)),
        ],
      ),
    );
  }

  Widget _insightRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12))),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }

  // ── Alert Feed ──────────────────────────────────────────────────────────────
  Widget _buildAlertFeed(AppState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF44336).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('ALERT PANEL', color: const Color(0xFFF44336)),
          const SizedBox(height: 10),
          if (state.activeAlerts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No active alerts', style: TextStyle(color: Color(0xFF4B5563), fontSize: 13))),
            )
          else
            ...state.activeAlerts.take(10).map((alert) {
              final isCrit = alert.severity == AlertSeverity.critical;
              final c = isCrit ? const Color(0xFFF44336) : const Color(0xFFFFC107);
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(6),
                  border: Border(left: BorderSide(color: c, width: 3)),
                ),
                child: Row(
                  children: [
                    Icon(isCrit ? Icons.warning_amber_rounded : Icons.info_outline, color: c, size: 14),
                    const SizedBox(width: 8),
                    Expanded(child: Text(alert.message, style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 11), maxLines: 3, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  Widget _sectionTitle(String label, {Color color = const Color(0xFF6B7280)}) {
    return Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.6),
    );
  }

  BoxDecoration _card() {
    return BoxDecoration(
      color: const Color(0xFF111827),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFF1F2937)),
    );
  }
}

// ─── Custom Chart Painter ────────────────────────────────────────────────────
class _GasTrendPainter extends CustomPainter {
  final List<_ChartPoint> points;
  final double h2sMax;
  final double ch4Max;

  _GasTrendPainter({required this.points, required this.h2sMax, required this.ch4Max});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final gridPaint = Paint()
      ..color = const Color(0xFF1F2937)
      ..strokeWidth = 1;

    // Draw horizontal grid lines
    for (int i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final h2sPaint = Paint()
      ..color = const Color(0xFF22D3EE)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final ch4Paint = Paint()
      ..color = const Color(0xFFF97316)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final n = points.length;
    final stepX = size.width / (n - 1);

    // H2S line
    final h2sPath = Path();
    for (int i = 0; i < n; i++) {
      final x = i * stepX;
      final y = size.height - ((points[i].h2s / h2sMax).clamp(0.0, 1.0) * size.height);
      if (i == 0) h2sPath.moveTo(x, y); else h2sPath.lineTo(x, y);
    }
    canvas.drawPath(h2sPath, h2sPaint);

    // CH4 line
    final ch4Path = Path();
    for (int i = 0; i < n; i++) {
      final x = i * stepX;
      final y = size.height - ((points[i].ch4 / ch4Max).clamp(0.0, 1.0) * size.height);
      if (i == 0) ch4Path.moveTo(x, y); else ch4Path.lineTo(x, y);
    }
    canvas.drawPath(ch4Path, ch4Paint);

    // Draw latest value dots
    final latestX = (n - 1) * stepX;
    final h2sDotY = size.height - ((points.last.h2s / h2sMax).clamp(0.0, 1.0) * size.height);
    final ch4DotY  = size.height - ((points.last.ch4 / ch4Max).clamp(0.0, 1.0) * size.height);

    canvas.drawCircle(Offset(latestX, h2sDotY), 4, Paint()..color = const Color(0xFF22D3EE));
    canvas.drawCircle(Offset(latestX, ch4DotY),  4, Paint()..color = const Color(0xFFF97316));

    // Y-axis labels
    final tp = TextPainter(textDirection: TextDirection.ltr);
    void drawLabel(String text, double y) {
      tp.text = TextSpan(text: text, style: const TextStyle(color: Color(0xFF4B5563), fontSize: 9));
      tp.layout();
      tp.paint(canvas, Offset(2, y - tp.height / 2));
    }
    drawLabel('${h2sMax.toInt()}', 0);
    drawLabel('${(h2sMax / 2).toInt()}', size.height / 2);
    drawLabel('0', size.height - 10);
  }

  @override
  bool shouldRepaint(covariant _GasTrendPainter old) =>
      old.points != points || old.points.length != points.length;
}
