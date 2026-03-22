import 'package:flutter/material.dart';

import '../services/database_service.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final data = await DatabaseService.instance.getAllGasReadings();
    setState(() {
      _logs = data.take(100).toList(); // Show last 100
      _isLoading = false;
    });
  }

  void _exportLogs() async {
    try {
      String path = await DatabaseService.instance.exportToCSV();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported to: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to export: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensor History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: "Export CSV",
            onPressed: _exportLogs,
          )
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView.separated(
            itemCount: _logs.length,
            separatorBuilder: (c, i) => const Divider(),
            itemBuilder: (context, index) {
              var row = _logs[index];
              return ListTile(
                title: Text("Time: ${row['timestamp'].toString().substring(0, 19)}"),
                subtitle: Text("H2S: ${row['h2s']} | CH4: ${row['ch4']} | CO: ${row['co']} | O2: ${row['o2']}"),
                leading: const Icon(Icons.history),
              );
            },
        ),
    );
  }
}
