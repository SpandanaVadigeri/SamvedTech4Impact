enum DeviceType { helmet, vitalBand, gasBadge, unknown }

class DeviceState {
  final String id;
  final String name;
  final DeviceType type;
  bool isConnected;
  int batteryLevel;

  DeviceState({
    required this.id,
    required this.name,
    required this.type,
    this.isConnected = false,
    this.batteryLevel = 100,
  });

  DeviceState copyWith({
    String? id,
    String? name,
    DeviceType? type,
    bool? isConnected,
    int? batteryLevel,
  }) {
    return DeviceState(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      isConnected: isConnected ?? this.isConnected,
      batteryLevel: batteryLevel ?? this.batteryLevel,
    );
  }
}
