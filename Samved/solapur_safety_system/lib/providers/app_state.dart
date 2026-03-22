import 'package:flutter/foundation.dart';
import '../models/device_state.dart';
import '../models/sensor_data.dart';
import '../services/socket_service.dart';
import '../models/safety_status.dart';

enum AlertSeverity { info, warning, critical }

// ── Entry status for the worker entry-approval flow ────────────────────────
enum EntryStatus { idle, waiting, approved, blocked }

class AlertMessage {
  final String id;
  final String message;
  final AlertSeverity severity;
  final DateTime timestamp;
  bool isAcknowledged;

  AlertMessage({
    required this.id,
    required this.message,
    required this.severity,
    DateTime? timestamp,
    this.isAcknowledged = false,
  }) : timestamp = timestamp ?? DateTime.now();
}

// ─────────────────────────────────────────────────────────────────────────────
//  Worker Model – groups wearable devices into a logical "active worker"
// ─────────────────────────────────────────────────────────────────────────────
class WorkerDeviceGroup {
  final String workerId;
  final String displayName;
  String? helmetDeviceId;
  String? bandDeviceId;
  String? badgeDeviceId;
  DateTime lastSeen;
  SafetyStatus status;

  WorkerDeviceGroup({
    required this.workerId,
    required this.displayName,
    required this.lastSeen,
    this.helmetDeviceId,
    this.bandDeviceId,
    this.badgeDeviceId,
    this.status = SafetyStatus.safe,
  });

  SensorData resolveData(Map<String, SensorData> deviceData) {
    return deviceData[helmetDeviceId] ??
        deviceData[bandDeviceId] ??
        deviceData[badgeDeviceId] ??
        SensorData();
  }

  List<String> get assignedDevices => [
    if (helmetDeviceId != null) helmetDeviceId!,
    if (bandDeviceId   != null) bandDeviceId!,
    if (badgeDeviceId  != null) badgeDeviceId!,
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
//  Pending entry request (for supervisor dashboard)
// ─────────────────────────────────────────────────────────────────────────────
class EntryRequest {
  final String sessionId;
  final String workerId;
  final String manholeId;
  final DateTime requestTime;

  const EntryRequest({
    required this.sessionId,
    required this.workerId,
    required this.manholeId,
    required this.requestTime,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  AppState – central ChangeNotifier for the entire Flutter app
// ─────────────────────────────────────────────────────────────────────────────
class AppState extends ChangeNotifier {
  final SocketService socketService = SocketService();
  final DateTime startTime = DateTime.now();

  // ── Connected Devices ──────────────────────────────────────────────────────
  final List<DeviceState> _devices = [];
  List<DeviceState> get devices => _devices;

  // ── Worker Groups (logical grouping for Live Monitoring) ───────────────────
  final Map<String, WorkerDeviceGroup> _workerGroups = {};
  List<WorkerDeviceGroup> get activeWorkers {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 30));
    return _workerGroups.values
        .where((w) => w.lastSeen.isAfter(cutoff))
        .toList();
  }

  // ── Real-time Sensor Data ──────────────────────────────────────────────────
  SensorData _currentData = SensorData();
  SensorData get currentData => _currentData;

  final Map<String, SensorData> deviceData = {};

  SensorData get topData    => deviceData['SOLAPUR_PROBE_TOP']    ?? SensorData();
  SensorData get midData    => deviceData['SOLAPUR_PROBE_MID']    ?? SensorData();
  SensorData get bottomData => deviceData['SOLAPUR_PROBE_BOTTOM'] ?? SensorData();

  // ── Alerts ─────────────────────────────────────────────────────────────────
  final List<AlertMessage> _activeAlerts = [];
  List<AlertMessage> get activeAlerts => _activeAlerts;

  // ── Overall safety status ──────────────────────────────────────────────────
  SafetyStatus _overallStatus = SafetyStatus.safe;
  SafetyStatus get overallStatus => _overallStatus;

  // ── Connection status ──────────────────────────────────────────────────────
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // ── Pre-entry status ───────────────────────────────────────────────────────
  bool _isPreEntryPassed = false;
  bool get isPreEntryPassed => _isPreEntryPassed;

  // ── Role ───────────────────────────────────────────────────────────────────
  String _currentRole = 'Supervisor';
  String get currentRole => _currentRole;

  // ── Global simulation mode (from server) ───────────────────────────────────
  String _simulationMode = 'AUTO'; // 'AUTO' | 'MANUAL'
  String get simulationMode => _simulationMode;

  // ── Worker entry status (for Worker dashboard) ─────────────────────────────
  EntryStatus _entryStatus = EntryStatus.idle;
  EntryStatus get entryStatus => _entryStatus;

  String? _entrySessionId;
  String? get entrySessionId => _entrySessionId;

  // ── Pending entry requests (for Supervisor dashboard) ─────────────────────
  final List<EntryRequest> _pendingEntryRequests = [];
  List<EntryRequest> get pendingEntryRequests => List.unmodifiable(_pendingEntryRequests);

  // ── Chart history ──────────────────────────────────────────────────────────
  final List<double> h2sHistory = List.filled(60, 0.0);
  final List<double> ch4History = List.filled(60, 0.0);
  final List<double> coHistory  = List.filled(60, 0.0);
  final List<double> o2History  = List.filled(21, 20.9);

  bool _hasBottomProbeData = false;

  // ── Auth token ─────────────────────────────────────────────────────────────
  String? _token;
  String? get token => _token;
  void setToken(String? t) { _token = t; }

  // ── Public methods ─────────────────────────────────────────────────────────

  void updateSensorData(SensorData newData) {
    _currentData = newData;
    notifyListeners();
  }

  void addDevice(DeviceState device) {
    if (!_devices.any((d) => d.id == device.id)) {
      _devices.add(device);
      notifyListeners();
    }
  }

  void updateDeviceConnection(String deviceId, bool connected) {
    final index = _devices.indexWhere((d) => d.id == deviceId);
    if (index >= 0) {
      _devices[index] = _devices[index].copyWith(isConnected: connected);
      notifyListeners();
    }
  }

  void setPreEntryStatus(bool passed) {
    _isPreEntryPassed = passed;
    notifyListeners();
  }

  void setOverallStatus(SafetyStatus status) {
    if (_overallStatus != status) {
      _overallStatus = status;
      notifyListeners();
    }
  }

  void addAlert(AlertMessage alert) {
    _activeAlerts.insert(0, alert);
    if (_activeAlerts.length > 50) _activeAlerts.removeLast();
    notifyListeners();
  }

  void acknowledgeAlert(String alertId) {
    final index = _activeAlerts.indexWhere((a) => a.id == alertId);
    if (index >= 0) {
      _activeAlerts[index].isAcknowledged = true;
      notifyListeners();
    }
  }

  void setRole(String role) {
    _currentRole = role;
    notifyListeners();
  }

  void clearDevices() {
    _devices.clear();
    notifyListeners();
  }

  void emitControlEvent(String eventName, String reason) {
    socketService.emitEvent(eventName, {
      'worker_id': 'ALL',
      'reason':    reason,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ── Entry flow – Worker side ───────────────────────────────────────────────
  void setEntryStatus(EntryStatus status, {String? sessionId}) {
    _entryStatus    = status;
    if (sessionId != null) _entrySessionId = sessionId;
    notifyListeners();
  }

  void sendEntryRequest({required String workerId, required String manholeId, String? sessionId}) {
    final sid = sessionId ?? 'SESSION_${DateTime.now().millisecondsSinceEpoch}';
    _entrySessionId = sid;
    _entryStatus    = EntryStatus.waiting;
    socketService.emitEvent('entry_request', {
      'sessionId': sid,
      'workerId':  workerId,
      'manholeId': manholeId,
    });
    notifyListeners();
  }

  // ── Entry flow – Supervisor side ──────────────────────────────────────────
  void addEntryRequest(EntryRequest request) {
    // Remove duplicate session
    _pendingEntryRequests.removeWhere((r) => r.sessionId == request.sessionId);
    _pendingEntryRequests.insert(0, request);
    notifyListeners();
  }

  void removeEntryRequest(String sessionId) {
    _pendingEntryRequests.removeWhere((r) => r.sessionId == sessionId);
    notifyListeners();
  }

  void approveWorkerEntry({required String sessionId, required String workerId}) {
    socketService.emitEvent('approve_entry', {
      'sessionId': sessionId,
      'workerId':  workerId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    removeEntryRequest(sessionId);
  }

  void blockWorkerEntry({required String sessionId, required String workerId}) {
    socketService.emitEvent('block_entry', {
      'sessionId': sessionId,
      'workerId':  workerId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    removeEntryRequest(sessionId);
  }

  // ── Socket Initialization ──────────────────────────────────────────────────
  void startSocket() {
    debugPrint('🚀 [AppState] Starting socket connection…');

    // Register custom event callbacks
    socketService.setEntryApprovedCallback((data) {
      debugPrint('[AppState] entry_approved: $data');
      if (data is Map) {
        final dataMap = Map<String, dynamic>.from(data);
        _entryStatus    = EntryStatus.approved;
        _entrySessionId = dataMap['sessionId']?.toString() ?? _entrySessionId;

        _overallStatus = SafetyStatus.safe;
        notifyListeners();
      }
    });

    socketService.setEntryBlockedCallback((data) {
      debugPrint('[AppState] entry_blocked: $data');
      if (data is Map) {
        _entryStatus = EntryStatus.blocked;
        _overallStatus = SafetyStatus.block;
        notifyListeners();
      }
    });

    socketService.setNewEntryRequestCallback((data) {
      debugPrint('[AppState] new_entry_request: $data');
      if (data is Map) {
        final dataMap = Map<String, dynamic>.from(data);
        addEntryRequest(EntryRequest(
          sessionId:   dataMap['sessionId']?.toString()  ?? '',
          workerId:    dataMap['workerId']?.toString()   ?? '',
          manholeId:   dataMap['manholeId']?.toString()  ?? '',
          requestTime: DateTime.fromMillisecondsSinceEpoch(
            dataMap['requestTime'] as int? ?? DateTime.now().millisecondsSinceEpoch,
          ),
        ));
      }
    });

    socketService.setModeChangedCallback((data) {
      debugPrint('[AppState] mode_changed: $data');
      if (data is Map) {
        final dataMap = Map<String, dynamic>.from(data);
        _simulationMode = dataMap['mode']?.toString() ?? 'AUTO';
        notifyListeners();
      }
    });

    socketService.connect(
      // ── DATA CALLBACK ──────────────────────────────────────────────────────
      (data) {
        if (data == null || data is! Map) return;

        final Map<String, dynamic> payload = Map<String, dynamic>.from(data);
        final String deviceId = payload['device_id'] ?? payload['worker_id'] ?? 'UNKNOWN';

        debugPrint('📥 [AppState] device=$deviceId status=${payload["status"]}');

        // 1. Track device
        if (!_devices.any((d) => d.id == deviceId)) {
          _devices.add(DeviceState(
            id:          deviceId,
            name:        _friendlyName(deviceId),
            type:        _inferDeviceType(deviceId),
            isConnected: true,
          ));
        }

        // 2. Parse sensor data
        final parsedData = SensorData(
          h2s:          _toDouble(payload['h2s'],   0.0),
          ch4:          _toDouble(payload['ch4'],   0.0),
          co:           _toDouble(payload['co'],    0.0),
          o2:           _toDouble(payload['o2'],   20.9),
          heartRate:    _toInt(payload['hr'],        0),
          spo2:         _toInt(payload['spo2'],     98),
          fallDetected: payload['fall']  == true,
          panicPressed: payload['panic'] == true,
          waterLevel:   _toDouble(payload['water_level'], 0.0),
          vibration:    _toDouble(payload['vibration'],   0.0),
          mlInsights:   payload['ml_insights'] is Map
              ? Map<String, dynamic>.from(payload['ml_insights'] as Map)
              : null,
          exposureLevel: payload['ml_insights'] is Map
              ? ((payload['ml_insights'] as Map)['exposure_level'] ?? 'LOW')
              : 'LOW',
        );

        // 3. Store per-device
        deviceData[deviceId] = parsedData;

        // 4. Update worker group mapping
        _updateWorkerGroup(deviceId, parsedData);

        // 5. Update currentData & chart history (priority: BOTTOM > any probe > wearable)
        final isBottomProbe = deviceId.contains('BOTTOM');
        final isAnyProbe    = deviceId.contains('PROBE');
        final isWearable    = !isAnyProbe;

        if (isBottomProbe) {
          _hasBottomProbeData = true;
          _currentData = parsedData;
          _appendChartHistory(parsedData);
        } else if (isAnyProbe && !_hasBottomProbeData) {
          _currentData = parsedData;
          _appendChartHistory(parsedData);
        } else if (isWearable && !_hasBottomProbeData) {
          _currentData = parsedData;
          _appendChartHistory(parsedData);
        }

        // 6. Overall safety status
        final backendStatus = payload['status'] as String? ?? 'SAFE';
        _updateOverallStatus(backendStatus);

        // 7. Process alerts
        if (payload['alerts'] != null && payload['alerts'] is List) {
          for (final alertMsg in (payload['alerts'] as List)) {
            final msg    = alertMsg.toString();
            final exists = _activeAlerts.any((a) =>
              a.message.contains(msg) &&
              DateTime.now().difference(a.timestamp).inSeconds < 5);
            if (!exists) {
              _activeAlerts.insert(0, AlertMessage(
                id:       DateTime.now().millisecondsSinceEpoch.toString(),
                message:  '[$deviceId] $msg',
                severity: backendStatus == 'BLOCK' ? AlertSeverity.critical : AlertSeverity.warning,
              ));
              if (_activeAlerts.length > 50) _activeAlerts.removeLast();
            }
          }
        }

        // 8. Notify
        notifyListeners();
      },

      // ── CONNECTION STATUS CALLBACK ─────────────────────────────────────────
      (bool connectionStatus) {
        debugPrint('🔌 [AppState] Connection: $connectionStatus');
        _isConnected = connectionStatus;
        notifyListeners();
      },
    );
  }

  // ── Private Helpers ────────────────────────────────────────────────────────

  void _appendChartHistory(SensorData d) {
    h2sHistory.add(d.h2s); if (h2sHistory.length > 60) h2sHistory.removeAt(0);
    ch4History.add(d.ch4); if (ch4History.length > 60) ch4History.removeAt(0);
    coHistory.add(d.co);   if (coHistory.length  > 60) coHistory.removeAt(0);
    o2History.add(d.o2);   if (o2History.length  > 60) o2History.removeAt(0);
  }

  // void _updateOverallStatus(String backendStatus) {
  //   if (backendStatus == 'BLOCK') {
  //     _overallStatus = SafetyStatus.block;
  //   } else if (backendStatus == 'CAUTION' && _overallStatus != SafetyStatus.block) {
  //     _overallStatus = SafetyStatus.caution;
  //   } else if (backendStatus == 'SAFE' && _overallStatus == SafetyStatus.safe) {
  //     _overallStatus = SafetyStatus.safe;
  //   }
  // }

  void _updateOverallStatus(String backendStatus) {
  switch (backendStatus) {
    case 'BLOCK':
      _overallStatus = SafetyStatus.block;
      break;
    case 'CAUTION':
      _overallStatus = SafetyStatus.caution;
      break;
    case 'SAFE':
    default:
      _overallStatus = SafetyStatus.safe;
  }
}

  void _updateWorkerGroup(String deviceId, SensorData data) {
    final isHelmet = deviceId.contains('HELMET');
    final isBand   = deviceId.contains('BAND');
    final isBadge  = deviceId.contains('BADGE') || deviceId.contains('PANIC');
    if (!isHelmet && !isBand && !isBadge) return;

    final parts     = deviceId.split('_');
    final num_      = parts.length >= 3 ? parts.last : '001';
    final workerKey = 'WORKER_$num_';

    final existing = _workerGroups[workerKey] ??
        WorkerDeviceGroup(workerId: workerKey, displayName: 'Worker #$num_', lastSeen: DateTime.now());

    if (isHelmet) existing.helmetDeviceId = deviceId;
    if (isBand)   existing.bandDeviceId   = deviceId;
    if (isBadge)  existing.badgeDeviceId  = deviceId;
    existing.lastSeen = DateTime.now();

    if (data.panicPressed || data.fallDetected || (data.spo2 > 0 && data.spo2 < 92)) {
      existing.status = SafetyStatus.block;
    } else if (data.vibration > 10) {
      existing.status = SafetyStatus.caution;
    } else {
      existing.status = SafetyStatus.safe;
    }

    _workerGroups[workerKey] = existing;
  }

  double _toDouble(dynamic val, double fallback) {
    if (val == null)     return fallback;
    if (val is double)   return val;
    if (val is int)      return val.toDouble();
    if (val is String)   return double.tryParse(val) ?? fallback;
    return fallback;
  }

  int _toInt(dynamic val, int fallback) {
    if (val == null)   return fallback;
    if (val is int)    return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? fallback;
    return fallback;
  }

  DeviceType _inferDeviceType(String deviceId) {
    if (deviceId.contains('HELMET'))                                return DeviceType.helmet;
    if (deviceId.contains('BAND'))                                  return DeviceType.vitalBand;
    if (deviceId.contains('BADGE') || deviceId.contains('PROBE'))  return DeviceType.gasBadge;
    return DeviceType.unknown;
  }

  String _friendlyName(String deviceId) {
    final parts = deviceId.split('_');
    if (parts.length >= 3) {
      final type = parts[1][0] + parts[1].substring(1).toLowerCase();
      return '$type #${parts[2]}';
    }
    return deviceId;
  }

  @override
  void dispose() {
    socketService.dispose();
    super.dispose();
  }
}
