import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlayerManagementPage extends StatefulWidget {
  @override
  _PlayerManagementPageState createState() => _PlayerManagementPageState();
}

class _PlayerManagementPageState extends State<PlayerManagementPage> {
  List<dynamic> players = [];
  bool isLoading = true;
  final ApiService apiService = ApiService();

  String? user;
  bool accessDenied = false;
  static const String kUserKey = 'user';
  static const String kEnlistedPlayersKey = 'enlistedPlayers';

  // For game enlistment
  List<String> selectedUsernames = [];
  Map<String, bool> initialSelections = {};
  
  // For role management (manager promotion)
  Map<String, String> playerRoles = {}; // Current roles
  Map<String, String> initialRoles = {}; // Original roles for change detection
  
  // For sorting
  bool _isAscending = true;
  bool _playersFromCache = false;
  String _preloadStatus = 'idle';
  String? _preloadUpdatedAt;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    user = prefs.getString(kUserKey);
    bool isAdmin = prefs.getBool('is_admin') ?? false;

    if (!isAdmin) {
      setState(() {
        accessDenied = true;
        isLoading = false;
      });
    } else {
      await fetchPlayers();
      await _loadEnlistedPlayers();
    }
  }

  Future<void> _saveEnlistedPlayers(List<String> players) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(kEnlistedPlayersKey, players);
  }

  Future<void> _loadEnlistedPlayers() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> savedPlayers = prefs.getStringList(kEnlistedPlayersKey) ?? [];
    setState(() {
      selectedUsernames = savedPlayers;
      // Initialize initialSelections after players are loaded
      if (players.isNotEmpty) {
        initialSelections = {
          for (var player in players)
            player['username']: savedPlayers.contains(player['username'])
        };
      }
    });
  }

  Future<void> fetchPlayers() async {
    if (accessDenied) return;
    
    setState(() {
      isLoading = true;
    });
    try {
      final response = await apiService.getWithCache('players', cacheKey: 'cache_players');
      if (response['success']) {
        setState(() {
          players = response['users'];
          _playersFromCache = response['_cached'] == true;
          // Initialize role maps
          for (var player in players) {
            String username = player['username'];
            String role = player['role'] ?? 'player';
            playerRoles[username] = role;
            initialRoles[username] = role;
          }
          // Refresh initial selections if needed
          _loadEnlistedPlayers(); 
          isLoading = false;
        });
      } else {
        _showError(response['message']);
      }
    } catch (e) {
        _showError('Failed to fetch players: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
      _loadPreloadStatus();
    }
  }

  Future<void> _loadPreloadStatus() async {
    try {
      final status = await apiService.getPreloadStatus();
      setState(() {
        _preloadStatus = status['status'] ?? 'idle';
        _preloadUpdatedAt = status['updatedAt'] as String?;
      });
    } catch (_) {}
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: TextStyle(color: Colors.white)), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Future<void> handleEnlistUsers() async {
    try {
      List<String> usernamesToEnlist = [];
      List<String> usernamesToUnenlist = [];
      List<Map<String, String>> roleUpdates = [];

      // Determine which users to enlist and unenlist based on changes
      for (var player in players) {
        String username = player['username'];
        bool initial = initialSelections[username] ?? false;
        bool current = selectedUsernames.contains(username);
        if (current != initial) {
          if (current) {
            usernamesToEnlist.add(username);
          } else {
            usernamesToUnenlist.add(username);
          }
        }
        
        // Check for role changes
        String initialRole = initialRoles[username] ?? 'player';
        String currentRole = playerRoles[username] ?? 'player';
        if (initialRole != currentRole) {
          roleUpdates.add({'username': username, 'role': currentRole});
        }
      }

      // Reorder usernamesToEnlist based on selectedUsernames to preserve selection order
      usernamesToEnlist.sort((a, b) => selectedUsernames.indexOf(a).compareTo(selectedUsernames.indexOf(b)));

      if (usernamesToEnlist.isNotEmpty || usernamesToUnenlist.isNotEmpty) {
        if (usernamesToEnlist.isNotEmpty) {
          await apiService.post('enlist-users', {
            'usernames': usernamesToEnlist,
            'isTierMethod': false,
          });
        }

        if (usernamesToUnenlist.isNotEmpty) {
          await apiService.post('delete-enlist', {
            'usernames': usernamesToUnenlist,
            'isTierMethod': false,
          });
        }
      }
      
      // Update roles if there are changes
      if (roleUpdates.isNotEmpty) {
        await apiService.put('update-player-roles', {
          'roleUpdates': roleUpdates,
        });
      }

      _showSuccess('Players enlistment and roles updated successfully!');

      // Update initialSelections and initialRoles to reflect current state
      setState(() {
        for (var username in usernamesToEnlist) {
          initialSelections[username] = true;
        }
        for (var username in usernamesToUnenlist) {
          initialSelections[username] = false;
        }
        for (var update in roleUpdates) {
          initialRoles[update['username']!] = update['role']!;
        }
      });

      // Save the updated enlisted players to SharedPreferences
      await _saveEnlistedPlayers(selectedUsernames);
    } catch (e) {
      _showError('Error updating players enlistment: $e');
    }
  }

  void _sortPlayers() {
    setState(() {
      players.sort((a, b) {
        final first = a['username'].toString().toLowerCase();
        final second = b['username'].toString().toLowerCase();
        return _isAscending ? first.compareTo(second) : second.compareTo(first);
      });
    });
  }

  Future<void> _addPlayer() async {
    final usernameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.person_add_rounded, color: Colors.deepPurple, size: 28),
            ),
            SizedBox(width: 12),
            Text(
              'Add New Player',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person, color: Colors.deepPurple),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: emailController,
                decoration: InputDecoration(
                  labelText: 'Email (Optional)',
                  prefixIcon: Icon(Icons.email, color: Colors.deepPurple),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: passwordController,
                decoration: InputDecoration(
                  labelText: 'Password (Default: 123456)',
                  prefixIcon: Icon(Icons.lock, color: Colors.deepPurple),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () async {
              Navigator.pop(context);
              try {
                final response = await apiService.post('add-player', {
                  'username': usernameController.text,
                  'email': emailController.text,
                  'password': passwordController.text.isNotEmpty ? passwordController.text : null,
                });
                if (response['success']) {
                  _showSuccess('Player added successfully');
                  fetchPlayers();
                } else {
                  _showError(response['message']);
                }
              } catch (e) {
                _showError('Error adding player: $e');
              }
            },
            child: Text('Add', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _editPlayer(Map<String, dynamic> player) async {
    final usernameController = TextEditingController(text: player['username']);
    final emailController = TextEditingController(text: player['email']);
    final passwordController = TextEditingController(text: player['password'] ?? '');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.edit_rounded, color: Colors.blue[700], size: 28),
            ),
            SizedBox(width: 12),
            Text(
              'Edit Player',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person, color: Colors.blue[700]),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email, color: Colors.blue[700]),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock, color: Colors.blue[700]),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                obscureText: false,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () async {
              Navigator.pop(context);
              try {
                final updateData = {
                  'newUsername': usernameController.text,
                  'newEmail': emailController.text,
                };
                
                if (passwordController.text.isNotEmpty) {
                  updateData['newPassword'] = passwordController.text;
                }
                
                final response = await apiService.put('update-player/${player['username']}', updateData);
                if (response['success']) {
                  _showSuccess('Player updated successfully');
                  fetchPlayers();
                } else {
                  _showError(response['message']);
                }
              } catch (e) {
                _showError('Error updating player: $e');
              }
            },
            child: Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePlayer(String username) async {
    // Confirmation Logic Removed for Brevity in this specific edit, assuming standard delete flow
    // ... (Keeping it simple for this file overwrite to focus on new features)
    // Actually, safer to keep user confirmation.
    
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Player?'),
        content: Text('This will delete $username and all their history.'),
        actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true), 
                child: Text('Delete'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
        ]
      )
    );

    if (confirm != true) return;

    try {
      final response = await apiService.delete('delete-player/$username');
      if (response['success']) {
        _showSuccess('Player deleted successfully');
        fetchPlayers();
      } else {
        _showError(response['message']);
      }
    } catch (e) {
      _showError('Error deleting player: $e');
    }
  }

  // ==========================================
  // NEW: FINANCIAL FEATURES
  // ==========================================

  Future<void> _showSaveGameDialog() async {
    if (selectedUsernames.isEmpty) {
      _showError('No players selected to save!');
      return;
    }

    DateTime selectedDate = DateTime.now();
    TextEditingController notesController = TextEditingController();
    TextEditingController costController = TextEditingController();
    bool forceOverrideAll = false;
    
    // Map to store individual cost overrides: { 'username': custom_cost }
    Map<String, int> individualCostOverrides = {};
    // Map to store per-player override notes
    Map<String, String> individualCostNotes = {};

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            
            String _formatDate(DateTime d) {
                // Simple day name format
                List<String> days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                return "${days[d.weekday - 1]}, ${d.day}/${d.month}/${d.year}";
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                 children: [
                    Icon(Icons.save, color: Colors.green[700], size: 24),
                    SizedBox(width: 8),
                    Text('Save Game', style: TextStyle(fontSize: 18)),
                 ]
              ),
              content: Container(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // DATE - COMPACT
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 18, color: Colors.grey[600]),
                          SizedBox(width: 6),
                          TextButton(
                            style: TextButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 8)),
                            child: Text(_formatDate(selectedDate), style: TextStyle(fontSize: 14)),
                            onPressed: () async {
                              final DateTime? picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null && picked != selectedDate) {
                                setState(() => selectedDate = picked);
                              }
                            },
                          ),
                        ],
                      ),
                      
                      // NOTES - COMPACT
                      TextField(
                        controller: notesController,
                        style: TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Notes (optional)',
                          hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      SizedBox(height: 12),
                      
                      // COST SECTION
                      Text('Cost', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green[800])),
                      SizedBox(height: 6),
                      TextField(
                          controller: costController, 
                          keyboardType: TextInputType.number,
                          style: TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                              hintText: 'Use default',
                              hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              prefixIcon: Icon(Icons.attach_money, size: 18),
                          )
                      ),
                      
                      // FORCE OVERRIDE - COMPACT
                      CheckboxListTile(
                          title: Text('Force for all', style: TextStyle(fontSize: 13)),
                          subtitle: Text('Ignore individual discounts', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          value: forceOverrideAll,
                          onChanged: (val) => setState(() => forceOverrideAll = val!),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          activeColor: Colors.orange,
                      ),
                      
                      // INDIVIDUAL COSTS - COLLAPSED BY DEFAULT
                      ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text('Per-player costs', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                          leading: Icon(Icons.group, size: 18, color: Colors.grey),
                          children: [
                              Container(
                                  height: 200,
                                  child: ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: selectedUsernames.length,
                                      itemBuilder: (ctx, idx) {
                                          String username = selectedUsernames[idx];
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(username, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                                SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    SizedBox(
                                                      width: 70,
                                                      child: TextField(
                                                        style: TextStyle(fontSize: 12),
                                                        decoration: InputDecoration(
                                                          hintText: '-',
                                                          hintStyle: TextStyle(fontSize: 11),
                                                          isDense: true,
                                                          contentPadding: EdgeInsets.all(6),
                                                          border: OutlineInputBorder(),
                                                          labelText: 'Cost',
                                                          labelStyle: TextStyle(fontSize: 10),
                                                        ),
                                                        keyboardType: TextInputType.number,
                                                        onChanged: (val) {
                                                          int? v = int.tryParse(val);
                                                          if (v != null) {
                                                              individualCostOverrides[username] = v;
                                                          } else {
                                                              individualCostOverrides.remove(username);
                                                          }
                                                        },
                                                      ),
                                                    ),
                                                    SizedBox(width: 8),
                                                    Expanded(
                                                      child: TextField(
                                                        style: TextStyle(fontSize: 12),
                                                        decoration: InputDecoration(
                                                          hintText: 'Why was it changed?',
                                                          hintStyle: TextStyle(fontSize: 11, color: Colors.grey),
                                                          isDense: true,
                                                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                                          border: OutlineInputBorder(),
                                                          labelText: 'Note',
                                                          labelStyle: TextStyle(fontSize: 10),
                                                        ),
                                                        onChanged: (val) {
                                                          if (val.trim().isNotEmpty) {
                                                              individualCostNotes[username] = val.trim();
                                                          } else {
                                                              individualCostNotes.remove(username);
                                                          }
                                                        },
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          );
                                      },
                                  ),
                              )
                          ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                     // Call Backend
                     try {
                         SharedPreferences prefs = await SharedPreferences.getInstance();
                         String? token = prefs.getString('token'); 
                         
                         int teamId = 1; // Fallback
                         int? baseCost = int.tryParse(costController.text);
                         
                        final response = await apiService.postQueued('finance/record-game', {
                           'team_id': teamId,
                           'date': selectedDate.toIso8601String(),
                           'enlistedPlayers': selectedUsernames,
                           'notes': notesController.text,
                           'base_cost': baseCost,
                           'force_base_cost': forceOverrideAll,
                           'specific_player_costs': individualCostOverrides.isNotEmpty ? individualCostOverrides : null,
                           'specific_player_notes': individualCostNotes.isNotEmpty ? individualCostNotes : null,
                         });
                         
                         if (response['success']) {
                             final queued = response['queued'] == true;
                             _showSuccess(queued ? 'Saved offline. Will sync when online.' : 'Game saved successfully!');
                         } else {
                             _showError(response['message']);
                         }
                     } catch(e) {
                         _showError('Error saving game: $e');
                     }
                  },
                  child: Text('Save Game'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green[800]),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showPlayerFinancials(Map<String, dynamic> player) async {
    // Show loading first?
    // We will load data inside the dialog or before.
    // Let's load inside a StatefulBuilder in the dialog.
    
    showDialog(
      context: context,
      builder: (context) => _PlayerFinancialDialog(username: player['username'], apiService: apiService),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (accessDenied) {
      return Scaffold(
        body: Center(
          child: Text('Access Denied', style: TextStyle(color: Colors.red, fontSize: 24)),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/reka.webp'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.6), BlendMode.dstATop),
          ),
        ),
        child: Column(
          children: [
            if (_preloadStatus == 'in_progress')
              Container(
                width: double.infinity,
                color: Colors.orange[50],
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_download, size: 16, color: Colors.orange[700]),
                    SizedBox(width: 6),
                    Text('Refreshing cache in background…', style: TextStyle(color: Colors.orange[800], fontSize: 12)),
                  ],
                ),
              )
            else if (_preloadStatus == 'ready')
              Container(
                width: double.infinity,
                color: Colors.green[50],
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, size: 16, color: Colors.green[700]),
                    SizedBox(width: 6),
                    Text('Cache up to date', style: TextStyle(color: Colors.green[800], fontSize: 12)),
                  ],
                ),
              ),
            // TOP BAR
            Container(
              padding: EdgeInsets.all(16),
              color: Colors.green[700]?.withOpacity(0.9),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   Row(
                     children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                          child: Text('Playing: ${selectedUsernames.length}', style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.bold)),
                        ),
                        SizedBox(width: 8),
                         Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.amber[600], borderRadius: BorderRadius.circular(20)),
                          child: Text('Manager', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                     ],
                   ),
                   Row(
                     children: [
                        TextButton.icon(
                            onPressed: () { setState(() { _isAscending = !_isAscending; _sortPlayers(); }); },
                            icon: Icon(Icons.sort, color: Colors.white),
                            label: Text('Sort', style: TextStyle(color: Colors.white)),
                        ),
                        SizedBox(width: 4),
                        // NEW SAVE GAME BUTTON
                        ElevatedButton.icon(
                            onPressed: _showSaveGameDialog,
                            icon: Icon(Icons.save_alt),
                            label: Text('Save Game'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[800],
                                foregroundColor: Colors.white,
                            ),
                        ),
                        SizedBox(width: 4),
                        ElevatedButton.icon(
                            onPressed: handleEnlistUsers,
                            icon: Icon(Icons.check),
                            label: Text('Update'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.green[800],
                            ),
                        ),
                     ],
                   ),
                ],
              ),
            ),
            // PLAYERS LIST
            Expanded(
              child: isLoading 
                ? Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      if (_playersFromCache)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.cloud_off, color: Colors.orange[700], size: 16),
                              SizedBox(width: 6),
                              Text('Showing cached players (offline)', style: TextStyle(color: Colors.orange[700], fontSize: 12)),
                            ],
                          ),
                        ),
                      Expanded(
                        child: ListView.builder(
                            padding: EdgeInsets.all(16),
                            itemCount: players.length,
                            itemBuilder: (context, index) {
                              final player = players[index];
                              final isEnlisted = selectedUsernames.contains(player['username']);
                              
                              return Card(
                                  margin: EdgeInsets.symmetric(vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                  color: _playersFromCache ? Colors.orange[50] : Colors.white.withOpacity(0.95),
                                  child: ListTile(
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      leading: Checkbox(
                                          value: isEnlisted,
                                          onChanged: (val) {
                                              setState(() {
                                                  if (val == true) {
                                                      if (!selectedUsernames.contains(player['username'])) selectedUsernames.add(player['username']);
                                                  } else {
                                                      selectedUsernames.remove(player['username']);
                                                  }
                                              });
                                          },
                                          activeColor: Colors.green,
                                      ),
                                      title: Text(player['username'], style: TextStyle(fontWeight: FontWeight.bold)),
                                      subtitle: Text(player['email'] ?? ''),
                                      trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                              // FINANCIAL ICON
                                              IconButton(
                                                  icon: Icon(Icons.account_balance_wallet, color: Colors.teal[700]),
                                                  onPressed: () => _showPlayerFinancials(player),
                                                  tooltip: 'Wallet & Payments',
                                              ),
                                              // Existing Icons
                                              IconButton(
                                                  icon: Icon(
                                                      Icons.emoji_events, 
                                                      color: playerRoles[player['username']] == 'manager' ? Colors.amber : Colors.grey[400]
                                                  ),
                                                  onPressed: () {
                                                      setState(() {
                                                          String r = playerRoles[player['username']] ?? 'player';
                                                          playerRoles[player['username']] = r == 'manager' ? 'player' : 'manager';
                                                      });
                                                  },
                                              ),
                                              IconButton(icon: Icon(Icons.edit, color: Colors.blue), onPressed: () => _editPlayer(player)),
                                              IconButton(icon: Icon(Icons.delete, color: Colors.red), onPressed: () => _deletePlayer(player['username'])),
                                          ],
                                      ),
                                  ),
                              );
                            },
                        ),
                      ),
                    ],
                  ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addPlayer,
        child: Icon(Icons.add),
        backgroundColor: Colors.green[800],
      ),
    );
  }
}

// ==========================================
// SEPARATE CLASS FOR FINANCIAL DIALOG
// ==========================================

class _PlayerFinancialDialog extends StatefulWidget {
    final String username;
    final ApiService apiService;

    const _PlayerFinancialDialog({required this.username, required this.apiService});

    @override
    __PlayerFinancialDialogState createState() => __PlayerFinancialDialogState();
}

class __PlayerFinancialDialogState extends State<_PlayerFinancialDialog> {
    bool loading = true;
    Map<String, dynamic>? data;
    String errorMessage = '';
    bool fromCache = false;
    int pendingQueue = 0;
    int lastSyncedCount = 0;
    String? lastSyncedAt;
    
    // Filter State: 'all', 'games', 'payments'
    String _filter = 'all';

    // For Adding Payment
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    String paymentMethod = 'bit'; // Default

    @override
    void initState() {
        super.initState();
        _fetchData();
    }

    Future<void> _fetchData() async {
        setState(() { loading = true; errorMessage = ''; });
        try {
            final response = await widget.apiService.getWithCache('finance/player-financials/${widget.username}', cacheKey: 'cache_player_financials_${widget.username}');
            if (response['success'] == true) {
                setState(() { data = response; loading = false; fromCache = response['_cached'] == true; });
            } else {
                setState(() { errorMessage = response['message']; loading = false; });
            }
        } catch (e) {
            setState(() { errorMessage = e.toString(); loading = false; });
        }
        _loadQueueStats();
    }

    Future<void> _loadQueueStats() async {
        try {
            final stats = await widget.apiService.getQueueStats();
            setState(() {
                pendingQueue = stats['pending'] ?? 0;
                lastSyncedCount = stats['last_synced_count'] ?? 0;
                lastSyncedAt = stats['last_synced_at'] as String?;
            });
        } catch (_) {}
    }

    Future<void> _addPayment() async {
        if (amountController.text.isEmpty) return;
        try {
            final response = await widget.apiService.postQueued('finance/add-payment', {
                'username': widget.username,
                'team_id': 1, // TODO: Get correct team_id
                'amount': int.tryParse(amountController.text) ?? 0,
                'method': paymentMethod,
                'notes': notesController.text,
            });
            if (response['success']) {
                amountController.clear();
                notesController.clear();
                _fetchData(); // Reload
                final queued = response['queued'] == true;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(queued ? 'Payment saved offline, will sync later' : 'Payment added!'),
                    backgroundColor: queued ? Colors.orange : Colors.green));
            } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message']), backgroundColor: Colors.red));
            }
        } catch (e) {
             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
        }
    }
    
    Future<void> _deleteInfo(String type, int id) async {
        // Confirm
        bool? confirm = await showDialog(context: context, builder: (ctx) => AlertDialog(
            title: Text('Delete Record?'),
            content: Text('Are you sure you want to delete this $type? This affects the balance.'),
            actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel')),
                ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red))
            ]
        ));
        
        if (confirm != true) return;
        
        try {
            String endpoint = type == 'payment' 
                ? 'finance/delete-payment/$id' 
                : 'finance/delete-attendance/$id';
                
            final response = await widget.apiService.deleteQueued(endpoint);
            
            if (response['success']) {
                 _fetchData(); // Reload
                 if (response['queued'] == true) {
                   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deletion queued (offline)'), backgroundColor: Colors.orange));
                 }
            } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message'])));
            }
        } catch(e) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
    }
    
    String _formatDate(String isoString) {
        try {
            DateTime d = DateTime.parse(isoString);
            List<String> days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
            return "${days[d.weekday - 1]}, ${d.day}/${d.month}/${d.year}";
        } catch(e) {
            return isoString;
        }
    }

    @override
    Widget build(BuildContext context) {
        if (loading) return AlertDialog(content: SizedBox(height: 100, child: Center(child: CircularProgressIndicator())));
        if (errorMessage.isNotEmpty) return AlertDialog(content: Text('Error: $errorMessage'), actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: Text('Close'))]);

        final financialData = data!;
        final balance = financialData['balance'] ?? 0;
        // history is an object { games: [...], payments: [...] }
        final historyObj = financialData['history'] as Map<String, dynamic>? ?? {};
        final history = historyObj['games'] as List<dynamic>? ?? [];
        final payments = historyObj['payments'] as List<dynamic>? ?? [];

        // Combine for 'all' or filtered
        List<Map<String, dynamic>> displayedList = [];
        
        if (_filter == 'all' || _filter == 'games') {
            for(var g in history) {
                displayedList.add({
                    'type': 'game',
                    'date': g['date'],
                    'amount': -1 * (g['applied_cost'] as num), // displayed as negative
                    'desc': 'Game (${g['notes'] ?? ''})',
                    'id': g['attendance_id'] // Ensure ID available
                });
            }
        }
        if (_filter == 'all' || _filter == 'payments') {
            for(var p in payments) {
                displayedList.add({
                    'type': 'payment',
                    'date': p['date'],
                    'amount': p['amount'],
                    'desc': 'Payment (${p['method']})',
                    'id': p['payment_id']
                });
            }
        }
        
        // Sort by date desc
        displayedList.sort((a, b) => DateTime.parse(b['date']).compareTo(DateTime.parse(a['date'])));

        return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                    Text('${widget.username} Wallet'),
                    Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                            color: balance >= 0 ? Colors.green[100] : Colors.red[100],
                            borderRadius: BorderRadius.circular(20)
                        ),
                        child: Text(
                            '${balance >= 0 ? '+' : ''}$balance ₪',
                            style: TextStyle(
                                color: balance >= 0 ? Colors.green[800] : Colors.red[800],
                                fontWeight: FontWeight.bold
                            )
                        )
                    )
                ]
            ),
            content: Container(
                width: double.maxFinite,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        if (fromCache)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text('Showing cached data (offline)', style: TextStyle(color: Colors.orange[700], fontSize: 12)),
                          ),
                        _buildQueueInfo(),
                        // FILTER BUTTONS
                        Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                                _buildFilterBtn('all', 'All'),
                                SizedBox(width: 8),
                                _buildFilterBtn('games', 'Games'),
                                SizedBox(width: 8),
                                _buildFilterBtn('payments', 'Payments'),
                            ],
                        ),
                        SizedBox(height: 12),
                        
                        // HISTORY LIST
                        Expanded(
                            child: displayedList.isEmpty 
                                ? Center(child: Text('No history found', style: TextStyle(color: Colors.grey)))
                                : ListView.builder(
                                    itemCount: displayedList.length,
                                    itemBuilder: (ctx, idx) {
                                        final item = displayedList[idx];
                                        bool isPayment = item['type'] == 'payment';
                                        return Card(
                                            margin: EdgeInsets.symmetric(vertical: 4),
                                            color: fromCache ? Colors.orange[50] : null,
                                            child: ListTile(
                                                dense: true,
                                                leading: Icon(
                                                    isPayment ? Icons.payment : Icons.sports_basketball,
                                                    color: isPayment ? Colors.blue : Colors.orange,
                                                ),
                                                title: Text(item['desc']),
                                                subtitle: Text(_formatDate(item['date'])),
                                                trailing: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                        Text(
                                                            '${item['amount'] > 0 ? '+' : ''}${item['amount']}',
                                                            style: TextStyle(
                                                                color: item['amount'] >= 0 ? Colors.green : Colors.red,
                                                                fontWeight: FontWeight.bold,
                                                                fontSize: 16
                                                            )
                                                        ),
                                                        SizedBox(width: 8),
                                                        // DELETE BUTTON
                                                        IconButton(
                                                            icon: Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                                                            onPressed: () => _deleteInfo(item['type'], item['id']),
                                                        )
                                                    ],
                                                ),
                                            ),
                                        );
                                    }
                                )
                        ),
                        
                        Divider(),
                        
                        // ADD PAYMENT
                        ExpansionTile(
                            title: Text('Add Payment', style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold)),
                            children: [
                                Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Column(
                                        children: [
                                            Row(children: [
                                                Expanded(child: TextField(controller: amountController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Amount', prefixIcon: Icon(Icons.attach_money)))),
                                                SizedBox(width: 8),
                                                DropdownButton<String>(
                                                    value: paymentMethod,
                                                    items: ['bit', 'cash', 'paybox', 'other'].map((e)=>DropdownMenuItem(value: e, child: Text(e.toUpperCase()))).toList(),
                                                    onChanged: (v)=>setState(()=>paymentMethod=v!)
                                                )
                                            ]),
                                            TextField(controller: notesController, decoration: InputDecoration(labelText: 'Notes (Optional)')),
                                            SizedBox(height: 8),
                                            ElevatedButton(
                                                onPressed: _addPayment, 
                                                child: Text('Submit Payment'),
                                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800])
                                            )
                                        ],
                                    ),
                                )
                            ],
                        )
                    ],
                ),
            ),
            actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text('Close'))
            ],
        );
    }
    
    Widget _buildFilterBtn(String mode, String label) {
        bool active = _filter == mode;
        return InkWell(
            onTap: () => setState(() => _filter = mode),
            child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: active ? Colors.blue[100] : Colors.grey[200],
                    borderRadius: BorderRadius.circular(15),
                    border: active ? Border.all(color: Colors.blue) : null
                ),
                child: Text(label, style: TextStyle(color: active ? Colors.blue[800] : Colors.black87, fontWeight: active?FontWeight.bold:FontWeight.normal))
            ),
        );
    }

    Widget _buildQueueInfo() {
        final syncedInfo = lastSyncedAt != null
            ? 'Last synced: $lastSyncedCount at ${_fmtTime(lastSyncedAt)}'
            : 'No sync yet';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Queue: $pendingQueue pending', style: TextStyle(fontSize: 12, color: Colors.grey[800])),
              Text(syncedInfo, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        );
    }

    String _fmtTime(String? iso) {
        if (iso == null) return '';
        try {
          final d = DateTime.parse(iso);
          String two(int n) => n.toString().padLeft(2, '0');
          return '${two(d.hour)}:${two(d.minute)}';
        } catch (_) {
          return iso;
        }
    }
}
