// lib/pages/management_page.dart

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Define keys for SharedPreferences
const String kUserKey = 'user';
const String kEnlistedPlayersKey = 'enlistedPlayers';

class UsernameSelection {
  String username;
  bool isEnlisted;

  UsernameSelection({required this.username, required this.isEnlisted});
}

class ManagementPage extends StatefulWidget {
  @override
  _ManagementPageState createState() => _ManagementPageState();
}

class _ManagementPageState extends State<ManagementPage> {
  List<UsernameSelection> usernameSelections = [];
  Map<String, bool> initialSelections = {};
  bool isTierMethod = false;
  String? user;
  bool accessDenied = false;
  bool _isAscending = true;

  // List to track the order of selected usernames
  List<String> selectedUsernames = [];

  final TextEditingController _newUsernameController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _newEmailController = TextEditingController();
  bool _isSubmittingNewPlayer = false;
  String? _newPlayerError;
  bool _isLoadingTeamDetails = false;
  String? _managedTeamName;
  String? _managedTeamPassword;
  String? _teamDetailsError;

  @override
  void initState() {
    super.initState();
    fetchUserAndData();
  }

  void fetchUserAndData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    user = prefs.getString(kUserKey);

    if (user != 'doron' && user != 'dor') {
      setState(() {
        accessDenied = true;
      });
      return;
    }

    await Future.wait([
      fetchData(),
      _fetchManagedTeamDetails(),
    ]);
    await _loadEnlistedPlayers(); // Load enlisted players from SharedPreferences
  }

  Future<void> _saveEnlistedPlayers(List<String> players) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(kEnlistedPlayersKey, players);
  }

  Future<void> _loadEnlistedPlayers() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> savedPlayers = prefs.getStringList(kEnlistedPlayersKey) ?? [];
    if (usernameSelections.isEmpty) {
      setState(() {
        selectedUsernames = savedPlayers;
      });
    } else {
      _applySelectionState(savedPlayers, updateInitial: true);
    }
  }

  void _applySelectionState(List<String> enlisted,
      {bool updateInitial = false}) {
    setState(() {
      _applySelectionStateNoSet(enlisted, updateInitial: updateInitial);
    });
  }

  void _applySelectionStateNoSet(List<String> enlisted,
      {bool updateInitial = false}) {
    selectedUsernames = List<String>.from(enlisted);
    for (var selection in usernameSelections) {
      selection.isEnlisted = enlisted.contains(selection.username);
    }
    if (updateInitial) {
      initialSelections = {
        for (var selection in usernameSelections)
          selection.username: selection.isEnlisted
      };
    }
  }

  Future<void> _fetchManagedTeamDetails() async {
    if (user == null) return;

    setState(() {
      _isLoadingTeamDetails = true;
      _teamDetailsError = null;
    });

    String? resolvedName;
    String? resolvedPassword;
    String? resolvedError;

    try {
      ApiService apiService = ApiService();
      final teamsResponse = await apiService.get('teams');

      if (teamsResponse['success'] == true && teamsResponse['teams'] is List) {
        final teams = teamsResponse['teams'] as List;
        Map<String, dynamic>? matchedTeam;

        for (final entry in teams) {
          if (entry is Map<String, dynamic>) {
            final managerCandidates = <String>{
              if (entry['manager'] != null)
                entry['manager'].toString().toLowerCase(),
              if (entry['manager_name'] != null)
                entry['manager_name'].toString().toLowerCase(),
              if (entry['manager_username'] != null)
                entry['manager_username'].toString().toLowerCase(),
            }..removeWhere((element) => element.isEmpty);

            if (managerCandidates.contains(user!.toLowerCase())) {
              matchedTeam = entry;
              break;
            }
          }
        }

        if (matchedTeam == null) {
          final fallbackTeam = teams
              .whereType<Map<String, dynamic>>()
              .firstWhere(
                (team) => team['team_name'] != null &&
                    team['team_name'].toString().isNotEmpty,
                orElse: () => <String, dynamic>{},
              );
          if (fallbackTeam.isNotEmpty) {
            matchedTeam = fallbackTeam;
          }
        }

        if (matchedTeam != null) {
          resolvedName = matchedTeam['team_name']?.toString();
          resolvedPassword = matchedTeam['team_password']?.toString();
        } else {
          resolvedError = 'No team details available.';
        }
      } else {
        resolvedError = 'Failed to load teams.';
      }
    } catch (e) {
      resolvedError = 'Error fetching teams: $e';
    }

    if (!mounted) return;
    setState(() {
      _isLoadingTeamDetails = false;
      _managedTeamName = resolvedName;
      _managedTeamPassword = resolvedPassword;
      _teamDetailsError = resolvedError;
    });
  }

  void _resetNewPlayerForm() {
    _newUsernameController.clear();
    _newPasswordController.clear();
    _newEmailController.clear();
    _newPlayerError = null;
  }

  void _openAddPlayerDialog() {
    if (_isLoadingTeamDetails) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loading team details. Please try again shortly.')),
      );
      return;
    }

    if (_managedTeamName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _teamDetailsError ?? 'Unable to determine the managed team.',
          ),
        ),
      );
      return;
    }

    _resetNewPlayerForm();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Add New Player'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.group,
                            color: Colors.blueGrey[700],
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _managedTeamName ?? '',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    TextField(
                      controller: _newUsernameController,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        icon: Icon(Icons.person),
                      ),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: _newPasswordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        icon: Icon(Icons.lock),
                      ),
                      obscureText: true,
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: _newEmailController,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        icon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    SizedBox(height: 12),
                    if (_newPlayerError != null) ...[
                      SizedBox(height: 12),
                      Text(
                        _newPlayerError!,
                        style: TextStyle(color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.lightGreen,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isSubmittingNewPlayer
                      ? null
                      : () => _submitNewPlayer(
                            dialogContext,
                            setDialogState,
                          ),
                  child: _isSubmittingNewPlayer
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('Adding...'),
                          ],
                        )
                      : Text('Add Player'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitNewPlayer(
    BuildContext dialogContext,
    void Function(VoidCallback) dialogSetState,
  ) async {
    if (_newUsernameController.text.trim().isEmpty ||
        _newPasswordController.text.isEmpty ||
        _newEmailController.text.trim().isEmpty) {
      setState(() {
        _newPlayerError = 'Please fill in all fields.';
      });
      dialogSetState(() {});
      return;
    }

    if (_managedTeamName == null) {
      setState(() {
        _newPlayerError = 'Unable to resolve the managed team.';
      });
      dialogSetState(() {});
      return;
    }

    setState(() {
      _isSubmittingNewPlayer = true;
      _newPlayerError = null;
    });
    dialogSetState(() {});

    bool dialogClosed = false;

    try {
      ApiService apiService = ApiService();
      final preservedSelections = List<String>.from(selectedUsernames);

      final Map<String, dynamic> payload = {
        'username': _newUsernameController.text.trim(),
        'password': _newPasswordController.text,
        'email': _newEmailController.text.trim(),
        'teamName': _managedTeamName,
      };

      if (_managedTeamPassword != null &&
          _managedTeamPassword!.trim().isNotEmpty) {
        payload['teamPassword'] = _managedTeamPassword;
      }

      final response = await apiService.post('register', payload);

      if (response['success'] == true) {
        Navigator.of(dialogContext).pop();
        dialogClosed = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Player added successfully!')),
        );
        await fetchData(preservedSelectionOrder: preservedSelections);
        _resetNewPlayerForm();
      } else {
        setState(() {
          _newPlayerError =
              response['message'] ?? 'Failed to add player. Please try again.';
        });
        dialogSetState(() {});
      }
    } catch (e) {
      setState(() {
        _newPlayerError = 'Error adding player: $e';
      });
      if (!dialogClosed) {
        dialogSetState(() {});
      }
    } finally {
      if (!mounted) return;
      setState(() {
        _isSubmittingNewPlayer = false;
      });
      if (!dialogClosed) {
        dialogSetState(() {});
      }
    }
  }

  Future<void> fetchData({List<String>? preservedSelectionOrder}) async {
    try {
      ApiService apiService = ApiService();
      final usernamesResponse = await apiService.get('usernames');

      if (usernamesResponse['success']) {
        List<dynamic> usernamesList = usernamesResponse['usernames'];
        List<String> usernamesData = List<String>.from(usernamesList);

        List<UsernameSelection> selections = usernamesData.map((username) {
          return UsernameSelection(username: username, isEnlisted: false);
        }).toList();

        final availableUsernames = usernamesData.toSet();
        final preserved = (preservedSelectionOrder ?? selectedUsernames)
            .where((username) => availableUsernames.contains(username))
            .toList();

        setState(() {
          usernameSelections = selections;
          _sortSelections();
          _applySelectionStateNoSet(preserved, updateInitial: true);
        });
      } else {
        // Handle error
        print('Failed to fetch usernames');
      }
    } catch (e) {
      print('Error fetching data: $e');
    }
  }

  @override
  void dispose() {
    _newUsernameController.dispose();
    _newPasswordController.dispose();
    _newEmailController.dispose();
    super.dispose();
  }

  // Helper function to split the list into chunks of specified size
  List<List<UsernameSelection>> splitList(
      List<UsernameSelection> list, int chunkSize) {
    List<List<UsernameSelection>> chunks = [];
    for (var i = 0; i < list.length; i += chunkSize) {
      chunks.add(
        list.sublist(
          i,
          i + chunkSize > list.length ? list.length : i + chunkSize,
        ),
      );
    }
    return chunks;
  }

  int currentPlayingCount() {
    return selectedUsernames.length;
  }

  void _sortSelections() {
    usernameSelections.sort((a, b) {
      final first = a.username.toLowerCase();
      final second = b.username.toLowerCase();
      return _isAscending ? first.compareTo(second) : second.compareTo(first);
    });
  }

  void _toggleSortOrder() {
    setState(() {
      _isAscending = !_isAscending;
      _sortSelections();
    });
  }

  Future<void> handleEnlistUsers() async {
    try {
      ApiService apiService = ApiService();

      List<String> usernamesToEnlist = [];
      List<String> usernamesToUnenlist = [];

      // Determine which users to enlist and unenlist based on changes
      usernameSelections.forEach((selection) {
        bool initial = initialSelections[selection.username] ?? false;
        bool current = selection.isEnlisted;
        if (current != initial) {
          if (current) {
            usernamesToEnlist.add(selection.username);
          } else {
            usernamesToUnenlist.add(selection.username);
          }
        }
      });

      // Reorder usernamesToEnlist based on selectedUsernames to preserve selection order
      usernamesToEnlist.sort((a, b) => selectedUsernames.indexOf(a).compareTo(selectedUsernames.indexOf(b)));

      if (usernamesToEnlist.isNotEmpty || usernamesToUnenlist.isNotEmpty) {
        if (usernamesToEnlist.isNotEmpty) {
          await apiService.post('enlist-users', {
            'usernames': usernamesToEnlist,
            'isTierMethod': isTierMethod,
          });
        }

        if (usernamesToUnenlist.isNotEmpty) {
          await apiService.post('delete-enlist', {
            'usernames': usernamesToUnenlist,
            'isTierMethod': isTierMethod,
          });
        }
      } else {
        // If no changes, still call delete-enlist with isTierMethod
        await apiService.post('delete-enlist', {
          'isTierMethod': isTierMethod,
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Users updated successfully!')),
      );

      // Update initialSelections to reflect current state
      setState(() {
        // Update initialSelections to reflect current state
        usernamesToEnlist.forEach((username) {
          initialSelections[username] = true;
        });
        usernamesToUnenlist.forEach((username) {
          initialSelections[username] = false;
        });
        // We do not overwrite selectedUsernames here
      });

      // Save the updated enlisted players to SharedPreferences
      await _saveEnlistedPlayers(selectedUsernames);
    } catch (e) {
      print('Error updating users: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating users')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (accessDenied) {
      return Scaffold(
        body: Center(
          child: Text(
            'Access Denied!',
            style: TextStyle(
              fontSize: 24,
              color: Colors.red,
            ),
          ),
        ),
      );
    }

    return Scaffold(

      body: Container(
        // Background image
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/bb3d.png'), // Ensure the image exists
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.6),
              BlendMode.dstATop,
            ),
          ),
        ),
        width: double.infinity,
        height: double.infinity,
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Use Tier Method Checkbox
                // (Uncomment and implement as needed)
                /*
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Checkbox(
                      value: isTierMethod,
                      onChanged: (bool? value) {
                        setState(() {
                          isTierMethod = value ?? false;
                        });
                      },
                    ),
                    Text('Tier Method'),
                  ],
                ),
                */
                SizedBox(height: 16.0),
                // Display current playing count
                Container(
                  padding: EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Playing now: ${currentPlayingCount()}',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
                SizedBox(height: 16.0),
                if (_managedTeamName != null)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.group,
                          color: Colors.blueGrey[700],
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Managing team: $_managedTeamName',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.blueGrey[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_managedTeamName != null) SizedBox(height: 16.0),
                if (_isLoadingTeamDetails)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: CircularProgressIndicator(),
                  )
                else if (_teamDetailsError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      _teamDetailsError!,
                      style: TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ElevatedButton.icon(
                  onPressed: (!_isLoadingTeamDetails && _managedTeamName != null)
                      ? _openAddPlayerDialog
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
                    textStyle: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: Icon(Icons.person_add),
                  label: Text('Add New Player'),
                ),
                SizedBox(height: 16.0),
                ElevatedButton(
                  onPressed: handleEnlistUsers,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.lightGreen, // Button color
                    foregroundColor: Colors.white, // Text color
                    padding:
                    EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
                    textStyle: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text('Update Players'),
                ),
                SizedBox(height: 16.0),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      _toggleSortOrder();
                    },
                    icon: Icon(
                      Icons.swap_vert,
                      color: Colors.green[700],
                      size: 24,
                    ),
                    label: Text(
                      _isAscending ? 'Sort A→Z' : 'Sort Z→A',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[700],
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                ),
                SizedBox(height: 16.0),
                // List of Users with Customized Checkboxes in Multiple Columns
                Container(
                  constraints: BoxConstraints(
                    maxHeight: 500, // Adjust as needed
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: usernameSelections.isEmpty
                      ? Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:
                      splitList(usernameSelections, 8).map((chunk) {
                        return Padding(
                          padding:
                          EdgeInsets.symmetric(horizontal: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: chunk.map((selection) {
                              // Determine the index of the user in selectedUsernames
                              int selectedIndex = selectedUsernames
                                  .indexOf(selection.username) +
                                  1; // 1-based index
                              bool isBeyondLimit = selectedIndex > 12;

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4.0, horizontal: 8.0),
                                child: Row(
                                  children: [
                                    // Customized Circular Checkbox
                                    Transform.scale(
                                      scale: 1.2, // Increase the size
                                      child: Checkbox(
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                            BorderRadius.circular(
                                                50)),
                                        value: selection.isEnlisted,
                                        checkColor: Colors.white,
                                        activeColor: (selection.isEnlisted &&
                                            isBeyondLimit)
                                            ? Colors.orange
                                            : Colors.lightGreen,
                                        onChanged: (bool? value) {
                                          setState(() {
                                            selection.isEnlisted =
                                                value ?? false;
                                            if (selection.isEnlisted) {
                                              // Add to selectedUsernames if not already present
                                              if (!selectedUsernames
                                                  .contains(
                                                  selection.username)) {
                                                selectedUsernames
                                                    .add(
                                                    selection.username);
                                              }
                                            } else {
                                              // Remove from selectedUsernames
                                              selectedUsernames
                                                  .remove(
                                                  selection.username);
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    // Username Text
                                    Text(
                                      selection.username,
                                      style: TextStyle(fontSize: 16),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
