

class SensorData {
  // Gas readings
  final double h2s; // ppm
  final double ch4; // %LEL
  final double co; // ppm
  final double o2; // %

  // Worker vitals
  final int heartRate; // bpm
  final int spo2; // %
  final bool fallDetected;
  final bool panicPressed;

  // Environment
  final double waterLevel;
  final double vibration;

  final DateTime timestamp;

  // ML Insights
  final Map<String, dynamic>? mlInsights;
  final String exposureLevel;
  
  final String source;

  SensorData({
    this.h2s = 0.0,
    this.ch4 = 0.0,
    this.co = 0.0,
    this.o2 = 20.9, // Normal atmosphere
    this.heartRate = 0,
    this.spo2 = 98,
    this.fallDetected = false,
    this.panicPressed = false,
    this.waterLevel = 0.0,
    this.vibration = 0.0,
    this.source = 'auto',
    this.mlInsights,
    this.exposureLevel = "LOW",
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  SensorData copyWith({
    double? h2s,
    double? ch4,
    double? co,
    double? o2,
    int? heartRate,
    int? spo2,
    bool? fallDetected,
    bool? panicPressed,
    double? waterLevel,
    double? vibration,
    Map<String, dynamic>? mlInsights,
    String? exposureLevel,
    DateTime? timestamp,
  }) {
    return SensorData(
      h2s: h2s ?? this.h2s,
      ch4: ch4 ?? this.ch4,
      co: co ?? this.co,
      o2: o2 ?? this.o2,
      heartRate: heartRate ?? this.heartRate,
      fallDetected: fallDetected ?? this.fallDetected,
      panicPressed: panicPressed ?? this.panicPressed,
      waterLevel: waterLevel ?? this.waterLevel,
      vibration: vibration ?? this.vibration,
      mlInsights: mlInsights ?? this.mlInsights,
      exposureLevel: exposureLevel ?? this.exposureLevel,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
