import 'package:flutter/material.dart';
import '../models/device_state.dart';
import '../models/sensor_data.dart';

class WorkerStatusCard extends StatelessWidget {
  final DeviceState device;
  final SensorData data;

  const WorkerStatusCard({super.key, required this.device, required this.data});

  @override
  Widget build(BuildContext context) {
    bool hasEmergency = data.fallDetected || data.panicPressed;
    Color statusColor = hasEmergency ? Colors.red.shade900 : Colors.teal.shade900;
    
    return Card(
      color: statusColor,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Row(
               mainAxisAlignment: MainAxisAlignment.spaceBetween,
               children: [
                 Text(device.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                 Icon(device.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                     color: device.isConnected ? Colors.blue : Colors.grey, size: 20),
               ],
             ),
             const SizedBox(height: 8),
             Row(
               children: [
                 const Icon(Icons.favorite, color: Colors.pinkAccent, size: 20),
                 const SizedBox(width: 4),
                 Text('${data.heartRate} bpm'),
                 const Spacer(),
                 const Icon(Icons.battery_full, color: Colors.greenAccent, size: 20),
                 const SizedBox(width: 4),
                 Text('${device.batteryLevel}%'),
               ],
             ),
             const SizedBox(height: 8),
             if (hasEmergency)
               Container(
                 padding: const EdgeInsets.all(4),
                 color: Colors.red,
                 child: Text(
                   data.panicPressed ? 'PANIC PRESSED' : 'FALL DETECTED',
                   style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                 ),
               ),
          ],
        ),
      ),
    );
  }
}
