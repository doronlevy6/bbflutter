// lib/settings_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _selectedSport = 'bb';
  bool _isHebrew = false;
  final TextEditingController _costController = TextEditingController();
  final ApiService apiService = ApiService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadTeamSettings();
  }

  Future<void> _loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedSport = prefs.getString('team_type') ?? 'bb';
      _isHebrew = prefs.getBool('isHebrew') ?? false;
    });
  }

  Future<void> _loadTeamSettings() async {
      // Fetch team settings from server. 
      // Using 'team-financial-summary' or a dedicated endpoint?
      // I made 'team-financial-summary/:team_id' return defaultGameCost.
      // I need team_id.
      // TODO: Get real team_id. Fallback to 1.
      int teamId = 1; 

      try {
          final response = await apiService.get('finance/team-financial-summary/$teamId');
          if (response['success']) {
              setState(() {
                  _costController.text = response['defaultGameCost'].toString();
              });
          }
      } catch (e) {
          print('Error loading team settings: $e');
      }
  }

  Future<void> _saveSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('team_type', _selectedSport);
    await prefs.setBool('isHebrew', _isHebrew);
  }

  Future<void> _saveCost() async {
      int teamId = 1; // Fallback
      int cost = int.tryParse(_costController.text) ?? 0;
      
      setState(() => _isLoading = true);
      try {
          final response = await apiService.put('finance/update-team-settings', {
              'team_id': teamId,
              'default_game_cost': cost
          });
          if (response['success']) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cost updated'), backgroundColor: Colors.green));
          } else {
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message']), backgroundColor: Colors.red));
          }
      } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      } finally {
          setState(() => _isLoading = false);
      }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        backgroundColor: Colors.green[700],
      ),
      body: SingleChildScrollView(
          padding: EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Game Settings',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green[800]),
              ),
              SizedBox(height: 16),
              
              Text('Default Game Cost (Amount per player per game):'),
              SizedBox(height: 8),
              Row(
                  children: [
                      Expanded(
                          child: TextField(
                              controller: _costController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                  prefixIcon: Icon(Icons.attach_money),
                                  border: OutlineInputBorder(),
                                  labelText: 'Cost',
                              ),
                          ),
                      ),
                      SizedBox(width: 12),
                      ElevatedButton(
                          onPressed: _isLoading ? null : _saveCost,
                          child: _isLoading ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text('Save Cost'),
                      ),
                  ],
              ),
              
              Divider(height: 40),
              
              Text(
                'App Settings',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blue[800]),
              ),
              SizedBox(height: 16),
              
              Text(
                'Team Sport Type:',
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
