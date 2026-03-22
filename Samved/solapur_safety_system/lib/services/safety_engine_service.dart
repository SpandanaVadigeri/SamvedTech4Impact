import '../models/sensor_data.dart';
import '../models/safety_status.dart';
class SafetyEngineService {
  // Evaluates a single gas reading to return a status color/level
  static SafetyStatus evaluateH2S(double value) {
    if (value < 5.0) return SafetyStatus.safe;
    if (value <= 10.0) return SafetyStatus.caution;
    return SafetyStatus.block;
  }

  static SafetyStatus evaluateCH4(double value) {
    if (value < 0.5) return SafetyStatus.safe;
    if (value <= 2.0) return SafetyStatus.caution;
    return SafetyStatus.block;
  }

  static SafetyStatus evaluateCO(double value) {
    if (value < 25.0) return SafetyStatus.safe;
    if (value <= 35.0) return SafetyStatus.caution;
    return SafetyStatus.block;
  }

  static SafetyStatus evaluateO2(double value) {
    if (value > 20.8) return SafetyStatus.safe;
    if (value >= 19.5) return SafetyStatus.caution;
    return SafetyStatus.block; // Less than 19.5% is danger
  }

  // Evaluates all readings and returns the most severe status
  static SafetyStatus evaluateOverallGasSafety(SensorData data) {
    final h2sStatus = evaluateH2S(data.h2s);
    final ch4Status = evaluateCH4(data.ch4);
    final coStatus = evaluateCO(data.co);
    final o2Status = evaluateO2(data.o2);

    final statuses = [h2sStatus, ch4Status, coStatus, o2Status];

    if (statuses.contains(SafetyStatus.block)) {
      return SafetyStatus.block;
    }
    if (statuses.contains(SafetyStatus.caution)) {
      return SafetyStatus.caution;
    }
    return SafetyStatus.safe;
  }

  // Pre-entry decision logic based on multiple depths
  // Returns true if SAFE to enter, false otherwise
  static bool calculatePreEntryDecision(
      SensorData top, SensorData mid, SensorData bottom) {
    final topStatus = evaluateOverallGasSafety(top);
    final midStatus = evaluateOverallGasSafety(mid);
    final botStatus = evaluateOverallGasSafety(bottom);

    // If any depth is BLOCK, entry is denied
    if (topStatus == SafetyStatus.block ||
        midStatus == SafetyStatus.block ||
        botStatus == SafetyStatus.block) {
      return false;
    }

    return true; // Safe or Caution allows conditional entry depending on policy, we assume true for now
  }
}
