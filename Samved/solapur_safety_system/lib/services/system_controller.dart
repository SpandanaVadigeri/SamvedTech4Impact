import 'dart:async';
import '../models/sensor_data.dart';
import '../models/device_state.dart';
import '../providers/app_state.dart';
import 'database_service.dart';
import 'exposure_tracker.dart';
import 'alert_manager.dart';

class SystemController {
  final AppState appState;
  final AlertManager alertManager;
  final ExposureTracker exposureTracker = ExposureTracker();
  Timer? _processingTimer;

  SystemController(this.appState) : alertManager = AlertManager(appState);

  void startSystem() {
    _processingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _processTick();
    });
  }

  void stopSystem() {
    _processingTimer?.cancel();
  }

  Future<void> _processTick() async {
    SensorData current = appState.currentData;
    String primaryDeviceId = "DASH_01"; // Mock ID for gateway overall status

    // 1. Evaluate real-time data for alerts
    alertManager.evaluateData(current, primaryDeviceId);

    // 2. Track Exposure for connected workers
    // In a real scenario, we calculate per-worker based on their badges. 
    // Here we use the global current data applied to all connected workers for demo purposes.
    for (DeviceState worker in appState.devices.where((d) => d.type == DeviceType.vitalBand)) {
        exposureTracker.addReading(worker.id, current.h2s, current.co, 5 / 60);

        if (exposureTracker.isApproachingH2SLimit(worker.id)) {
            appState.addAlert(AlertMessage(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              message: "EXPOSURE WARNING: Worker ${worker.name} approaching H2S STEL limit",
              severity: AlertSeverity.warning
            ));
        }
        if (exposureTracker.isApproachingCOLimit(worker.id)) {
            appState.addAlert(AlertMessage(
              id: "${DateTime.now().millisecondsSinceEpoch}_co",
              message: "EXPOSURE WARNING: Worker ${worker.name} approaching CO STEL limit",
              severity: AlertSeverity.warning
            ));
        }

        // Store worker vitals to DB
        await DatabaseService.instance.insertWorkerVitals(current, worker.id, worker.batteryLevel);
    }

    // 3. Store gas reading to DB
    await DatabaseService.instance.insertGasReading(current, primaryDeviceId, "Sector 4", "Mid");
  }

  // Simulated Mock data injection for testing
  void injectMockData(SensorData mockData) {
    appState.updateSensorData(mockData);
  }
}
