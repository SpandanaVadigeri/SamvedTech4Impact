import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter/foundation.dart';

/// ─────────────────────────────────────────────────────────────────────────────
///  SocketService – handles WebSocket connection to the Node.js backend.
///
///  ⚠️  REAL DEVICE SETUP:
///    1. Run `ipconfig` (Windows) / `ifconfig` (Mac/Linux)
///    2. Find your IPv4 address (e.g. 192.168.1.10)
///    3. Replace [serverUrl] – keep port 3000
///
///  Examples:
///    Physical Android : 'http://192.168.1.10:3000'
///    Android Emulator : 'http://10.0.2.2:3000'
///    Desktop / Chrome : 'http://127.0.0.1:3000'
/// ─────────────────────────────────────────────────────────────────────────────
class SocketService {
  // 🔧 Change to your PC's local-network IP when testing on a real device
  static const String serverUrl = 'http://10.131.3.221:3000';

  io.Socket? _socket;
  bool isConnected = false;

  // Offline buffer – events sent while disconnected are replayed on reconnect
  final List<Map<String, dynamic>> _offlineQueue = [];

  // ── Callbacks set by AppState ─────────────────────────────────────────────
  Function(dynamic)? _onDataReceived;
  Function(bool)?    _onConnectionChanged;
  Function(dynamic)? _onEntryApproved;
  Function(dynamic)? _onEntryBlocked;
  Function(dynamic)? _onNewEntryRequest;
  Function(dynamic)? _onModeChanged;

  io.Socket get socket {
    assert(_socket != null, 'SocketService.connect() must be called first');
    return _socket!;
  }

  // ── Public setters for callbacks set after construction ───────────────────
  void setEntryApprovedCallback(Function(dynamic) cb)   => _onEntryApproved  = cb;
  void setEntryBlockedCallback(Function(dynamic) cb)    => _onEntryBlocked   = cb;
  void setNewEntryRequestCallback(Function(dynamic) cb) => _onNewEntryRequest = cb;
  void setModeChangedCallback(Function(dynamic) cb)     => _onModeChanged    = cb;

  // ── Connect ───────────────────────────────────────────────────────────────
  void connect(
    Function(dynamic) onDataReceived,
    Function(bool)    onConnectionChanged,
  ) {
    _onDataReceived       = onDataReceived;
    _onConnectionChanged  = onConnectionChanged;

    debugPrint('🔌 [SOCKET] Connecting to $serverUrl ...');

    _socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(9999)
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(10000)
          .setTimeout(10000)
          .build(),
    );

    // ── connect ──────────────────────────────────────────────────────────────
    _socket!.on('connect', (_) {
      debugPrint('✅ [SOCKET] Connected! id=${_socket!.id}');
      isConnected = true;
      _onConnectionChanged?.call(true);
      _flushOfflineQueue();
    });

    // ── reconnect ─────────────────────────────────────────────────────────────
    _socket!.on('reconnect', (_) {
      debugPrint('♻️ [SOCKET] Reconnected!');
      isConnected = true;
      _onConnectionChanged?.call(true);
      _flushOfflineQueue();
    });

    _socket!.on('reconnecting',    (_) => debugPrint('⏳ [SOCKET] Reconnecting…'));
    _socket!.on('reconnect_error', (e) => debugPrint('⚠️ [SOCKET] Reconnect error: $e'));

    // ── PRIMARY sensor data: sensor_update ────────────────────────────────────
    _socket!.on('sensor_update', (data) {
      debugPrint(
        '📡 [SOCKET] sensor_update:'
        ' device=${data is Map ? data["device_id"] : "?"}'
        ' status=${data is Map ? data["status"] : "?"}',
      );
      if (data is Map) _onDataReceived?.call(Map<String, dynamic>.from(data));
    });

    // ── LEGACY sensor data: sensor-data ───────────────────────────────────────
    _socket!.on('sensor-data', (data) {
      if (data is Map) _onDataReceived?.call(Map<String, dynamic>.from(data));
    });

    // ── Evacuation order ──────────────────────────────────────────────────────
    _socket!.on('evacuation_order', (data) {
      debugPrint('🚨 [SOCKET] evacuation_order received!');
      _onDataReceived?.call(<String, dynamic>{
        'status': 'BLOCK',
        'alerts': ['SUPERVISOR DECLARED CRITICAL EMERGENCY EVACUATION'],
        'device_id': 'SYSTEM',
        'worker_id': 'ALL',
      });
    });

    // ── Panic alert ───────────────────────────────────────────────────────────
    _socket!.on('panic-alert', (data) {
      final workerId  = data is Map ? (data['workerId']  ?? 'WORKER')  : 'WORKER';
      final manholeId = data is Map ? (data['manholeId'] ?? 'UNKNOWN') : 'UNKNOWN';
      debugPrint('🚨 [SOCKET] panic-alert worker=$workerId');
      _onDataReceived?.call(<String, dynamic>{
        'status': 'BLOCK',
        'alerts': ['🚨 PANIC: Worker $workerId requests HELP at $manholeId!'],
        'device_id': workerId,
        'worker_id': workerId,
        'panic': true,
      });
    });

    // ── Entry approved (sent to specific worker) ──────────────────────────────
    _socket!.on('entry_approved', (data) {
      debugPrint('✅ [SOCKET] entry_approved received: $data');
      if (_onEntryApproved != null && data is Map) {
        _onEntryApproved!(Map<String, dynamic>.from(data));
      }
    });

    // ── Entry blocked (sent to specific worker) ───────────────────────────────
    _socket!.on('entry_blocked', (data) {
      debugPrint('🚫 [SOCKET] entry_blocked received: $data');
      if (_onEntryBlocked != null && data is Map) {
        _onEntryBlocked!(Map<String, dynamic>.from(data));
      }
    });

    // ── Entry status update (broadcast) ──────────────────────────────────────
    _socket!.on('entry_status_update', (data) {
      debugPrint('📋 [SOCKET] entry_status_update: $data');
      if (data is! Map) return;
      final dataMap = Map<String, dynamic>.from(data);
      final status  = dataMap['status'] as String? ?? '';
      if (status == 'APPROVED' && _onEntryApproved != null) {
        _onEntryApproved!(dataMap);
      } else if (status == 'BLOCKED' && _onEntryBlocked != null) {
        _onEntryBlocked!(dataMap);
      }
    });

    // ── New entry request (supervisor receives) ───────────────────────────────
    _socket!.on('new_entry_request', (data) {
      debugPrint('📥 [SOCKET] new_entry_request: $data');
      if (_onNewEntryRequest != null && data is Map) {
        _onNewEntryRequest!(Map<String, dynamic>.from(data));
      }
    });

    // ── Mode changed ──────────────────────────────────────────────────────────
    _socket!.on('mode_changed', (data) {
      debugPrint('🔄 [SOCKET] mode_changed: $data');
      if (_onModeChanged != null && data is Map) {
        _onModeChanged!(Map<String, dynamic>.from(data));
      }
    });

    // ── Disconnect ────────────────────────────────────────────────────────────
    _socket!.onDisconnect((_) {
      debugPrint('❌ [SOCKET] Disconnected from $serverUrl');
      isConnected = false;
      _onConnectionChanged?.call(false);
    });

    _socket!.onError((err) => debugPrint('❌ [SOCKET] Error: $err'));
    _socket!.on('connect_error', (err) {
      debugPrint('❌ [SOCKET] Connection error: $err');
      isConnected = false;
      _onConnectionChanged?.call(false);
    });
  }

  // ── Emit (buffers if offline) ─────────────────────────────────────────────
  void emitEvent(String eventName, dynamic data) {
    if (isConnected && _socket != null) {
      debugPrint('📤 [SOCKET] Emitting event=$eventName');
      _socket!.emit(eventName, data);
    } else {
      debugPrint('⚠️ [SOCKET] Offline – buffering "$eventName"');
      _offlineQueue.add({
        'event':     eventName,
        'data':      data,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  // ── Flush offline queue ───────────────────────────────────────────────────
  void _flushOfflineQueue() {
    if (_offlineQueue.isNotEmpty && _socket != null) {
      debugPrint('🔄 [SOCKET] Flushing ${_offlineQueue.length} buffered events…');
      for (final item in _offlineQueue) {
        _socket!.emit(item['event'] as String, item['data']);
      }
      _offlineQueue.clear();
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────
  void dispose() {
    if (_socket != null) {
      if (_socket!.connected) _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }
  }

  void onEvent(String event, Function(dynamic) callback) {
    socket.on(event,callback);
  }
}