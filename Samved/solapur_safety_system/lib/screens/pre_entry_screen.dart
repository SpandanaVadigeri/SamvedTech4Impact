import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sensor_data.dart';
import '../providers/app_state.dart';
import '../services/safety_engine_service.dart';
import '../services/database_service.dart';

class PreEntryScreen extends StatefulWidget {
  const PreEntryScreen({super.key});

  @override
  State<PreEntryScreen> createState() => _PreEntryScreenState();
}

class _PreEntryScreenState extends State<PreEntryScreen> {
  // Test Mock data generator
  SensorData generateMockData(double multiplier) {
    return SensorData(
      h2s: 2.0 * multiplier,
      ch4: 0.2 * multiplier,
      co: 5.0 * multiplier,
      o2: 20.9 - (1.0 * multiplier),
    );
  }

  SensorData? topData;
  SensorData? midData;
  SensorData? bottomData;
  bool isBlocked = false;
  String assessmentResult = "";

  void _runAssessment() async {
    // Mock probes connection by generating data after delay
    setState(() {
      assessmentResult = "Reading Top Depth...";
    });
    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      topData = generateMockData(1.0);
      assessmentResult = "Reading Mid Depth...";
    });
    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      midData = generateMockData(2.5);
      assessmentResult = "Reading Bottom Depth...";
    });
    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      bottomData = generateMockData(5.5); // Might trigger block
    });

    bool safe = SafetyEngineService.calculatePreEntryDecision(topData!, midData!, bottomData!);

    setState(() {
      isBlocked = !safe;
      assessmentResult = safe ? "SAFE TO ENTER" : "ENTRY BLOCKED: High Gas Levels";
    });

    // Log to DB
    await DatabaseService.instance.insertDecision(
      safe ? "SAFE" : "BLOCK",
      "Pre-Entry Assessment completed.",
      "OP_001",
    );

    if (!mounted) return;
    Provider.of<AppState>(context, listen: false).setPreEntryStatus(safe);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pre-Entry Assessment')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.security, size: 80, color: Colors.teal),
            const SizedBox(height: 20),
            const Text(
              'Perform multi-level gas sampling before entry.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 40),
            if (assessmentResult.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                color: assessmentResult.contains("SAFE") 
                  ? Colors.green.shade800 
                  : (assessmentResult.contains("BLOCK") ? Colors.red.shade800 : Colors.blueGrey),
                child: Text(
                  assessmentResult,
                  style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: _runAssessment,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Assessment Scan'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
            const SizedBox(height: 20),
            if (topData != null && midData != null && bottomData != null)
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/dashboard');
                },
                child: const Text('Proceed to Dashboard'),
              )
          ],
        ),
      ),
    );
  }
}
