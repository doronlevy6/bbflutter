import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/basketball_spinner.dart';
import 'dart:async';
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;

enum PlayerSortMode {
  nameAsc,
  nameDesc,
  enlistedFirst,
  notEnlistedFirst,
  managerFirst,
  guestFirst,
}

enum PlayerRoleFilter {
  all,
  noGuests,
  guestsOnly,
}

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
  PlayerSortMode _sortMode = PlayerSortMode.nameAsc;
  PlayerRoleFilter _roleFilter = PlayerRoleFilter.noGuests;
  bool _playersFromCache = false;
  String _preloadStatus = 'idle';
  String? _preloadUpdatedAt;

  StreamSubscription<bool>? _syncSub;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _checkAccess();
    _startSyncListener();
  }

  void _startSyncListener() {
    _syncSub = apiService.isSyncing.listen((isSyncing) {
      if (mounted) {
        setState(() {
          _isSyncing = isSyncing;
        });
      }
    });
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
    final teamId = prefs.getInt('team_id');
    // Keep legacy/global key for pages that still read it,
    // and team-scoped key for correct multi-team isolation.
    await prefs.setStringList(kEnlistedPlayersKey, players);
    if (teamId != null) {
      await prefs.setStringList('${kEnlistedPlayersKey}_$teamId', players);
    }
    // Keep Interactive Builder in sync immediately after manager update.
    await prefs.setStringList('interactive_selection', players);
  }

  Future<void> _invalidateTeamSummaryCache() async {
    final prefs = await SharedPreferences.getInstance();
    final teamId = prefs.getInt('team_id');
    if (teamId == null) return;
    await apiService.clearCache('cache_team_summary_$teamId');
  }

  Future<void> _loadEnlistedPlayers() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final teamId = prefs.getInt('team_id');
    final key =
        teamId == null ? kEnlistedPlayersKey : '${kEnlistedPlayersKey}_$teamId';
    List<String> savedPlayers = prefs.getStringList(key) ??
        prefs.getStringList(kEnlistedPlayersKey) ??
        [];
    setState(() {
      selectedUsernames = savedPlayers;
      // Initialize initialSelections after players are loaded
      if (players.isNotEmpty) {
        initialSelections = {
          for (var player in players)
            player['username']: savedPlayers.contains(player['username'])
        };
      }
      _sortPlayersInternal();
    });
  }

  Future<void> fetchPlayers() async {
    if (accessDenied) return;

    final prefs = await SharedPreferences.getInstance();
    final teamId = prefs.getInt('team_id');
    final cacheKey =
        teamId == null ? 'cache_players' : 'cache_players_team_$teamId';

    // 1. Try Cache Immediately
    final cached = await apiService.getFromCacheOnly(cacheKey);
    if (cached != null && cached['success'] == true && mounted) {
      _processPlayersData(cached);
      setState(() => isLoading = false);
    } else {
      setState(() => isLoading = true);
    }

    // 2. Fetch Network (Background update)
    try {
      final response =
          await apiService.getWithCache('players', cacheKey: cacheKey);
      if (mounted && response['success'] == true) {
        _processPlayersData(response);
      } else if (mounted && players.isEmpty) {
        _showError(response['message']);
      }
    } catch (e) {
      if (mounted && players.isEmpty) _showError('Failed to fetch players: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
      _loadPreloadStatus();
    }
  }

  void _processPlayersData(Map<String, dynamic> data) {
    setState(() {
      players = data['users'];
      _playersFromCache = data['_cached'] == true;
      // Initialize role maps
      playerRoles.clear();
      initialRoles.clear();
      for (var player in players) {
        String username = player['username'];
        String role = (player['role'] ?? 'player').toString().toLowerCase();
        if (role != 'manager' && role != 'guest') {
          role = 'player';
        }
        playerRoles[username] = role;
        initialRoles[username] = role;
      }
      _sortPlayersInternal();
      // Refresh initial selections if needed
      _loadEnlistedPlayers();
    });
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
      SnackBar(
          content: Text(message, style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.red),
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
        String initialRole = (initialRoles[username] ?? 'player').toLowerCase();
        String currentRole = _roleOf(username);
        if (initialRole != currentRole) {
          roleUpdates.add({'username': username, 'role': currentRole});
        }
      }

      // Reorder usernamesToEnlist based on selectedUsernames to preserve selection order
      usernamesToEnlist.sort((a, b) =>
          selectedUsernames.indexOf(a).compareTo(selectedUsernames.indexOf(b)));

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
        await _invalidateTeamSummaryCache();
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

  String _playerName(Map player) {
    return (player['username'] ?? '').toString().toLowerCase();
  }

  String _roleOf(String username) {
    final raw = (playerRoles[username] ?? 'player').toLowerCase();
    if (raw == 'manager' || raw == 'guest') return raw;
    return 'player';
  }

  bool _isGuest(String username) => _roleOf(username) == 'guest';

  List<dynamic> _visiblePlayers() {
    if (_roleFilter == PlayerRoleFilter.all) return players;
    return players.where((p) {
      final map = p as Map;
      final username = (map['username'] ?? '').toString();
      final isGuest = _isGuest(username);
      if (_roleFilter == PlayerRoleFilter.noGuests) return !isGuest;
      return isGuest;
    }).toList();
  }

  bool _areAllVisibleSelected() {
    final visible = _visiblePlayers();
    if (visible.isEmpty) return false;
    for (final p in visible) {
      final map = p as Map;
      final username = (map['username'] ?? '').toString();
      if (!selectedUsernames.contains(username)) {
        return false;
      }
    }
    return true;
  }

  void _toggleSelectAllVisible() {
    final visible = _visiblePlayers();
    final allSelected = _areAllVisibleSelected();
    setState(() {
      if (allSelected) {
        for (final p in visible) {
          final map = p as Map;
          final username = (map['username'] ?? '').toString();
          selectedUsernames.remove(username);
        }
      } else {
        for (final p in visible) {
          final map = p as Map;
          final username = (map['username'] ?? '').toString();
          if (!selectedUsernames.contains(username)) {
            selectedUsernames.add(username);
          }
        }
      }
      _sortPlayersInternal();
    });
  }

  int _compareByName(Map a, Map b) {
    return _playerName(a).compareTo(_playerName(b));
  }

  void _sortPlayersInternal() {
    players.sort((a, b) {
      final first = a as Map;
      final second = b as Map;
      final firstName = _compareByName(first, second);

      switch (_sortMode) {
        case PlayerSortMode.nameAsc:
          return firstName;
        case PlayerSortMode.nameDesc:
          return -firstName;
        case PlayerSortMode.enlistedFirst:
          final firstEnlisted = selectedUsernames.contains(first['username']);
          final secondEnlisted = selectedUsernames.contains(second['username']);
          if (firstEnlisted != secondEnlisted) {
            return firstEnlisted ? -1 : 1;
          }
          return firstName;
        case PlayerSortMode.notEnlistedFirst:
          final firstEnlisted = selectedUsernames.contains(first['username']);
          final secondEnlisted = selectedUsernames.contains(second['username']);
          if (firstEnlisted != secondEnlisted) {
            return firstEnlisted ? 1 : -1;
          }
          return firstName;
        case PlayerSortMode.managerFirst:
          final firstManager =
              _roleOf((first['username'] ?? '').toString()) == 'manager';
          final secondManager =
              _roleOf((second['username'] ?? '').toString()) == 'manager';
          if (firstManager != secondManager) {
            return firstManager ? -1 : 1;
          }
          return firstName;
        case PlayerSortMode.guestFirst:
          final firstGuest =
              _roleOf((first['username'] ?? '').toString()) == 'guest';
          final secondGuest =
              _roleOf((second['username'] ?? '').toString()) == 'guest';
          if (firstGuest != secondGuest) {
            return firstGuest ? -1 : 1;
          }
          return firstName;
      }
    });
  }

  String _sortLabel() {
    switch (_sortMode) {
      case PlayerSortMode.nameAsc:
        return 'Name A-Z';
      case PlayerSortMode.nameDesc:
        return 'Name Z-A';
      case PlayerSortMode.enlistedFirst:
        return 'Enlisted First';
      case PlayerSortMode.notEnlistedFirst:
        return 'Not Enlisted First';
      case PlayerSortMode.managerFirst:
        return 'Managers First';
      case PlayerSortMode.guestFirst:
        return 'Guests First';
    }
  }

  Future<void> _addPlayer() async {
    final usernameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = 'player';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.person_add_rounded,
                          color: Colors.deepPurple, size: 28),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Add New Player',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
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
                          prefixIcon:
                              Icon(Icons.person, color: Colors.deepPurple),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      SizedBox(height: 16),
                      TextField(
                        controller: emailController,
                        decoration: InputDecoration(
                          labelText: 'Email (Optional)',
                          prefixIcon:
                              Icon(Icons.email, color: Colors.deepPurple),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      SizedBox(height: 16),
                      TextField(
                        controller: passwordController,
                        decoration: InputDecoration(
                          labelText: 'Password (Default: 123456)',
                          prefixIcon:
                              Icon(Icons.lock, color: Colors.deepPurple),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        obscureText: true,
                      ),
                      SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedRole,
                        decoration: InputDecoration(
                          labelText: 'Role',
                          prefixIcon:
                              Icon(Icons.badge, color: Colors.deepPurple),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'player', child: Text('Player')),
                          DropdownMenuItem(
                              value: 'guest', child: Text('Guest')),
                          DropdownMenuItem(
                              value: 'manager', child: Text('Manager')),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            selectedRole = value ?? 'player';
                          });
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel',
                        style: TextStyle(color: Colors.grey[600])),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding:
                          EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    onPressed: () async {
                      final username = usernameController.text.trim();
                      final email = emailController.text.trim();
                      final password = passwordController.text.trim();

                      if (username.isEmpty) {
                        _showError('Username is required');
                        return;
                      }

                      try {
                        final response = await apiService.post('add-player', {
                          'username': username,
                          'email': email,
                          'password': password.isNotEmpty ? password : null,
                          'role': selectedRole,
                        });
                        if (response['success']) {
                          Navigator.pop(context);
                          _showSuccess('Player added successfully');
                          await _invalidateTeamSummaryCache();
                          await fetchPlayers();
                        } else {
                          _showError(response['message']);
                        }
                      } catch (e) {
                        _showError('Error adding player: $e');
                      }
                    },
                    child: Text('Add',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              )),
    );
  }

  Future<void> _editPlayer(Map<String, dynamic> player) async {
    final usernameController = TextEditingController(text: player['username']);
    final emailController = TextEditingController(text: player['email']);
    final passwordController =
        TextEditingController(text: player['password'] ?? '');
    String selectedRole = _roleOf((player['username'] ?? '').toString());

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.edit_rounded,
                          color: Colors.blue[700], size: 28),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Edit Player',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
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
                          prefixIcon:
                              Icon(Icons.person, color: Colors.blue[700]),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      SizedBox(height: 16),
                      TextField(
                        controller: emailController,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon:
                              Icon(Icons.email, color: Colors.blue[700]),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      SizedBox(height: 16),
                      TextField(
                        controller: passwordController,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock, color: Colors.blue[700]),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        obscureText: false,
                      ),
                      SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedRole,
                        decoration: InputDecoration(
                          labelText: 'Role',
                          prefixIcon:
                              Icon(Icons.badge, color: Colors.blue[700]),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'player', child: Text('Player')),
                          DropdownMenuItem(
                              value: 'guest', child: Text('Guest')),
                          DropdownMenuItem(
                              value: 'manager', child: Text('Manager')),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            selectedRole = value ?? 'player';
                          });
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel',
                        style: TextStyle(color: Colors.grey[600])),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding:
                          EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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

                        final response = await apiService.put(
                            'update-player/${player['username']}', updateData);
                        if (response['success']) {
                          final usernameToUse = usernameController.text.trim();
                          if (usernameToUse.isNotEmpty) {
                            await apiService.put('update-player-roles', {
                              'roleUpdates': [
                                {
                                  'username': usernameToUse,
                                  'role': selectedRole
                                }
                              ],
                            });
                          }
                          await _invalidateTeamSummaryCache();
                          _showSuccess('Player updated successfully');
                          fetchPlayers();
                        } else {
                          _showError(response['message']);
                        }
                      } catch (e) {
                        _showError('Error updating player: $e');
                      }
                    },
                    child: Text('Save',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              )),
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
                content:
                    Text('This will delete $username and all their history.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text('Cancel')),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text('Delete'),
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  ),
                ]));

    if (confirm != true) return;

    try {
      final response = await apiService.delete('delete-player/$username');
      if (response['success']) {
        _showSuccess('Player deleted successfully');
        await _invalidateTeamSummaryCache();
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
    TimeOfDay selectedTime =
        TimeOfDay(hour: 19, minute: 30); // Default: 7:30 PM
    TextEditingController notesController = TextEditingController();
    TextEditingController costController = TextEditingController();
    TextEditingController hallCostController = TextEditingController();
    bool forceOverrideAll = false;

    // Map to store individual cost overrides: { 'username': custom_cost }
    Map<String, int> individualCostOverrides = {};
    // Map to store per-player override notes
    Map<String, String> individualCostNotes = {};

    // Game session selection
    String sessionMode = 'new'; // 'new' or 'existing'
    String? selectedSessionId;
    List<Map<String, dynamic>> availableSessions = [];
    bool loadingSessions = false;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            String _formatDate(DateTime d) {
              List<String> days = [
                'Mon',
                'Tue',
                'Wed',
                'Thu',
                'Fri',
                'Sat',
                'Sun'
              ];
              return "${days[d.weekday - 1]}, ${d.day}/${d.month}/${d.year}";
            }

            String _formatTime(TimeOfDay t) {
              final hour = t.hour.toString().padLeft(2, '0');
              final minute = t.minute.toString().padLeft(2, '0');
              return "$hour:$minute";
            }

            Future<void> _loadGameSessions() async {
              setState(() => loadingSessions = true);
              try {
                final response = await apiService.get('finance/game-sessions');
                if (response['success']) {
                  setState(() {
                    availableSessions =
                        List<Map<String, dynamic>>.from(response['sessions']);
                    loadingSessions = false;
                  });
                }
              } catch (e) {
                print('Error loading sessions: $e');
                setState(() => loadingSessions = false);
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(children: [
                Icon(Icons.save, color: Colors.green[700], size: 24),
                SizedBox(width: 8),
                Text('Save Game', style: TextStyle(fontSize: 18)),
              ]),
              content: Container(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // SESSION MODE SELECTION
                      Text('Game Session',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.blue[800])),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<String>(
                              title: Text('New Session',
                                  style: TextStyle(fontSize: 13)),
                              value: 'new',
                              groupValue: sessionMode,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (val) =>
                                  setState(() => sessionMode = val!),
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<String>(
                              title: Text('Existing',
                                  style: TextStyle(fontSize: 13)),
                              value: 'existing',
                              groupValue: sessionMode,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (val) {
                                setState(() => sessionMode = val!);
                                if (availableSessions.isEmpty &&
                                    !loadingSessions) {
                                  _loadGameSessions();
                                }
                              },
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 12),

                      // EXISTING SESSION SELECTION
                      if (sessionMode == 'existing') ...[
                        if (loadingSessions)
                          Center(child: CircularProgressIndicator())
                        else if (availableSessions.isEmpty)
                          Text('No existing sessions found',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey))
                        else
                          DropdownButtonFormField<String>(
                            decoration: InputDecoration(
                              labelText: 'Select Session',
                              labelStyle: TextStyle(fontSize: 13),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                            ),
                            value: selectedSessionId,
                            menuMaxHeight: 120, // Limit height to show ~2 items
                            items: availableSessions.map((session) {
                              final sessionId =
                                  session['game_session_id'] as String;
                              final playerCount = session['player_count'] ?? 0;
                              final notes = session['notes'] ?? '';
                              return DropdownMenuItem(
                                value: sessionId,
                                child: Text(
                                  '$sessionId ($playerCount players) ${notes.isNotEmpty ? "- $notes" : ""}',
                                  style: TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() => selectedSessionId = val);
                              // Parse selected session to populate date and time
                              if (val != null) {
                                try {
                                  final parts = val.split('_');
                                  if (parts.length == 2) {
                                    final dateParts = parts[0].split('-');
                                    final timeParts = parts[1].split(':');
                                    setState(() {
                                      selectedDate = DateTime(
                                        int.parse(dateParts[0]),
                                        int.parse(dateParts[1]),
                                        int.parse(dateParts[2]),
                                      );
                                      selectedTime = TimeOfDay(
                                        hour: int.parse(timeParts[0]),
                                        minute: int.parse(timeParts[1]),
                                      );
                                    });
                                  }
                                } catch (e) {
                                  print('Error parsing session ID: $e');
                                }
                              }
                            },
                          ),
                        SizedBox(height: 8),
                        // MANAGE SESSION BUTTON
                        if (selectedSessionId != null)
                          TextButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _showManageSessionDialog(selectedSessionId!);
                            },
                            icon: Icon(Icons.edit, size: 16),
                            label: Text('Manage Players in Session',
                                style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.blue[700],
                            ),
                          ),
                        SizedBox(height: 12),
                      ],

                      // DATE & TIME SELECTION (for new sessions or display for existing)
                      if (sessionMode == 'new') ...[
                        Text('Date & Time',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.green[800])),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            // DATE PICKER
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: Icon(Icons.calendar_today, size: 16),
                                label: Text(_formatDate(selectedDate),
                                    style: TextStyle(fontSize: 13)),
                                style: OutlinedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                ),
                                onPressed: () async {
                                  final DateTime? picked = await showDatePicker(
                                    context: context,
                                    initialDate: selectedDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                  );
                                  if (picked != null &&
                                      picked != selectedDate) {
                                    setState(() => selectedDate = picked);
                                  }
                                },
                              ),
                            ),
                            SizedBox(width: 8),
                            // TIME PICKER
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: Icon(Icons.access_time, size: 16),
                                label: Text(_formatTime(selectedTime),
                                    style: TextStyle(fontSize: 13)),
                                style: OutlinedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                ),
                                onPressed: () async {
                                  final TimeOfDay? picked =
                                      await showTimePicker(
                                    context: context,
                                    initialTime: selectedTime,
                                    builder:
                                        (BuildContext context, Widget? child) {
                                      return MediaQuery(
                                        data: MediaQuery.of(context).copyWith(
                                            alwaysUse24HourFormat: true),
                                        child: child!,
                                      );
                                    },
                                  );
                                  if (picked != null) {
                                    // Round to nearest 15 minutes
                                    int roundedMinute =
                                        ((picked.minute / 15).round() * 15) %
                                            60;
                                    final roundedTime = TimeOfDay(
                                        hour: picked.hour,
                                        minute: roundedMinute);
                                    setState(() => selectedTime = roundedTime);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                      ] else ...[
                        // Display selected session date & time (read-only)
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 16, color: Colors.blue[700]),
                              SizedBox(width: 8),
                              Text(
                                '${_formatDate(selectedDate)} at ${_formatTime(selectedTime)}',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.blue[900]),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 12),
                      ],

                      // NOTES - COMPACT
                      TextField(
                        controller: notesController,
                        style: TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Notes (optional)',
                          hintStyle:
                              TextStyle(fontSize: 12, color: Colors.grey),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      SizedBox(height: 12),

                      // HALL COST SECTION
                      Text('Hall Cost',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.teal[800])),
                      SizedBox(height: 6),
                      TextField(
                        controller: hallCostController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Use hall default',
                          helperText:
                              'Only fill this if this specific night cost differently.',
                          helperStyle:
                              TextStyle(fontSize: 11, color: Colors.grey[600]),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          prefixIcon: Icon(Icons.home_work, size: 18),
                        ),
                      ),
                      SizedBox(height: 12),

                      // COST SECTION
                      Text('Cost',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.green[800])),
                      SizedBox(height: 6),
                      TextField(
                          controller: costController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Use default',
                            hintStyle:
                                TextStyle(fontSize: 12, color: Colors.grey),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            prefixIcon: Icon(Icons.attach_money, size: 18),
                          )),

                      // FORCE OVERRIDE - COMPACT
                      CheckboxListTile(
                        title: Text('Force for all',
                            style: TextStyle(fontSize: 13)),
                        subtitle: Text('Ignore individual discounts',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                        value: forceOverrideAll,
                        onChanged: (val) =>
                            setState(() => forceOverrideAll = val!),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        activeColor: Colors.orange,
                      ),

                      // INDIVIDUAL COSTS - COLLAPSED BY DEFAULT
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text('Per-player costs',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[700])),
                        leading:
                            Icon(Icons.group, size: 18, color: Colors.grey),
                        children: [
                          Container(
                            height: 200,
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: selectedUsernames.length,
                              itemBuilder: (ctx, idx) {
                                String username = selectedUsernames[idx];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 4, horizontal: 4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(username,
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600)),
                                      SizedBox(height: 6),
                                      Row(
                                        children: [
                                          SizedBox(
                                            width: 70,
                                            child: TextField(
                                              style: TextStyle(fontSize: 12),
                                              decoration: InputDecoration(
                                                hintText: '-',
                                                hintStyle:
                                                    TextStyle(fontSize: 11),
                                                isDense: true,
                                                contentPadding:
                                                    EdgeInsets.all(6),
                                                border: OutlineInputBorder(),
                                                labelText: 'Cost',
                                                labelStyle:
                                                    TextStyle(fontSize: 10),
                                              ),
                                              keyboardType:
                                                  TextInputType.number,
                                              onChanged: (val) {
                                                int? v = int.tryParse(val);
                                                if (v != null) {
                                                  individualCostOverrides[
                                                      username] = v;
                                                } else {
                                                  individualCostOverrides
                                                      .remove(username);
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
                                                hintStyle: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey),
                                                isDense: true,
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 10),
                                                border: OutlineInputBorder(),
                                                labelText: 'Note',
                                                labelStyle:
                                                    TextStyle(fontSize: 10),
                                              ),
                                              onChanged: (val) {
                                                if (val.trim().isNotEmpty) {
                                                  individualCostNotes[
                                                      username] = val.trim();
                                                } else {
                                                  individualCostNotes
                                                      .remove(username);
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
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel')),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    // Call Backend
                    try {
                      int? baseCost = int.tryParse(costController.text);
                      int? hallCost =
                          int.tryParse(hallCostController.text.trim());

                      // Format date and time
                      final timeStr = _formatTime(selectedTime);

                      final response =
                          await apiService.postQueued('finance/record-game', {
                        'date': selectedDate.toIso8601String(),
                        'time': timeStr,
                        'enlistedPlayers': selectedUsernames,
                        'notes': notesController.text,
                        'base_cost': baseCost,
                        if (hallCost != null) 'hall_cost': hallCost,
                        'force_base_cost': forceOverrideAll,
                        'specific_player_costs':
                            individualCostOverrides.isNotEmpty
                                ? individualCostOverrides
                                : null,
                        'specific_player_notes': individualCostNotes.isNotEmpty
                            ? individualCostNotes
                            : null,
                      });

                      if (response['success']) {
                        final queued = response['queued'] == true;
                        _showSuccess(queued
                            ? 'Saved offline. Will sync when online.'
                            : 'Game saved successfully!');
                      } else {
                        _showError(response['message']);
                      }
                    } catch (e) {
                      _showError('Error saving game: $e');
                    }
                  },
                  child: Text('Save Game'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[800]),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showManageSessionDialog(String gameSessionId) async {
    // Load session data
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator()),
    );

    try {
      final response =
          await apiService.get('finance/game-session-players/$gameSessionId');
      Navigator.of(context).pop(); // Close loading

      if (!mounted) return;

      if (response['success'] != true) {
        _showError('Failed to load session: ${response['message']}');
        return;
      }

      final game = response['game'];
      final sessionPlayers =
          List<Map<String, dynamic>>.from(response['players']);
      final notesController =
          TextEditingController(text: (game['notes'] ?? '').toString());
      final baseCostController =
          TextEditingController(text: (game['base_cost'] ?? '').toString());
      String? addPlayerUsername;
      bool isAddingPlayer = false;
      String? addPlayerSaveStatus;
      bool addPlayerSaved = false;
      final addCostController = TextEditingController();
      final addNoteController = TextEditingController();

      // Show management dialog
      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setState) {
            final activeUsernames =
                sessionPlayers.map((p) => p['username'].toString()).toSet();
            final availablePlayers = players
                .where((p) => !activeUsernames.contains(p['username']))
                .map((p) => p['username'].toString())
                .toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

            Future<void> saveGameDetails() async {
              try {
                final parsedCost = int.tryParse(baseCostController.text.trim());
                final updateData = {
                  'notes': notesController.text.trim(),
                  if (parsedCost != null) 'base_cost': parsedCost,
                };
                final updateRes = await apiService.put(
                  'finance/game-sessions/$gameSessionId',
                  updateData,
                );
                if (updateRes['success'] == true) {
                  final updatedGame = updateRes['game'];
                  if (updatedGame is Map<String, dynamic>) {
                    game['notes'] = updatedGame['notes'];
                    game['base_cost'] = updatedGame['base_cost'];
                  }
                  await _invalidateTeamSummaryCache();
                  _showSuccess('Game details updated');
                  setState(() {});
                } else {
                  _showError(updateRes['message'] ?? 'Update failed');
                }
              } catch (e) {
                _showError('Error updating game: $e');
              }
            }

            Future<void> addPlayerToSession() async {
              final username = addPlayerUsername;
              if (username == null || username.isEmpty) {
                _showError('Choose a player first');
                return;
              }

              try {
                setState(() {
                  isAddingPlayer = true;
                  addPlayerSaved = false;
                  addPlayerSaveStatus = 'Saving to database...';
                });
                final parsedCost = int.tryParse(addCostController.text.trim());
                final addRes = await apiService.post(
                  'finance/game-sessions/$gameSessionId/players',
                  {
                    'username': username,
                    if (parsedCost != null) 'applied_cost': parsedCost,
                    'adjustment_note': addNoteController.text.trim(),
                  },
                );
                if (addRes['success'] == true) {
                  final newPlayer = addRes['player'];
                  if (newPlayer is Map<String, dynamic>) {
                    sessionPlayers.add(newPlayer);
                  }
                  addPlayerUsername = null;
                  addCostController.clear();
                  addNoteController.clear();
                  await _invalidateTeamSummaryCache();
                  setState(() {
                    isAddingPlayer = false;
                    addPlayerSaved = true;
                    addPlayerSaveStatus =
                        '$username saved in database and added to this game';
                  });
                } else {
                  setState(() {
                    isAddingPlayer = false;
                    addPlayerSaved = false;
                    addPlayerSaveStatus =
                        addRes['message']?.toString() ?? 'Save failed';
                  });
                  _showError(addRes['message'] ?? 'Add failed');
                }
              } catch (e) {
                setState(() {
                  isAddingPlayer = false;
                  addPlayerSaved = false;
                  addPlayerSaveStatus = 'Save failed';
                });
                _showError('Error adding player: $e');
              }
            }

            Future<void> editSessionPlayer(
              Map<String, dynamic> player,
              int index,
            ) async {
              final costController = TextEditingController(
                text: (player['applied_cost'] ?? '').toString(),
              );
              final noteController = TextEditingController(
                text: (player['adjustment_note'] ?? '').toString(),
              );

              final shouldSave = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Edit Player Charge'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: costController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Cost',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SizedBox(height: 12),
                      TextField(
                        controller: noteController,
                        decoration: InputDecoration(
                          labelText: 'Note',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text('Save'),
                    ),
                  ],
                ),
              );

              if (shouldSave != true) return;

              try {
                final parsedCost = int.tryParse(costController.text.trim());
                if (parsedCost == null) {
                  _showError('Cost must be a number');
                  return;
                }

                final updateRes = await apiService.put(
                  'finance/game-attendance/${player['attendance_id']}',
                  {
                    'applied_cost': parsedCost,
                    'adjustment_note': noteController.text.trim(),
                  },
                );
                if (updateRes['success'] == true) {
                  final updatedPlayer = updateRes['player'];
                  if (updatedPlayer is Map<String, dynamic>) {
                    sessionPlayers[index] = updatedPlayer;
                  }
                  await _invalidateTeamSummaryCache();
                  _showSuccess('Player charge updated');
                  setState(() {});
                } else {
                  _showError(updateRes['message'] ?? 'Update failed');
                }
              } catch (e) {
                _showError('Error updating player: $e');
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.people, color: Colors.blue[700], size: 24),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Manage Session (${sessionPlayers.length})',
                            style: TextStyle(fontSize: 18)),
                        Text(gameSessionId,
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text('${sessionPlayers.length} charged players',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              content: Container(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Game Details',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[800])),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          SizedBox(
                            width: 110,
                            child: TextField(
                              controller: baseCostController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Base Cost',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: notesController,
                              decoration: InputDecoration(
                                labelText: 'Notes',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Save details',
                            onPressed: saveGameDetails,
                            icon: Icon(Icons.save, color: Colors.green[700]),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      Text('Add Player',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green[800])),
                      SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: addPlayerUsername,
                        decoration: InputDecoration(
                          labelText: 'Player',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: availablePlayers
                            .map(
                              (username) => DropdownMenuItem(
                                value: username,
                                child: Text(username),
                              ),
                            )
                            .toList(),
                        onChanged: availablePlayers.isEmpty
                            ? null
                            : (value) {
                                setState(() {
                                  addPlayerUsername = value;
                                  addPlayerSaveStatus = null;
                                  addPlayerSaved = false;
                                });
                              },
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          SizedBox(
                            width: 110,
                            child: TextField(
                              controller: addCostController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Cost',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: addNoteController,
                              decoration: InputDecoration(
                                labelText: 'Note',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Add player',
                            onPressed:
                                availablePlayers.isEmpty || isAddingPlayer
                                    ? null
                                    : addPlayerToSession,
                            icon: isAddingPlayer
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(Icons.person_add,
                                    color: Colors.green[700]),
                          ),
                        ],
                      ),
                      if (addPlayerSaveStatus != null) ...[
                        SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding:
                              EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: addPlayerSaved
                                ? Colors.green[50]
                                : isAddingPlayer
                                    ? Colors.blue[50]
                                    : Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: addPlayerSaved
                                  ? Colors.green.shade200
                                  : isAddingPlayer
                                      ? Colors.blue.shade200
                                      : Colors.red.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                addPlayerSaved
                                    ? Icons.check_circle
                                    : isAddingPlayer
                                        ? Icons.sync
                                        : Icons.error,
                                color: addPlayerSaved
                                    ? Colors.green[700]
                                    : isAddingPlayer
                                        ? Colors.blue[700]
                                        : Colors.red[700],
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  addPlayerSaveStatus!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: addPlayerSaved
                                        ? Colors.green[800]
                                        : isAddingPlayer
                                            ? Colors.blue[800]
                                            : Colors.red[800],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      SizedBox(height: 16),
                      Text('Players',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blueGrey[800])),
                      SizedBox(height: 8),
                      if (sessionPlayers.isEmpty)
                        Text('No players in this session')
                      else
                        SizedBox(
                          height: 320,
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: sessionPlayers.length,
                            itemBuilder: (ctx, idx) {
                              final player = sessionPlayers[idx];
                              return Card(
                                margin: EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.blue[100],
                                    child: Text(
                                      player['username'][0].toUpperCase(),
                                      style: TextStyle(color: Colors.blue[900]),
                                    ),
                                  ),
                                  title: Text(player['username'],
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Cost: ${player['applied_cost']}₪'),
                                      if (player['adjustment_note'] != null &&
                                          player['adjustment_note']
                                              .toString()
                                              .isNotEmpty)
                                        Text(
                                            'Note: ${player['adjustment_note']}',
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontStyle: FontStyle.italic)),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.edit,
                                            color: Colors.blue[700]),
                                        onPressed: () =>
                                            editSessionPlayer(player, idx),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.delete,
                                            color: Colors.red),
                                        onPressed: () async {
                                          bool? confirm =
                                              await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: Text('Remove Player?'),
                                              content: Text(
                                                  'Remove ${player['username']} from this game session? This will cancel their charge.'),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            ctx, false),
                                                    child: Text('Cancel')),
                                                ElevatedButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx, true),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.red),
                                                  child: Text('Remove'),
                                                ),
                                              ],
                                            ),
                                          );

                                          if (confirm == true) {
                                            try {
                                              final deleteRes =
                                                  await apiService.delete(
                                                      'finance/delete-attendance/${player['attendance_id']}');
                                              if (deleteRes['success']) {
                                                _showSuccess(
                                                    'Player removed from session');
                                                await _invalidateTeamSummaryCache();
                                                setState(() {
                                                  sessionPlayers.removeAt(idx);
                                                });
                                              } else {
                                                _showError(
                                                    deleteRes['message']);
                                              }
                                            } catch (e) {
                                              _showError(
                                                  'Error removing player: $e');
                                            }
                                          }
                                        },
                                      ),
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
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Close'),
                ),
              ],
            );
          },
        ),
      );
    } catch (e) {
      Navigator.of(context).pop(); // Close loading
      if (!mounted) return;
      _showError('Error loading session: $e');
    }
  }

  Future<void> _showPlayerFinancials(Map<String, dynamic> player) async {
    // Show loading first?
    // We will load data inside the dialog or before.
    // Let's load inside a StatefulBuilder in the dialog.

    showDialog(
      context: context,
      builder: (context) => PlayerFinancialDialog(
          username: player['username'], apiService: apiService),
    );
  }

  void _showPendingQueueDialog() async {
    final items = await apiService.getQueueItems();
    final stats = await apiService.getQueueStats();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.cloud_off, color: Colors.orange),
              SizedBox(width: 8),
              Text('Pending Actions (${items.length})'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 48),
                        SizedBox(height: 8),
                        Text('No pending actions',
                            style: TextStyle(fontSize: 16)),
                        Text('All synced!',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final method = item['method'] ?? 'POST';
                      final endpoint = item['endpoint'] ?? '';
                      final createdAt = item['created_at'] ?? '';
                      final attempts = item['attempts'] ?? 0;

                      String description =
                          _getActionDescription(method, endpoint, item['body']);

                      return Card(
                        child: ListTile(
                          leading: Icon(
                            method == 'DELETE'
                                ? Icons.delete
                                : Icons.cloud_upload,
                            color:
                                method == 'DELETE' ? Colors.red : Colors.blue,
                          ),
                          title:
                              Text(description, style: TextStyle(fontSize: 13)),
                          subtitle: Text(
                            'Attempts: $attempts | ${_formatTime(createdAt)}',
                            style: TextStyle(fontSize: 11),
                          ),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () async {
                              await apiService.removeFromQueue(item['id']);
                              final newItems = await apiService.getQueueItems();
                              setDialogState(() => items
                                ..clear()
                                ..addAll(newItems));
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Close'),
            ),
            if (items.isNotEmpty) ...[
              TextButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('Clear All?'),
                      content: Text(
                          'Are you sure you want to delete all ${items.length} pending actions? This cannot be undone.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text('Cancel')),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text('Delete',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await apiService.clearQueue();
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Queue cleared')),
                    );
                  }
                },
                child: Text('Clear All', style: TextStyle(color: Colors.red)),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await apiService.processQueue();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Syncing...')),
                  );
                },
                child: Text('Sync Now'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getActionDescription(String method, String endpoint, dynamic body) {
    final bodyMap = body is Map<String, dynamic> ? body : <String, dynamic>{};
    final amount = bodyMap['amount'];
    final username = bodyMap['username'] ?? bodyMap['player_username'] ?? '';

    if (endpoint.contains('add-payment')) {
      return 'Payment: ${amount != null ? "₪$amount" : ""} ${username.isNotEmpty ? "($username)" : ""}';
    }
    if (endpoint.contains('record-game')) {
      final fee = bodyMap['game_fee'] ?? bodyMap['fee'];
      return 'Game: ${fee != null ? "₪$fee" : ""} ${username.isNotEmpty ? "($username)" : ""}';
    }
    if (endpoint.contains('delete-payment')) {
      return 'Delete Payment ${username.isNotEmpty ? "($username)" : ""}';
    }
    if (endpoint.contains('delete-attendance')) {
      return 'Delete Attendance ${username.isNotEmpty ? "($username)" : ""}';
    }
    if (endpoint.contains('enlist')) {
      return 'Enlist Player ${username.isNotEmpty ? "($username)" : ""}';
    }
    return '$method: $endpoint';
  }

  String _formatTime(String isoString) {
    try {
      final d = DateTime.parse(isoString);
      return '${d.day}/${d.month} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoString;
    }
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (accessDenied) {
      return Scaffold(
        body: Center(
          child: Text('Access Denied',
              style: TextStyle(color: Colors.red, fontSize: 24)),
        ),
      );
    }

    return Scaffold(
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  void _toggleEnlist(String username, bool shouldEnlist) {
    setState(() {
      if (shouldEnlist) {
        if (!selectedUsernames.contains(username)) {
          selectedUsernames.add(username);
        }
      } else {
        selectedUsernames.remove(username);
      }
      _sortPlayersInternal();
    });
  }

  void _cycleRole(String username) {
    setState(() {
      final currentRole = _roleOf(username);
      if (currentRole == 'manager') {
        playerRoles[username] = 'player';
      } else if (currentRole == 'player') {
        playerRoles[username] = 'guest';
      } else {
        playerRoles[username] = 'manager';
      }
      _sortPlayersInternal();
    });
  }

  String _displayName(String username) {
    if (username.length <= 10) return username;
    return username.substring(0, 10);
  }

  void _showFullPlayerName(String username) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Player Name'),
        content: SelectableText(
          username,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerCard(Map<String, dynamic> player) {
    final username = (player['username'] ?? '').toString();
    final isEnlisted = selectedUsernames.contains(username);
    final role = _roleOf(username);
    final isManager = role == 'manager';
    final isGuest = role == 'guest';
    final roleLabel = isManager
        ? 'Manager'
        : isGuest
            ? 'Guest'
            : 'Player';
    final roleIcon = isManager
        ? Icons.emoji_events
        : isGuest
            ? Icons.visibility_outlined
            : Icons.sports_basketball;
    final roleColor = isManager
        ? Colors.amber
        : (isGuest ? Colors.blueGrey : Colors.grey[500]);

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: _playersFromCache
          ? Colors.orange[50]
          : Colors.white.withOpacity(0.95),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Transform.scale(
              scale: 0.82,
              child: Checkbox(
                value: isEnlisted,
                onChanged: (val) => _toggleEnlist(username, val ?? false),
                activeColor: Colors.green,
                visualDensity: VisualDensity.compact,
              ),
            ),
            Expanded(
              child: Tooltip(
                message: username,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _showFullPlayerName(username),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      _displayName(username),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
            Tooltip(
              message: 'Role: $roleLabel (tap to cycle)',
              child: IconButton(
                constraints: BoxConstraints.tightFor(width: 24, height: 24),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  roleIcon,
                  size: 16,
                  color: roleColor,
                ),
                onPressed: () => _cycleRole(username),
              ),
            ),
            IconButton(
              constraints: BoxConstraints.tightFor(width: 24, height: 24),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.account_balance_wallet,
                  size: 16, color: Colors.teal[700]),
              onPressed: () => _showPlayerFinancials(player),
              tooltip: 'Wallet',
            ),
            IconButton(
              constraints: BoxConstraints.tightFor(width: 24, height: 24),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.edit, size: 16, color: Colors.blue),
              onPressed: () => _editPlayer(player),
              tooltip: 'Edit',
            ),
            IconButton(
              constraints: BoxConstraints.tightFor(width: 24, height: 24),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.delete, size: 16, color: Colors.red),
              onPressed: () => _deletePlayer(username),
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayersGrid() {
    final visiblePlayers = _visiblePlayers();
    return LayoutBuilder(
      builder: (context, constraints) {
        const minCardWidth = 235.0;
        int crossAxisCount = (constraints.maxWidth / minCardWidth).floor();
        if (crossAxisCount < 1) crossAxisCount = 1;
        if (crossAxisCount > 6) crossAxisCount = 6;

        return GridView.builder(
          padding: EdgeInsets.all(12),
          itemCount: visiblePlayers.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            mainAxisExtent: 74,
          ),
          itemBuilder: (context, index) {
            final player =
                Map<String, dynamic>.from(visiblePlayers[index] as Map);
            return _buildPlayerCard(player);
          },
        );
      },
    );
  }

  Widget _buildContent() {
    final visibleCount = _visiblePlayers().length;
    final totalCount = players.length;
    final allVisibleSelected = _areAllVisibleSelected();
    String roleFilterLabel;
    switch (_roleFilter) {
      case PlayerRoleFilter.noGuests:
        roleFilterLabel = 'No Guests';
        break;
      case PlayerRoleFilter.guestsOnly:
        roleFilterLabel = 'Guests Only';
        break;
      case PlayerRoleFilter.all:
        roleFilterLabel = 'All Roles';
        break;
    }

    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/reka.webp'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.6), BlendMode.dstATop),
        ),
      ),
      child: Column(
        children: [
          // SINGLE CACHE INDICATOR - only when there are pending items
          FutureBuilder<Map<String, dynamic>>(
            future: apiService.getQueueStats(),
            builder: (context, snapshot) {
              final pending = snapshot.data?['pending'] ?? 0;
              if (pending == 0 && !_isSyncing) return SizedBox.shrink();
              return GestureDetector(
                onTap: _showPendingQueueDialog,
                child: Container(
                  width: double.infinity,
                  color: Colors.orange[50],
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isSyncing) ...[
                        BasketballSpinner(size: 16),
                        SizedBox(width: 8),
                        Text('Syncing...',
                            style: TextStyle(
                                fontSize: 12, color: Colors.blue[800])),
                      ] else ...[
                        Icon(Icons.cloud_off, color: Colors.orange, size: 18),
                        SizedBox(width: 8),
                        Text('$pending pending (tap to view)',
                            style: TextStyle(
                                fontSize: 12, color: Colors.orange[800])),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
          // TOP BAR
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.green[700]?.withOpacity(0.9),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 980;
                final sortButtonLabel = isNarrow ? 'Sort' : _sortLabel();
                final filterButtonLabel = isNarrow ? 'Role' : roleFilterLabel;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20)),
                          child: Text('Playing: ${selectedUsernames.length}',
                              style: TextStyle(
                                  color: Colors.green[800],
                                  fontWeight: FontWeight.bold)),
                        ),
                        Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                              color: Colors.amber[600],
                              borderRadius: BorderRadius.circular(20)),
                          child: Text('Show: $visibleCount/$totalCount',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        PopupMenuButton<PlayerSortMode>(
                          tooltip: 'Sort Players',
                          onSelected: (mode) {
                            setState(() {
                              _sortMode = mode;
                              _sortPlayersInternal();
                            });
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: PlayerSortMode.nameAsc,
                              child: Text('Name A-Z'),
                            ),
                            PopupMenuItem(
                              value: PlayerSortMode.nameDesc,
                              child: Text('Name Z-A'),
                            ),
                            PopupMenuItem(
                              value: PlayerSortMode.enlistedFirst,
                              child: Text('Enlisted First'),
                            ),
                            PopupMenuItem(
                              value: PlayerSortMode.notEnlistedFirst,
                              child: Text('Not Enlisted First'),
                            ),
                            PopupMenuItem(
                              value: PlayerSortMode.managerFirst,
                              child: Text('Managers First'),
                            ),
                            PopupMenuItem(
                              value: PlayerSortMode.guestFirst,
                              child: Text('Guests First'),
                            ),
                          ],
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white54),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.sort, color: Colors.white, size: 18),
                                SizedBox(width: 6),
                                Text(
                                  sortButtonLabel,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(Icons.arrow_drop_down,
                                    color: Colors.white),
                              ],
                            ),
                          ),
                        ),
                        PopupMenuButton<PlayerRoleFilter>(
                          tooltip: 'Role Filter',
                          onSelected: (mode) {
                            setState(() {
                              _roleFilter = mode;
                            });
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: PlayerRoleFilter.all,
                              child: Text('All Roles'),
                            ),
                            PopupMenuItem(
                              value: PlayerRoleFilter.noGuests,
                              child: Text('Hide Guests'),
                            ),
                            PopupMenuItem(
                              value: PlayerRoleFilter.guestsOnly,
                              child: Text('Guests Only'),
                            ),
                          ],
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white54),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.filter_alt_outlined,
                                    color: Colors.white, size: 18),
                                SizedBox(width: 6),
                                Text(
                                  filterButtonLabel,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(Icons.arrow_drop_down,
                                    color: Colors.white),
                              ],
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _toggleSelectAllVisible,
                          icon: Icon(
                            allVisibleSelected
                                ? Icons.deselect_outlined
                                : Icons.select_all,
                          ),
                          label: Text(allVisibleSelected
                              ? 'Deselect All'
                              : 'Select All'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal[700],
                            foregroundColor: Colors.white,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _addPlayer,
                          icon: Icon(Icons.person_add),
                          label: Text('Add Player'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple[700],
                            foregroundColor: Colors.white,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _showSaveGameDialog,
                          icon: Icon(Icons.save_alt),
                          label: Text('Save Game'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[800],
                            foregroundColor: Colors.white,
                          ),
                        ),
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
                );
              },
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(Icons.cloud_off,
                                  color: Colors.orange[700], size: 16),
                              SizedBox(width: 6),
                              Text('Showing cached players (offline)',
                                  style: TextStyle(
                                      color: Colors.orange[700], fontSize: 12)),
                            ],
                          ),
                        ),
                      Expanded(
                        child: _buildPlayersGrid(),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// SEPARATE CLASS FOR FINANCIAL DIALOG
// ==========================================

class PlayerFinancialDialog extends StatefulWidget {
  final String username;
  final ApiService apiService;

  const PlayerFinancialDialog(
      {required this.username, required this.apiService});

  @override
  _PlayerFinancialDialogState createState() => _PlayerFinancialDialogState();
}

class _PlayerFinancialDialogState extends State<PlayerFinancialDialog> {
  bool loading = true;
  bool _isRefreshingData = false;
  Map<String, dynamic>? data;
  String errorMessage = '';
  bool fromCache = false;
  int pendingQueue = 0;
  int failedQueue = 0;
  int lastSyncedCount = 0;
  String? lastSyncedAt;
  String? lastServerRefreshAt;
  bool _isSyncing = false;
  StreamSubscription<bool>? _syncSub;
  IO.Socket? _socket;
  Timer? _liveRefreshTimer;
  int? _teamId;
  DateTime? _lastLiveRefreshAt;
  static int _paymentSequence = 0;
  static const String _lastPaymentDebugKeyPrefix = 'last_payment_debug_';
  bool _isSubmittingPayment = false;
  String? _lastPaymentStatus;
  String? _lastPaymentTraceId;
  String? _lastPaymentEmailStatus;
  String? _lastPaymentMessage;
  String? _lastPaymentAtIso;

  // Filter State: 'all', 'games', 'payments'
  String _filter = 'all';

  // For Adding Payment
  final amountController = TextEditingController();
  final notesController = TextEditingController();
  String paymentMethod = 'bit'; // Default

  @override
  void initState() {
    super.initState();
    _startSyncListener();
    _loadLastPaymentDebug();
    _initLiveUpdates();
    _fetchData();
  }

  String get _lastPaymentDebugKey =>
      '$_lastPaymentDebugKeyPrefix${widget.username}';

  Future<void> _persistLastPaymentDebug({
    required String status,
    required String message,
    bool? queued,
    String? traceId,
    String? emailStatus,
  }) async {
    final payload = <String, dynamic>{
      'status': status,
      'message': message,
      'queued': queued,
      'trace_id': traceId,
      'email_status': emailStatus,
      'updated_at': DateTime.now().toIso8601String(),
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastPaymentDebugKey, jsonEncode(payload));
    if (!mounted) return;
    setState(() {
      _lastPaymentStatus = status;
      _lastPaymentMessage = message;
      _lastPaymentTraceId = traceId;
      _lastPaymentEmailStatus = emailStatus;
      _lastPaymentAtIso = payload['updated_at'] as String;
    });
  }

  Future<void> _loadLastPaymentDebug() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastPaymentDebugKey);
      if (raw == null || raw.isEmpty) return;
      final parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) return;
      if (!mounted) return;
      setState(() {
        _lastPaymentStatus = parsed['status'] as String?;
        _lastPaymentMessage = parsed['message'] as String?;
        _lastPaymentTraceId = parsed['trace_id'] as String?;
        _lastPaymentEmailStatus = parsed['email_status'] as String?;
        _lastPaymentAtIso = parsed['updated_at'] as String?;
      });
    } catch (_) {
      // Keep UI stable even if debug payload is malformed.
    }
  }

  void _startSyncListener() {
    _syncSub = widget.apiService.isSyncing.listen((isSyncing) {
      if (!mounted) return;
      setState(() {
        _isSyncing = isSyncing;
      });
      if (!isSyncing) {
        _loadQueueStats();
        _fetchData(preferCache: false, keepDialogVisible: true);
      }
    });
  }

  Future<void> _initLiveUpdates() async {
    final prefs = await SharedPreferences.getInstance();
    _teamId = prefs.getInt('team_id');
    _startRealtimeListener();
    _startPeriodicRefresh();
  }

  void _startRealtimeListener() {
    final teamId = _teamId;
    if (teamId == null) return;

    _socket?.dispose();
    final socket = IO.io(widget.apiService.apiUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    _socket = socket;

    socket.on('connect', (_) {
      socket.emit('joinTeam', {'team_id': teamId});
    });

    socket.on('financeSummaryUpdated', (payload) {
      if (!_belongsToMyTeam(payload)) return;
      _handleRealtimeUpdate();
    });

    socket.connect();
  }

  bool _belongsToMyTeam(dynamic payload) {
    final teamId = _teamId;
    if (teamId == null) return true;
    if (payload is Map) {
      final raw = payload['team_id'];
      if (raw is int) return raw == teamId;
      if (raw is String) return int.tryParse(raw) == teamId;
    }
    return true;
  }

  void _startPeriodicRefresh() {
    _liveRefreshTimer?.cancel();
    _liveRefreshTimer = Timer.periodic(const Duration(seconds: 35), (_) {
      _handleRealtimeUpdate();
    });
  }

  Future<void> _handleRealtimeUpdate() async {
    if (!mounted) return;
    final now = DateTime.now();
    if (_lastLiveRefreshAt != null &&
        now.difference(_lastLiveRefreshAt!) < const Duration(seconds: 1)) {
      return;
    }
    _lastLiveRefreshAt = now;
    await _fetchData(preferCache: false, keepDialogVisible: true);
  }

  Future<void> _fetchData(
      {bool preferCache = true, bool keepDialogVisible = false}) async {
    final hasCurrentData = data != null;
    final shouldKeepVisible = keepDialogVisible || hasCurrentData;
    setState(() {
      if (shouldKeepVisible) {
        _isRefreshingData = true;
      } else {
        loading = true;
      }
      errorMessage = '';
    });

    final cacheKey = 'cache_player_financials_${widget.username}';
    if (preferCache) {
      final cached = await widget.apiService.getFromCacheOnly(cacheKey);
      if (cached != null && cached['success'] == true && mounted) {
        setState(() {
          data = cached;
          fromCache = true;
          lastServerRefreshAt = cached['_cache_updated_at'] as String?;
          if (!shouldKeepVisible) {
            loading = false;
          }
        });
      }
    }

    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final response = await widget.apiService.getWithCache(
          'finance/player-financials/${widget.username}?ts=$ts',
          cacheKey: cacheKey);
      if (response['success'] == true) {
        setState(() {
          data = response;
          fromCache = response['_cached'] == true;
          lastServerRefreshAt = response['_cache_updated_at'] as String?;
        });
      } else {
        if (data == null) {
          setState(() {
            errorMessage = response['message'];
          });
        }
      }
    } catch (e) {
      if (data == null) {
        setState(() {
          errorMessage = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          _isRefreshingData = false;
        });
      }
    }
    _loadQueueStats();
  }

  Future<void> _loadQueueStats() async {
    try {
      final stats = await widget.apiService.getQueueStats();
      setState(() {
        pendingQueue = stats['pending'] ?? 0;
        failedQueue = stats['failed'] ?? 0;
        lastSyncedCount = stats['last_synced_count'] ?? 0;
        lastSyncedAt = stats['last_synced_at'] as String?;
      });
    } catch (_) {}
  }

  String _generateClientPaymentId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final seq = _paymentSequence++;
    return '${widget.username}_${ts}_$seq';
  }

  Future<void> _addPayment() async {
    if (amountController.text.isEmpty || _isSubmittingPayment) return;
    setState(() => _isSubmittingPayment = true);
    try {
      final paymentPayload = {
        'username': widget.username,
        'client_payment_id': _generateClientPaymentId(),
        'amount': int.tryParse(amountController.text) ?? 0,
        'method': paymentMethod,
        'notes': notesController.text,
      };
      debugPrint(
        '[payment:add] sending payload for ${widget.username}: $paymentPayload',
      );
      final response = await widget.apiService
          .postQueued('finance/add-payment', paymentPayload);
      debugPrint('[payment:add] response for ${widget.username}: $response');
      if (response['success'] == true) {
        amountController.clear();
        notesController.clear();
        final queued = response['queued'] == true;
        final emailStatus = response['email_status'] as String?;
        String emailHint = '';
        if (!queued) {
          await _fetchData(preferCache: false, keepDialogVisible: true);
        } else {
          await _loadQueueStats();
        }
        if (!queued) {
          if (emailStatus == 'sent') {
            emailHint = ' | confirmation email sent';
          } else if (emailStatus == 'skipped') {
            emailHint = ' | no email sent (missing player email / SMTP)';
          } else if (emailStatus == 'failed') {
            emailHint = ' | email send failed';
          }
        }
        final traceId = response['trace_id']?.toString();
        await _persistLastPaymentDebug(
          status: queued ? 'queued' : 'success',
          message: queued
              ? 'Saved offline, waiting for sync'
              : 'Payment saved in database',
          queued: queued,
          traceId: traceId,
          emailStatus: emailStatus,
        );
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(queued
                ? 'Payment saved offline, will sync later'
                : 'Payment saved in database!$emailHint'),
            backgroundColor: queued ? Colors.orange : Colors.green));
      } else {
        final traceId = response['trace_id']?.toString();
        final failureMessage =
            response['message']?.toString() ?? 'Payment failed';
        await _persistLastPaymentDebug(
          status: 'failed',
          message: failureMessage,
          queued: false,
          traceId: traceId,
          emailStatus: response['email_status']?.toString(),
        );
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(response['message'] ?? 'Failed'),
            backgroundColor: Colors.red));
      }
    } catch (e) {
      await _persistLastPaymentDebug(
        status: 'error',
        message: e.toString(),
        queued: false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSubmittingPayment = false);
    }
  }

  Future<void> _deleteInfo(String type, int id) async {
    // Confirm
    bool? confirm = await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text('Delete Record?'),
                content: Text(
                    'Are you sure you want to delete this $type? This affects the balance.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('Cancel')),
                  ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text('Delete'),
                      style:
                          ElevatedButton.styleFrom(backgroundColor: Colors.red))
                ]));

    if (confirm != true) return;

    try {
      String endpoint = type == 'payment'
          ? 'finance/delete-payment/$id'
          : 'finance/delete-attendance/$id';

      final response = await widget.apiService.deleteQueued(endpoint);

      if (response['success'] == true) {
        final queued = response['queued'] == true;
        if (!queued) {
          await _fetchData(preferCache: false, keepDialogVisible: true);
        } else {
          await _loadQueueStats();
        }
        if (queued) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Deletion queued (offline)'),
              backgroundColor: Colors.orange));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response['message'] ?? 'Failed')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  String _formatDate(String isoString) {
    try {
      DateTime d = DateTime.parse(isoString);
      List<String> days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return "${days[d.weekday - 1]}, ${d.day}/${d.month}/${d.year}";
    } catch (e) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading && data == null)
      return AlertDialog(
          content: SizedBox(
              height: 100, child: Center(child: CircularProgressIndicator())));
    if (errorMessage.isNotEmpty && data == null)
      return AlertDialog(content: Text('Error: $errorMessage'), actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text('Close'))
      ]);

    final financialData = data!;
    final balance = financialData['balance'] ?? 0;
    // history is an object { games: [...], payments: [...] }
    final historyObj = financialData['history'] as Map<String, dynamic>? ?? {};
    final history = historyObj['games'] as List<dynamic>? ?? [];
    final payments = historyObj['payments'] as List<dynamic>? ?? [];

    // Combine for 'all' or filtered
    List<Map<String, dynamic>> displayedList = [];

    if (_filter == 'all' || _filter == 'games') {
      for (var g in history) {
        displayedList.add({
          'type': 'game',
          'date': g['date'],
          'amount': -1 * ((g['applied_cost'] as num?) ?? 0),
          'desc': 'Game (${g['notes'] ?? ''})',
          'id': g['attendance_id'] // Ensure ID available
        });
      }
    }
    if (_filter == 'all' || _filter == 'payments') {
      for (var p in payments) {
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
    displayedList.sort((a, b) =>
        DateTime.parse(b['date']).compareTo(DateTime.parse(a['date'])));

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(
          children: [
            Text('${widget.username} Wallet'),
            if (_isRefreshingData) ...[
              SizedBox(width: 8),
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: balance >= 0 ? Colors.green[100] : Colors.red[100],
                borderRadius: BorderRadius.circular(20)),
            child: Text('${balance >= 0 ? '+' : ''}$balance ₪',
                style: TextStyle(
                    color: balance >= 0 ? Colors.green[800] : Colors.red[800],
                    fontWeight: FontWeight.bold)))
      ]),
      content: Container(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (fromCache)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text('Showing cached data (offline)',
                    style: TextStyle(color: Colors.orange[700], fontSize: 12)),
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
                    ? Center(
                        child: Text('No history found',
                            style: TextStyle(color: Colors.grey)))
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
                                isPayment
                                    ? Icons.payment
                                    : Icons.sports_basketball,
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
                                          color: item['amount'] >= 0
                                              ? Colors.green
                                              : Colors.red,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  SizedBox(width: 8),
                                  // DELETE BUTTON
                                  IconButton(
                                    icon: Icon(Icons.delete_outline,
                                        size: 20, color: Colors.grey),
                                    onPressed: () =>
                                        _deleteInfo(item['type'], item['id']),
                                  )
                                ],
                              ),
                            ),
                          );
                        })),

            Divider(),

            // ADD PAYMENT
            ExpansionTile(
              title: Text('Add Payment',
                  style: TextStyle(
                      color: Colors.blue[800], fontWeight: FontWeight.bold)),
              children: [
                Padding(
                  padding: EdgeInsets.all(8),
                  child: Column(
                    children: [
                      Row(children: [
                        Expanded(
                            child: TextField(
                                controller: amountController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                    labelText: 'Amount',
                                    prefixIcon: Icon(Icons.attach_money)))),
                        SizedBox(width: 8),
                        DropdownButton<String>(
                            value: paymentMethod,
                            items: ['bit', 'cash', 'paybox', 'other']
                                .map((e) => DropdownMenuItem(
                                    value: e, child: Text(e.toUpperCase())))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => paymentMethod = v!))
                      ]),
                      TextField(
                          controller: notesController,
                          decoration:
                              InputDecoration(labelText: 'Notes (Optional)')),
                      SizedBox(height: 8),
                      ElevatedButton(
                          onPressed: _isSubmittingPayment ? null : _addPayment,
                          child: _isSubmittingPayment
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text('Saving Payment...'),
                                  ],
                                )
                              : Text('Submit Payment'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[800])),
                      if (_lastPaymentStatus != null) ...[
                        SizedBox(height: 10),
                        _buildLastPaymentDebugCard(),
                      ],
                    ],
                  ),
                )
              ],
            )
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text('Close'))
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
              border: active ? Border.all(color: Colors.blue) : null),
          child: Text(label,
              style: TextStyle(
                  color: active ? Colors.blue[800] : Colors.black87,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal))),
    );
  }

  Widget _buildQueueInfo() {
    final queueInfo = lastSyncedAt != null
        ? 'Queue synced: $lastSyncedCount at ${_fmtDateTime(lastSyncedAt)}'
        : 'Queue not synced yet';
    final serverInfo = lastServerRefreshAt != null
        ? 'Server data updated: ${_fmtDateTime(lastServerRefreshAt)}'
        : 'Server data not loaded yet';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_isSyncing) ...[
                BasketballSpinner(size: 14),
                SizedBox(width: 6),
              ],
              Text(
                'Queue: $pendingQueue pending${failedQueue > 0 ? " | $failedQueue failed" : ""}',
                style: TextStyle(fontSize: 12, color: Colors.grey[800]),
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            queueInfo,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          SizedBox(height: 2),
          Text(
            serverInfo,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  String _fmtDateTime(String? iso) {
    if (iso == null) return '';
    try {
      final d = DateTime.parse(iso);
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
    } catch (_) {
      return iso;
    }
  }

  Widget _buildLastPaymentDebugCard() {
    Color color;
    if (_lastPaymentStatus == 'success') {
      color = Colors.green[700]!;
    } else if (_lastPaymentStatus == 'queued') {
      color = Colors.orange[700]!;
    } else {
      color = Colors.red[700]!;
    }

    final emailText = _lastPaymentEmailStatus != null
        ? 'Email: $_lastPaymentEmailStatus'
        : 'Email: n/a';
    final traceText = _lastPaymentTraceId != null
        ? 'Trace: $_lastPaymentTraceId'
        : 'Trace: n/a';
    final atText = _fmtDateTime(_lastPaymentAtIso);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Last Payment Attempt: ${_lastPaymentStatus?.toUpperCase()}',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 4),
          Text(_lastPaymentMessage ?? '', style: TextStyle(fontSize: 12)),
          SizedBox(height: 2),
          Text(emailText, style: TextStyle(fontSize: 12)),
          SizedBox(height: 2),
          Text(traceText, style: TextStyle(fontSize: 12)),
          if (atText.isNotEmpty) ...[
            SizedBox(height: 2),
            Text('Updated: $atText', style: TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _liveRefreshTimer?.cancel();
    if (_teamId != null) {
      _socket?.emit('leaveTeam', {'team_id': _teamId});
    }
    _socket?.dispose();
    amountController.dispose();
    notesController.dispose();
    super.dispose();
  }
}
