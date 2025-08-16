import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_notifier.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Consumer<ThemeNotifier>(
        builder: (context, notifier, child) => SwitchListTile(
          title: const Text('Dark Mode'),
          value: notifier.darkTheme,
          onChanged: (val) {
            notifier.toggleTheme();
          },
        ),
      ),
    );
  }
}
