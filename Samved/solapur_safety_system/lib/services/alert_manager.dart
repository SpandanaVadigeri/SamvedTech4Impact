import 'package:uuid/uuid.dart';
import '../models/sensor_data.dart';
import '../providers/app_state.dart';
import 'safety_engine_service.dart';
import '../models/safety_status.dart';

class AlertManager {
  final AppState appState;
  final Uuid uuid = const Uuid();

  AlertManager(this.appState);

  void evaluateData(SensorData data, String deviceId) {
    final status = SafetyEngineService.evaluateOverallGasSafety(data);
    
    // Evaluate Gas Anomaly
    if (status == SafetyStatus.block) {
       _triggerAlert("CRITICAL: Gas limit exceeded on device $deviceId", AlertSeverity.critical);
    } else if (status == SafetyStatus.caution) {
       _triggerAlert("WARNING: Gas level cautious on device $deviceId", AlertSeverity.warning);
    }

    // Evaluate Wearable Anomaly
    if (data.fallDetected) {
       _triggerAlert("EMERGENCY: Fall detected for worker with device $deviceId", AlertSeverity.critical);
    }

    if (data.panicPressed) {
       _triggerAlert("EMERGENCY: Panic button pressed on device $deviceId", AlertSeverity.critical);
    }

    // Evaluate vitals
    if (data.heartRate > 120 || (data.heartRate > 0 && data.heartRate < 50)) {
       _triggerAlert("WARNING: Abnormal heart rate (${data.heartRate} bpm) on device $deviceId", AlertSeverity.warning);
    }

    // Evaluate Environment
    if (data.waterLevel > 0.8) {
       _triggerAlert("WARNING: High water level near $deviceId", AlertSeverity.critical);
    }
    if (data.vibration > 0.5) {
       _triggerAlert("WARNING: Structural vibration detected near $deviceId", AlertSeverity.warning);
    }
  }

  void _triggerAlert(String message, AlertSeverity severity) {
     appState.addAlert(AlertMessage(
       id: uuid.v4(),
       message: message,
       severity: severity,
       timestamp: DateTime.now()
     ));
     
     if (severity == AlertSeverity.critical) {
         appState.setOverallStatus(SafetyStatus.block);
     } else if (severity == AlertSeverity.warning && appState.overallStatus == SafetyStatus.safe) {
         appState.setOverallStatus(SafetyStatus.caution);
     }
  }
}
