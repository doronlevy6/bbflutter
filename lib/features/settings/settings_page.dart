// lib/settings_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _selectedSport = 'bb';
  bool _isHebrew = false;
  bool accessDenied = false;
  bool _accessChecked = false;
  bool _didLoadPlayersOnce = false;
  final TextEditingController _costController = TextEditingController();
  final ApiService apiService = ApiService();
  bool _isLoading = false;
  bool _teamSettingsCached = false;
  static const String _appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
  static const String _deployedAtRaw =
      String.fromEnvironment('DEPLOYED_AT', defaultValue: '');
  static const String _buildGitSha =
      String.fromEnvironment('BUILD_GIT_SHA', defaultValue: '');

  @override
  void initState() {
    super.initState();
    _initializeAccess();
  }

  Future<void> _initializeAccess() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final isAdmin = prefs.getBool('is_admin') ?? false;

    if (!isAdmin) {
      if (!mounted) return;
      setState(() {
        accessDenied = true;
        _accessChecked = true;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      accessDenied = false;
      _accessChecked = true;
    });
    _loadSettings();
    _loadTeamSettings();
    if (!_didLoadPlayersOnce) {
      _didLoadPlayersOnce = true;
      _loadPlayers();
    }
  }

  Future<void> _loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      String storedSport = prefs.getString('team_type') ?? 'bb';
      if (storedSport != 'bb' && storedSport != 'fb') {
        storedSport = 'bb';
      }
      _selectedSport = storedSport;
      _isHebrew = prefs.getBool('isHebrew') ?? false;
    });
  }

  Future<void> _loadTeamSettings() async {
    try {
      final response = await apiService.getWithCache(
        'finance/team-settings',
        cacheKey: 'cache_team_settings',
      );
      if (response['success'] == true) {
        setState(() {
          _costController.text = response['defaultGameCost'].toString();
          _teamSettingsCached = response['_cached'] == true;
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
    int cost = int.tryParse(_costController.text) ?? 0;

    setState(() => _isLoading = true);
    try {
      final response = await apiService.putQueued(
          'finance/update-team-settings', {'default_game_cost': cost});
      if (response['success']) {
        final queued = response['queued'] == true;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(queued
                ? 'Saved offline. Will sync when online.'
                : 'Cost updated'),
            backgroundColor: queued ? Colors.orange : Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(response['message']), backgroundColor: Colors.red));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _formatDeployedAt() {
    if (_deployedAtRaw.isEmpty) {
      return 'Not available (local/dev build)';
    }
    final parsed = DateTime.tryParse(_deployedAtRaw);
    if (parsed == null) {
      return _deployedAtRaw;
    }
    final local = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_accessChecked) {
      return Center(child: CircularProgressIndicator());
    }

    if (accessDenied) {
      return Center(
        child: Text('Access Denied',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Default Game Cost (Amount per player per game):'),
          SizedBox(height: 8),
          if (_teamSettingsCached)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('Showing cached data (offline)',
                  style: TextStyle(color: Colors.orange[700], fontSize: 12)),
            ),
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
                child: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Save Cost'),
              ),
            ],
          ),
          Divider(height: 40),
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
          Divider(height: 40),
          Text(
            'App Version',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Version: $_appVersion',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 4),
                Text(
                  'Last Deploy: ${_formatDeployedAt()}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
                if (_buildGitSha.isNotEmpty) ...[
                  SizedBox(height: 4),
                  Text(
                    'Build SHA: $_buildGitSha',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 40),
          Text(
            'Player Cost Overrides',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.orange[800]),
          ),
          SizedBox(height: 8),
          Text(
            'Set specific game cost for individual players (overrides default). Leave empty/0 to use default.',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          SizedBox(height: 16),
          _isLoadingPlayers
              ? Center(child: CircularProgressIndicator())
              : _buildPlayersTable(),
        ],
      ),
    );
  }

  // Players Management Logic
  List<dynamic> _players = [];
  bool _isLoadingPlayers = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_accessChecked && !accessDenied && !_didLoadPlayersOnce) {
      _didLoadPlayersOnce = true;
      _loadPlayers();
    }
  }

  Future<void> _loadPlayers() async {
    setState(() => _isLoadingPlayers = true);
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      final teamId = prefs.getInt('team_id');
      if (teamId == null) {
        return;
      }
      final response = await apiService.getWithCache(
        'finance/team-financial-summary/$teamId',
        cacheKey: 'cache_team_summary_$teamId',
      );

      if (response['success'] == true) {
        setState(() {
          _players = response['summary'];
          // Note: team-financial-summary returns {username, balance, debt, paid}
          // It DOES NOT currently return 'custom_game_cost'.
          // We need to update the backend or use a different endpoint.
          // For now, let's assume we update backend to include it.
        });
      }
    } catch (e) {
      print('Error loading players: $e');
    } finally {
      if (mounted) setState(() => _isLoadingPlayers = false);
    }
  }

  Widget _buildPlayersTable() {
    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: _players.length,
      itemBuilder: (context, index) {
        final player = _players[index];
        final username = player['username'];
        // Placeholder for custom cost until backend is updated
        final customCost = player['custom_game_cost'] ?? '';

        return Card(
          margin: EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            title:
                Text(username, style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: SizedBox(
              width: 100,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Default',
                        isDense: true,
                        contentPadding: EdgeInsets.all(8),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      // Controller management for list view is tricky.
                      // For simplicity, we'll use a dialog to edit.
                      enabled: false,
                      controller: TextEditingController(
                          text:
                              customCost != null ? customCost.toString() : ''),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit, size: 20, color: Colors.blue),
                    onPressed: () => _showEditCostDialog(username, customCost),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showEditCostDialog(String username, dynamic currentCost) {
    TextEditingController _editController =
        TextEditingController(text: currentCost?.toString() ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Cost for $username'),
        content: TextField(
          controller: _editController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: 'Cost per game'),
        ),
        actions: [
          TextButton(
            child: Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            child: Text('Save'),
            onPressed: () {
              _updatePlayerCost(username, _editController.text);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _updatePlayerCost(String username, String costStr) async {
    int? cost = int.tryParse(costStr);

    try {
      final response =
          await apiService.putQueued('finance/update-user-financial-settings', {
        'username': username,
        'custom_game_cost': cost // null sends null to DB (resets to default)
      });

      if (response['success']) {
        final queued = response['queued'] == true;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(queued
                ? 'Saved offline. Will sync when online.'
                : 'Updated $username'),
            backgroundColor: queued ? Colors.orange : Colors.green));
        _loadTeamSettings(); // Refresh
        _loadPlayers();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }
}
