import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/device_state.dart';
import '../models/sensor_data.dart';
import '../providers/app_state.dart';

class BleService {
  final AppState appState;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final Map<String, StreamSubscription<BluetoothConnectionState>> _connectionSubscriptions = {};

  // UUIDs
  static const String helmetService = "12345678-1234-1234-1234-123456789abc";
  static const String h2sChar = "1111";
  static const String ch4Char = "2222";
  static const String coChar = "3333";
  static const String o2Char = "4444";
  static const String commandChar = "5555";

  static const String vitalService = "180D"; // Standard Heart Rate
  static const String hrMeasurementChar = "2A37";

  BleService(this.appState);

  Future<void> startScan() async {
    // Check if Bluetooth is on
    var adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState == BluetoothAdapterState.off) {
      debugPrint("Bluetooth is off");
      return; // handle error in UI
    }

    // Clear previous devices
    appState.clearDevices();

    _scanSubscription = FlutterBluePlus.onScanResults.listen(
      (results) {
        for (ScanResult r in results) {
          String name = r.device.platformName.isNotEmpty
              ? r.device.platformName
              : "Unknown Device";

          // Add logic to categorize devices
          DeviceType type = DeviceType.unknown;
          if (name.toLowerCase().contains("helmet")) {
            type = DeviceType.helmet;
          } else if (name.toLowerCase().contains("vital") || name.toLowerCase().contains("band")) {
            type = DeviceType.vitalBand;
          } else if (name.toLowerCase().contains("badge")) {
            type = DeviceType.gasBadge;
          }

          if (type != DeviceType.unknown && 
              !appState.devices.any((d) => d.id == r.device.remoteId.str)) {
            appState.addDevice(
              DeviceState(id: r.device.remoteId.str, name: name, type: type),
            );
          }
        }
      },
      onError: (e) => debugPrint("Scan error: $e"),
    );

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  Future<void> connectToDevice(String deviceId) async {
    try {
      final device = BluetoothDevice.fromId(deviceId);
      
      // Cancel any existing subscription
      await _connectionSubscriptions[deviceId]?.cancel();
      
      // Listen to connection state changes
      _connectionSubscriptions[deviceId] = device.connectionState.listen((state) {
        bool isConnected = state == BluetoothConnectionState.connected;
        appState.updateDeviceConnection(deviceId, isConnected);
        
        if (state == BluetoothConnectionState.connected) {
          debugPrint("Device $deviceId connected successfully");
          // Discover services after connection is established
          discoverServices(device);
        } else if (state == BluetoothConnectionState.disconnected) {
          debugPrint("Device $deviceId disconnected");
          _connectionSubscriptions.remove(deviceId);
        }
      });
      
      // Initiate connection (this is not a Future that completes when connected)
      // It returns immediately, connection happens asynchronously
      await device.connect(
        license: License.free, // Handle license if required by platform
        autoConnect: false, // We will manage reconnection manually
      );
      
    } catch (e) {
      debugPrint("Error connecting to device: $e");
      appState.updateDeviceConnection(deviceId, false);
    }
  }

  Future<void> disconnectDevice(String deviceId) async {
    try {
      final device = BluetoothDevice.fromId(deviceId);
      await _connectionSubscriptions[deviceId]?.cancel();
      _connectionSubscriptions.remove(deviceId);
      await device.disconnect();
      appState.updateDeviceConnection(deviceId, false);
    } catch (e) {
      debugPrint("Error disconnecting: $e");
    }
  }

  Future<void> discoverServices(BluetoothDevice device) async {
    try {
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        // Check if it's Helmet Service
        if (service.uuid.toString().toLowerCase() == helmetService.toLowerCase()) {
          for (var char in service.characteristics) {
            await _subscribeToCharacteristic(char, device.remoteId.str, DeviceType.helmet);
          }
        } 
        // Check if it's Vital Band Service
        else if (service.uuid.toString().toLowerCase() == "0000180d-0000-1000-8000-00805f9b34fb") { 
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase() == "00002a37-0000-1000-8000-00805f9b34fb") {
              await _subscribeToCharacteristic(char, device.remoteId.str, DeviceType.vitalBand);
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error discovering services: $e");
    }
  }

  Future<void> _subscribeToCharacteristic(
      BluetoothCharacteristic char, String deviceId, DeviceType deviceType) async {
    try {
      if (char.properties.notify) {
        await char.setNotifyValue(true);
        char.onValueReceived.listen((value) {
          _parseCharacteristicValue(char.uuid.toString(), value, deviceId, deviceType);
        });
      }
    } catch (e) {
      debugPrint("Error subscribing to characteristic: $e");
    }
  }

  void _parseCharacteristicValue(
      String uuid, List<int> value, String deviceId, DeviceType deviceType) {
    SensorData currentData = appState.currentData;

    try {
      if (deviceType == DeviceType.helmet) {
        // Parse based on characteristic UUID
        if (uuid.toLowerCase().contains(h2sChar.toLowerCase())) {
          double h2s = _parseUint16(value) / 100.0;
          appState.updateSensorData(currentData.copyWith(h2s: h2s));
        } else if (uuid.toLowerCase().contains(ch4Char.toLowerCase())) {
          double ch4 = _parseUint16(value) / 100.0;
          appState.updateSensorData(currentData.copyWith(ch4: ch4));
        } else if (uuid.toLowerCase().contains(coChar.toLowerCase())) {
          double co = _parseUint16(value) / 100.0;
          appState.updateSensorData(currentData.copyWith(co: co));
        } else if (uuid.toLowerCase().contains(o2Char.toLowerCase())) {
          double o2 = _parseUint16(value) / 100.0;
          appState.updateSensorData(currentData.copyWith(o2: o2));
        }
      } else if (deviceType == DeviceType.vitalBand) {
        if (uuid.toLowerCase().contains(hrMeasurementChar.toLowerCase())) {
          // Parse standard BLE HR measurement
          // First byte: flags (bit0 = heart rate format: 0 = uint8, 1 = uint16)
          int hr = 0;
          if (value.isNotEmpty) {
            int flags = value[0];
            bool isUint16 = (flags & 0x01) == 0x01;
            if (isUint16 && value.length >= 3) {
              hr = (value[2] << 8) | value[1]; // Uint16 format
            } else if (value.length >= 2) {
              hr = value[1]; // Uint8 format
            }
          }
          appState.updateSensorData(currentData.copyWith(heartRate: hr));
        }
      }
    } catch (e) {
      debugPrint("Error parsing BLE value: $e");
    }
  }

  int _parseUint16(List<int> bytes) {
    if (bytes.length < 2) return 0;
    // Handle both little and big endian
    if (bytes.length >= 2) {
      return (bytes[0] & 0xFF) | ((bytes[1] & 0xFF) << 8); // Little Endian
    }
    return 0;
  }

  // Write command to Helmet e.g., turn on buzzer
  Future<void> sendCommandToHelmet(String deviceId, int command) async {
    try {
      final device = BluetoothDevice.fromId(deviceId);
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == helmetService.toLowerCase()) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase().contains(commandChar.toLowerCase())) {
              await char.write([command]);
              debugPrint("Command $command sent to $deviceId");
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error sending command: $e");
    }
  }

  // Clean up resources
  void dispose() {
    _scanSubscription?.cancel();
    for (var sub in _connectionSubscriptions.values) {
      sub.cancel();
    }
    _connectionSubscriptions.clear();
  }
}