import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import '../services/server_config.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.languageCode,
    required this.onLanguageChanged,
  });

  final String languageCode;
  final ValueChanged<String> onLanguageChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _server = TextEditingController();
  String _resolution = '720p';
  bool _cellular = true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((preferences) {
      if (!mounted) return;
      setState(() {
        _server.text =
            preferences.getString('serverUrl') ?? ServerConfig.defaultUrl;
        _resolution = preferences.getString('resolution') ?? '720p';
        _cellular = preferences.getBool('allowCellular') ?? true;
      });
    });
  }

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'serverUrl',
      ServerConfig.normalize(_server.text),
    );
    await preferences.setString('resolution', _resolution);
    await preferences.setBool('allowCellular', _cellular);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.strings.get('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _server,
            decoration: InputDecoration(
              labelText: context.strings.get('serverUrl'),
            ),
          ),
          const SizedBox(height: 20),
          Text(context.strings.get('resolution')),
          RadioGroup<String>(
            groupValue: _resolution,
            onChanged: (value) => setState(() => _resolution = value ?? '720p'),
            child: const Column(
              children: [
                RadioListTile(value: '720p', title: Text('720p (recommended)')),
                RadioListTile(value: '1080p', title: Text('1080p')),
                RadioListTile(
                  value: '4K',
                  title: Text('4K (compatible devices)'),
                ),
              ],
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _cellular,
            onChanged: (value) => setState(() => _cellular = value),
            title: Text(context.strings.get('cellular')),
          ),
          const SizedBox(height: 12),
          Text(context.strings.get('language')),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'en',
                label: Text(context.strings.get('english')),
              ),
              ButtonSegment(
                value: 'zh',
                label: Text(context.strings.get('chinese')),
              ),
            ],
            selected: {widget.languageCode},
            onSelectionChanged: (value) =>
                widget.onLanguageChanged(value.first),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _save,
            child: Text(context.strings.get('saveSettings')),
          ),
        ],
      ),
    );
  }
}
