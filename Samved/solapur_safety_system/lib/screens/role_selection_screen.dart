import 'package:flutter/material.dart';
import 'supervisor_dashboard.dart';
import 'admin_dashboard.dart';
import 'worker_dashboard.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SCSSAS - Role Selection'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.security, size: 80, color: Colors.teal),
            const SizedBox(height: 20),
            const Text(
              'Select Your Role',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            _buildRoleButton(
              context,
              'Supervisor Dashboard',
              Icons.dashboard,
              Colors.blueAccent,
              () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SupervisorDashboard())),
            ),
            const SizedBox(height: 20),
            _buildRoleButton(
              context,
              'Admin Dashboard',
              Icons.analytics,
              Colors.purpleAccent,
              () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminDashboard())),
            ),
            const SizedBox(height: 20),
            _buildRoleButton(
              context,
              'Worker Dashboard',
              Icons.person,
              Colors.orangeAccent,
              () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const WorkerDashboard())),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleButton(BuildContext context, String title, IconData icon, Color color, VoidCallback onTap) {
    return SizedBox(
      width: 250,
      height: 60,
      child: ElevatedButton.icon(
        icon: Icon(icon, size: 28),
        label: Text(title, style: const TextStyle(fontSize: 16)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onTap,
      ),
    );
  }
}
