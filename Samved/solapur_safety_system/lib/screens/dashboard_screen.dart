import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/sensor_data.dart';

import '../widgets/gas_gauge.dart';
import '../widgets/worker_status_card.dart';
import 'logs_screen.dart';
import 'settings_screen.dart';
import '../models/safety_status.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    var state = context.watch<AppState>();
    SensorData current = state.currentData;

    Color bannerColor = Colors.green;
    String bannerText = "SYSTEM SAFE";
    if (state.overallStatus == SafetyStatus.caution) {
       bannerColor = Colors.orange;
       bannerText = "CAUTION: Thresholds Approaching";
    } else if (state.overallStatus == SafetyStatus.block) {
       bannerColor = Colors.red;
       bannerText = "EMERGENCY: SITE BLOCKED";
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Supervisor Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LogsScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
             // Status Banner
             Container(
               width: double.infinity,
               padding: const EdgeInsets.all(12),
               color: bannerColor,
               child: Text(bannerText, textAlign: TextAlign.center, 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
             ),
             const SizedBox(height: 10),

             // Gas Gauges Grid
             GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 1,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                   GasGaugeWidget(
                     label: 'H2S', value: current.h2s, unit: 'ppm',
                     max: 20.0, cautionThreshold: 5.0, blockThreshold: 10.0,
                   ),
                   GasGaugeWidget(
                     label: 'CH4', value: current.ch4, unit: '%LEL',
                     max: 5.0, cautionThreshold: 0.5, blockThreshold: 2.0,
                   ),
                   GasGaugeWidget(
                     label: 'CO', value: current.co, unit: 'ppm',
                     max: 50.0, cautionThreshold: 25.0, blockThreshold: 35.0,
                   ),
                   GasGaugeWidget(
                     label: 'O2', value: current.o2, unit: '%',
                     max: 25.0, cautionThreshold: 20.8, blockThreshold: 19.5,
                     invertedSafe: true, // Lower is danger
                   ),
                ],
             ),
             const SizedBox(height: 10),

             // Worker Status Cards
             Align(
               alignment: Alignment.centerLeft,
               child: const Text('Connected Workers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
             ),
             const SizedBox(height: 5),
             if (state.devices.isEmpty)
               const Text("No wearables connected. Pull down or go to config to scan.", 
                  style: TextStyle(color: Colors.grey)),
             ListView.builder(
               shrinkWrap: true,
               physics: const NeverScrollableScrollPhysics(),
               itemCount: state.devices.length,
               itemBuilder: (context, index) {
                 return WorkerStatusCard(device: state.devices[index], data: current);
               },
             ),

             const SizedBox(height: 10),

             // Alerts Feed
             Align(
               alignment: Alignment.centerLeft,
               child: const Text('Recent Alerts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
             ),
             const SizedBox(height: 5),
             if (state.activeAlerts.isEmpty)
               const Text("No active alerts.", style: TextStyle(color: Colors.grey)),
             ListView.builder(
               shrinkWrap: true,
               physics: const NeverScrollableScrollPhysics(),
               itemCount: state.activeAlerts.length < 5 ? state.activeAlerts.length : 5,
               itemBuilder: (context, index) {
                 final alert = state.activeAlerts[index];
                 return ListTile(
                   leading: Icon(
                     alert.severity == AlertSeverity.critical ? Icons.warning : Icons.info,
                     color: alert.severity == AlertSeverity.critical ? Colors.red : Colors.orange,
                   ),
                   title: Text(alert.message),
                   subtitle: Text(alert.timestamp.toString().substring(11, 19)), // Show time HH:mm:ss
                   trailing: alert.isAcknowledged 
                     ? const Icon(Icons.check, color: Colors.green)
                     : IconButton(
                         icon: const Icon(Icons.check_box_outline_blank),
                         onPressed: () => state.acknowledgeAlert(alert.id),
                       ),
                 );
               },
             ),
          ],
        ),
      ),
    );
  }
}
