import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Role'),
            subtitle: const Text('Supervisor'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              // Toggle role
            },
          ),
          ListTile(
            title: const Text('Transmission Interval (Seconds)'),
            subtitle: const Text('5'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {},
          ),
          ListTile(
            title: const Text('Gas Threshold Configuration'),
            subtitle: const Text('Default OSHA Limits applied'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {},
          ),
          ListTile(
            title: const Text('Simulate Emergency Panic'),
            leading: const Icon(Icons.warning, color: Colors.orange),
            onTap: () {
                // Test route hook
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Test alarm dispatched locally')));
            },
          )
        ],
      ),
    );
  }
}
