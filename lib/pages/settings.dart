// lib/settings_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _selectedSport = 'bb';
  bool _isHebrew = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedSport = prefs.getString('team_type') ?? 'bb';
      _isHebrew = prefs.getBool('isHebrew') ?? false;
    });
  }

  Future<void> _saveSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('team_type', _selectedSport);
    await prefs.setBool('isHebrew', _isHebrew);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        backgroundColor: Colors.green[700],
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'team_type:',
              style: TextStyle(fontSize: 18),
            ),
            DropdownButton<String>(
              value: _selectedSport,
              items: [
                DropdownMenuItem(
                  child: Text('Basketball'),
                  value: 'bb',
                ),
                DropdownMenuItem(
                  child: Text('Football'),
                  value: 'fb',
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedSport = value!;
                });
                _saveSettings();
              },
            ),
            SizedBox(height: 24),
            Text(
              'Language:',
              style: TextStyle(fontSize: 18),
            ),
            Row(
              children: [
                Radio<bool>(
                  value: false,
                  groupValue: _isHebrew,
                  onChanged: (value) {
                    setState(() {
                      _isHebrew = value!;
                    });
                    _saveSettings();
                  },
                ),
                Text('English'),
                Radio<bool>(
                  value: true,
                  groupValue: _isHebrew,
                  onChanged: (value) {
                    setState(() {
                      _isHebrew = value!;
                    });
                    _saveSettings();
                  },
                ),
                Text('עברית'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
