import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/team_preferences.dart';

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

  Future<int?> _getTeamId() async {
    final int? teamId = await TeamPreferences.getTeamId();
    if (teamId == null) {
      _showError('Team not found. Please log in again.');
    }
    return teamId;
  }

  Future<void> fetchPlayers() async {
    if (accessDenied) return;
    
    setState(() {
      isLoading = true;
    });
    try {
      final response = await apiService.get('players');
      if (response['success']) {
        setState(() {
          players = response['users'];
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
    }
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

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                 children: [
                    Icon(Icons.save_as, color: Colors.green[800]),
                    SizedBox(width: 8),
                    Text('Save Game Record'),
                 ]
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Archive current Enlisted players as a played game.'),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Text('Date:', style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(width: 8),
                      TextButton.icon(
                        icon: Icon(Icons.calendar_today),
                        label: Text("${selectedDate.toLocal()}".split(' ')[0]),
                        onPressed: () async {
                          final DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null && picked != selectedDate) {
                            setState(() {
                              selectedDate = picked;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: notesController,
                    decoration: InputDecoration(
                      labelText: 'Notes (Optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 16),
                  Text('${selectedUsernames.length} Players enlisted.', style: TextStyle(fontStyle: FontStyle.italic)),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                     // Call Backend
                     try {
                         final int? teamId = await _getTeamId();
                         if (teamId == null) return;

                        final response = await apiService.post('finance/record-game', {
                           'team_id': teamId,
                           'date': selectedDate.toIso8601String(),
                           'enlistedPlayers': selectedUsernames,
                           'notes': notesController.text,
                         });
                         
                         if (response['success']) {
                             _showSuccess('Game saved successfully!');
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
                : ListView.builder(
                    padding: EdgeInsets.all(16),
                    itemCount: players.length,
                    itemBuilder: (context, index) {
                      final player = players[index];
                      final isEnlisted = selectedUsernames.contains(player['username']);
                      
                      return Card(
                          margin: EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          color: Colors.white.withOpacity(0.95),
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
            final response = await widget.apiService.get('finance/player-financials/${widget.username}');
            if (response['success']) {
                setState(() { data = response; loading = false; });
            } else {
                setState(() { errorMessage = response['message']; loading = false; });
            }
        } catch (e) {
            setState(() { errorMessage = e.toString(); loading = false; });
        }
    }

    Future<int?> _getTeamId() async {
        final int? teamId = await TeamPreferences.getTeamId();
        if (teamId == null) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Team not found. Please log in again.'), backgroundColor: Colors.red),
            );
        }
        return teamId;
    }

    Future<void> _addPayment() async {
        if (amountController.text.isEmpty) return;
        final int? teamId = await _getTeamId();
        if (teamId == null) return;
        try {
            final response = await widget.apiService.post('finance/add-payment', {
                'username': widget.username,
                'team_id': teamId,
                'amount': int.tryParse(amountController.text) ?? 0,
                'method': paymentMethod,
                'notes': notesController.text,
            });
            if (response['success']) {
                amountController.clear();
                notesController.clear();
                _fetchData(); // Reload
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment added!'), backgroundColor: Colors.green));
            } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message']), backgroundColor: Colors.red));
            }
        } catch (e) {
             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
        }
    }

    @override
    Widget build(BuildContext context) {
        return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('${widget.username} - Financials'),
            content: Container(
                width: double.maxFinite,
                height: 500, // Fixed height for scrolling
                child: loading ? Center(child: CircularProgressIndicator()) : errorMessage.isNotEmpty ? Center(child: Text(errorMessage, style: TextStyle(color: Colors.red))) : Column(
                    children: [
                        // BALANCE SUMMARY
                        Container(
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                                color: (data?['balance'] ?? 0) >= 0 ? Colors.green[100] : Colors.red[100],
                                borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                    Text('Balance:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                    Text(
                                        '${data?['balance'] ?? 0} ₪', 
                                        style: TextStyle(
                                            fontSize: 24, 
                                            fontWeight: FontWeight.bold,
                                            color: (data?['balance'] ?? 0) >= 0 ? Colors.green[800] : Colors.red[800],
                                        )
                                    ),
                                ],
                            ),
                        ),
                        SizedBox(height: 16),
                        
                        // TABS or SECTIONS? Let's just do an ExpansionTile for "Add Payment"
                        ExpansionTile(
                            title: Text('Add Payment', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[800])),
                            children: [
                                Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                    child: Column(
                                        children: [
                                            Row(
                                                children: [
                                                    Expanded(
                                                        child: TextField(
                                                            controller: amountController,
                                                            keyboardType: TextInputType.number,
                                                            decoration: InputDecoration(labelText: 'Amount', prefixIcon: Icon(Icons.attach_money)),
                                                        ),
                                                    ),
                                                    SizedBox(width: 8),
                                                    DropdownButton<String>(
                                                        value: paymentMethod,
                                                        items: ['bit', 'paybox', 'cash', 'other'].map((m) => DropdownMenuItem(child: Text(m), value: m)).toList(),
                                                        onChanged: (v) => setState(() => paymentMethod = v!),
                                                    ),
                                                ],
                                            ),
                                            TextField(controller: notesController, decoration: InputDecoration(labelText: 'Notes (Optional)')),
                                            SizedBox(height: 8),
                                            ElevatedButton(onPressed: _addPayment, child: Text('Submit Payment')),
                                            SizedBox(height: 8),
                                        ],
                                    ),
                                ),
                            ],
                        ),

                        Divider(),
                        Text('History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Expanded(
                            child: ListView(
                                children: [
                                    // Combine games and payments? separate?
                                    // Only showing payments for now based on typical need, but user asked for "how many games".
                                    // data['history']['games'] and data['history']['payments']
                                    if (data?['history']?['games'] != null)
                                        ...List<Widget>.from(data!['history']['games'].map((g) => ListTile(
                                            leading: Icon(Icons.sports_basketball, color: Colors.grey),
                                            title: Text('Game: ${g['date'].toString().split('T')[0]}'),
                                            subtitle: Text(g['notes'] ?? ''),
                                            trailing: Text('-${g['applied_cost']} ₪', style: TextStyle(color: Colors.red)),
                                        ))),
                                    if (data?['history']?['payments'] != null)
                                        ...List<Widget>.from(data!['history']['payments'].map((p) => ListTile(
                                            leading: Icon(Icons.payment, color: Colors.green),
                                            title: Text('Payment: ${p['method']}'),
                                            subtitle: Text('${p['date'].toString().split('T')[0]} ${p['notes'] ?? ''}'),
                                            trailing: Text('+${p['amount']} ₪', style: TextStyle(color: Colors.green)),
                                        ))),
                                ],
                            ),
                        ),
                    ],
                ),
            ),
            actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text('Close')),
            ],
        );
    }
}
