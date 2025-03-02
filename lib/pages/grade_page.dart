// lib/screens/grade_page.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import 'legend_page.dart';
import '../services/rankings_service.dart';
import '../config/legend_config.dart';

class GradePage extends StatefulWidget {
  @override
  _GradePageState createState() => _GradePageState();
}

class _GradePageState extends State<GradePage> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> grading = [];
  String? user;

  // To track the currently frozen player
  String? _frozenPlayerUsername;

  // OverlayEntry for floating buttons
  OverlayEntry? _floatingButtonsOverlay;

  String? _selectedGradeButtonUsername;
  String? _selectedGradeButtonField;

  // Variable to track sorting order
  bool _isAscending = false; // Initial sorting is descending
  String _sport = 'basketball'; // ערך ברירת מחדל

  @override
  void initState() {
    super.initState();
    fetchInitialData();
  }

  @override
  void dispose() {
    _removeFloatingButtons(resetSelection: false); // Prevent setState() during dispose
    super.dispose();
  }

  Future<void> fetchInitialData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    user = prefs.getString('user');
    _sport = prefs.getString('sport') ?? 'basketball';

    if (user == null) {
      // Navigate to login page if user is not logged in
      Navigator.pushReplacementNamed(context, '/login');
    } else {
      try {
        // Fetch all usernames
        final usernamesResponse = await _apiService.get('usernames');

        // Fetch all rankings given by the logged-in user
        final rankingsResponse = await _apiService.get('rankings/$user');

        if (usernamesResponse['success'] && rankingsResponse['success']) {
          // Convert the rankings into a map for easy access
          Map<String, dynamic> rankingsByUser = {};
          for (var ranking in rankingsResponse['rankings']) {
            rankingsByUser[ranking['rated_username']] = ranking;
          }

          // Prepare the initial grading data, considering all the usernames
          List<Map<String, dynamic>> initialGrading = [];
          for (var username in usernamesResponse['usernames']) {
            // Only "doron" can see players starting with "joker"
            if (username.startsWith('joker') && user != 'doron') {
              continue;
            }

            // Allow self-ranking only for "doron" or "Moshe"
            if ((username == 'doron' || username == 'Moshe') && user == username) {
              // Allow ranking themselves
            } else if (username == user) {
              // Other users cannot rank themselves
              continue;
            }

            if (rankingsByUser.containsKey(username)) {
              // If ranking exists, use it (UPDATED: using new keys param1...param6)
              initialGrading.add({
                'username': username,
                'param1': rankingsByUser[username]['param1'] ?? 0,
                'param2': rankingsByUser[username]['param2'] ?? 0,
                'param3': rankingsByUser[username]['param3'] ?? 0,
                'param4': rankingsByUser[username]['param4'] ?? 0,
                'param5': rankingsByUser[username]['param5'] ?? 0,
                'param6': rankingsByUser[username]['param6'] ?? 0,
              });
            } else {
              // Initialize with default values (using new keys)
              initialGrading.add({
                'username': username,
                'param1': 0,
                'param2': 0,
                'param3': 0,
                'param4': 0,
                'param5': 0,
                'param6': 0,
              });
            }
          }

          // Compute average for each player (UPDATED: using new keys)
          for (var player in initialGrading) {
            double sum = 0;
            int count = 0;
            List<String> fields = [
              'param1',
              'param2',
              'param3',
              'param4',
              'param5',
              'param6'
            ];
            for (var field in fields) {
              int grade = player[field];
              if (grade != null && grade > 0) {
                sum += grade;
                count += 1;
              }
            }
            double average = 0.0;
            if (count > 0) {
              average = sum / count;
            }
            player['average'] = average;
          }

          // Sort the initialGrading list according to average (descending by default)
          if (!_isAscending) {
            initialGrading.sort((a, b) => b['average'].compareTo(a['average']));
          } else {
            initialGrading.sort((a, b) => a['average'].compareTo(b['average']));
          }

          setState(() {
            grading = initialGrading;
          });
        }
      } catch (error) {
        print('Error fetching data: $error');
        // Optionally, show an error message to the user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching data. Please try again later.')),
        );
      }
    }
  }

  Future<void> submitGrading() async {
    try {
      // Lists to hold valid and invalid player grades
      List<Map<String, dynamic>> validGrading = [];
      List<String> invalidPlayers = [];

      // Define the grading fields using new keys
      List<String> fields = [
        'param1',
        'param2',
        'param3',
        'param4',
        'param5',
        'param6'
      ];

      // Iterate through each player to categorize them
      for (var player in grading) {
        // Check if all grading fields are nullish (null or 0) and skip them
        bool allGradesNullish = fields.every((field) =>
        player[field] == null || player[field] == 0);
        if (allGradesNullish) {
          continue; // Skip this player
        }

        bool allGradesSet = true;

        // Check if all grading fields are set (not null and not 0)
        for (var field in fields) {
          if (player[field] == null || player[field] == 0) {
            allGradesSet = false;
            break;
          }
        }

        if (allGradesSet) {
          // Additionally, ensure all grades are within the valid range (1-10)
          bool allGradesValid = fields.every((field) =>
          player[field] >= 1 && player[field] <= 10);
          if (allGradesValid) {
            validGrading.add(player);
          } else {
            invalidPlayers.add(player['username']);
          }
        } else {
          invalidPlayers.add(player['username']);
        }
      }

      // Handle submission based on validity
      if (validGrading.isEmpty) {
        // No valid grades to submit
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No valid grades to submit.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Submit the valid gradings
      final response = await _apiService.post('rankings', {
        'rater_username': user,
        'rankings': validGrading,
      });

      if (response['success']) {
        String successMessage = 'Grading submitted successfully!';
        if (invalidPlayers.isNotEmpty) {
          successMessage +=
          '\nPlayers not submitted due to incomplete grades: ${invalidPlayers.join(', ')}.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 6),
          ),
        );

        // **Step 1: Fetch Updated Rankings**
        List<bool> results = await Future.wait([
          RankingsService.fetchAndCachePlayerRankingsForUser(user!),
          RankingsService.fetchAndCacheOverallPlayerRankings(),
        ]);

        bool cacheUserRankingsSuccess = results[0];
        bool cacheOverallRankingsSuccess = results[1];

        if (!cacheUserRankingsSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update cached player rankings.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        if (!cacheOverallRankingsSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update cached overall player rankings.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        // Optionally, you can refresh the UI or navigate away here
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit grading. Please try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred while submitting: $error'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// Removes the floating buttons overlay with optional selection reset
  void _removeFloatingButtons({bool resetSelection = true}) {
    _floatingButtonsOverlay?.remove();
    _floatingButtonsOverlay = null;
    if (resetSelection && mounted) {
      setState(() {
        _selectedGradeButtonUsername = null;
        _selectedGradeButtonField = null;
      });
    }
  }

  /// Shows the floating + and - buttons at the specified position
  void _showFloatingButtons(Offset position, String username, String field) {
    _removeFloatingButtons(resetSelection: false); // Prevent resetting the selection

    final overlay = Overlay.of(context)!;

    _floatingButtonsOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Positioned floating buttons aligned with the grade button
          Positioned(
            left: position.dx - 30,
            top: position.dy - 90,
            child: Column(
              children: [
                // + Button
                AnimatedOpacity(
                  opacity: 0.8,
                  duration: Duration(milliseconds: 300),
                  child: FloatingActionButton(
                    mini: false,
                    backgroundColor: Colors.green[200],
                    onPressed: () {
                      setState(() {
                        int index = grading.indexWhere((p) => p['username'] == username);
                        if (index != -1) {
                          if (grading[index][field] == null || grading[index][field] == 0) {
                            grading[index][field] = 5;
                          } else if (grading[index][field] < 10) {
                            grading[index][field]++;
                          }
                          _updatePlayerAverage(grading[index]);
                        }
                      });
                    },
                    child: Text(
                      '+',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Colors.green,
                      ),
                    ),
                    tooltip: 'Increase Grade',
                  ),
                ),
                SizedBox(height: 70),
                // - Button
                AnimatedOpacity(
                  opacity: 0.8,
                  duration: Duration(milliseconds: 300),
                  child: FloatingActionButton(
                    mini: false,
                    backgroundColor: Colors.red[200],
                    onPressed: () {
                      setState(() {
                        int index = grading.indexWhere((p) => p['username'] == username);
                        if (index != -1) {
                          if (grading[index][field] == null || grading[index][field] == 0) {
                            grading[index][field] = 5;
                          } else if (grading[index][field] > 1) {
                            grading[index][field]--;
                          }
                          _updatePlayerAverage(grading[index]);
                        }
                      });
                    },
                    child: Text(
                      '-',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    tooltip: 'Decrease Grade',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    overlay.insert(_floatingButtonsOverlay!);
  }

  /// Updates the average grade for a player (UPDATED: using new keys)
  void _updatePlayerAverage(Map<String, dynamic> player) {
    double sum = 0;
    int count = 0;
    List<String> fields = [
      'param1',
      'param2',
      'param3',
      'param4',
      'param5',
      'param6'
    ];
    for (var field in fields) {
      int grade = player[field];
      if (grade != null && grade > 0) {
        sum += grade;
        count += 1;
      }
    }
    double average = 0.0;
    if (count > 0) {
      average = sum / count;
    }
    player['average'] = average;
  }

  /// Handles selecting a player and freezing their row
  void _selectPlayer(String username) {
    setState(() {
      if (_frozenPlayerUsername == username) {
        _frozenPlayerUsername = null;
      } else {
        _frozenPlayerUsername = username;
      }
    });
  }

  /// Sorts the grading list according to the current sorting order
  void _sortGradingList() {
    setState(() {
      if (_isAscending) {
        grading.sort((a, b) => a['average'].compareTo(b['average']));
      } else {
        grading.sort((a, b) => b['average'].compareTo(a['average']));
      }
    });
  }

  Widget buildGradeButton(String username, String field, bool isRowSelected) {
    Map<String, dynamic> player = grading.firstWhere(
          (p) => p['username'] == username,
      orElse: () => {
        'username': 'Unknown',
        'param1': 0,
        'param2': 0,
        'param3': 0,
        'param4': 0,
        'param5': 0,
        'param6': 0,
      },
    );

    if (player['username'] == 'Unknown') {
      return SizedBox();
    }

    // Check if this grade button is selected
    bool isSelected = _selectedGradeButtonUsername == username && _selectedGradeButtonField == field;
    final definitions = getLegendDefinitions(_sport);
    final iconData = definitions[field]?['icon'];

    return GradeButton(
      grade: player[field],
      icon: iconData, // Use icon from legend definitions
      isSelected: isSelected,
      isRowSelected: isRowSelected,
      onIncrement: () {
        setState(() {
          int index = grading.indexWhere((p) => p['username'] == username);
          if (index != -1) {
            if (grading[index][field] == null || grading[index][field] == 0) {
              grading[index][field] = 5;
            } else if (grading[index][field] < 10) {
              grading[index][field]++;
            }
            _updatePlayerAverage(grading[index]);
          }
        });
      },
      onDecrement: () {
        setState(() {
          int index = grading.indexWhere((p) => p['username'] == username);
          if (index != -1) {
            if (grading[index][field] == null || grading[index][field] == 0) {
              grading[index][field] = 5;
            } else if (grading[index][field] > 1) {
              grading[index][field]--;
            }
            _updatePlayerAverage(grading[index]);
          }
        });
      },
      onTap: (position) {
        setState(() {
          _selectedGradeButtonUsername = username;
          _selectedGradeButtonField = field;
          _frozenPlayerUsername = username;
        });
        _showFloatingButtons(position, username, field);
      },
    );
  }

  Widget buildPlayerRow(Map<String, dynamic> player) {
    bool isRowSelected = _frozenPlayerUsername == player['username'];

    return GestureDetector(
      onTap: () {
        _selectPlayer(player['username']);
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
        child: Row(
          children: [
            // Username Section with average
            Expanded(
              flex: 2,
              child: Card(
                elevation: 1,
                margin: EdgeInsets.symmetric(vertical: 1),
                color: Colors.white,
                child: ListTile(
                  contentPadding: EdgeInsets.only(left: 4.0),
                  horizontalTitleGap: 4.0,
                  minLeadingWidth: 0,
                  visualDensity: VisualDensity.compact,
                  dense: true,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: DefaultTextStyle(
                          style: TextStyle(color: Colors.green),
                          child: Text('Full username: ${player['username']}'),
                        ),
                        duration: Duration(seconds: 2),
                        backgroundColor: Colors.white,
                      ),
                    );
                  },
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          player['username'],
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 4),
                      Text(
                        player['average'] != null ? player['average'].toStringAsFixed(1) : '0.0',
                        style: TextStyle(
                          color: Colors.green[700],
                          fontSize: 10,
                        ),
                      ),
                      SizedBox(width: 6),
                    ],
                  ),
                ),
              ),
            ),
            // Grade Buttons (UPDATED: using new keys instead of old ones)
            Expanded(
              child: buildGradeButton(player['username'], 'param1', isRowSelected),
            ),
            Expanded(
              child: buildGradeButton(player['username'], 'param2', isRowSelected),
            ),
            Expanded(
              child: buildGradeButton(player['username'], 'param3', isRowSelected),
            ),
            Expanded(
              child: buildGradeButton(player['username'], 'param4', isRowSelected),
            ),
            Expanded(
              child: buildGradeButton(player['username'], 'param5', isRowSelected),
            ),
            Expanded(
              child: buildGradeButton(player['username'], 'param6', isRowSelected),
            ),
          ],
        ),
      ),
    );
  }

  /// Function to show explanations in English
  void _showEnglishExplanation() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'The selected player\'s grades will also appear above the table for easy comparison with others: ',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Icon(Icons.looks_one, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Param1: Generic parameter 1',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.looks_two, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Param2: Generic parameter 2',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.looks_3, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Param3: Generic parameter 3',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.looks_4, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Param4: Generic parameter 4',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.looks_5, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Param5: Generic parameter 5',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.looks_6, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Param6: Generic parameter 6',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Function to show explanations in Hebrew
  void _showHebrewExplanation() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'ציוני השחקן הנבחר יופיעו גם מעל הטבלה להשוואה נוחה עם אחרים: ',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Icon(Icons.looks_one, size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Param1: פרמטר כללי 1',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.looks_two, size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Param2: פרמטר כללי 2',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.looks_3, size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Param3: פרמטר כללי 3',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.looks_4, size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Param4: פרמטר כללי 4',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.looks_5, size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Param5: פרמטר כללי 5',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.looks_6, size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Param6: פרמטר כללי 6',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Method to build frozen row or instruction
  Widget _buildFrozenRowOrInstruction() {
    if (_frozenPlayerUsername != null) {
      return buildFrozenPlayerRow();
    } else {
      return Container(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
          child: Center(
            child: Text(
              'Tap on a grade to adjust it',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.green,
                fontSize: 20,
              ),
            ),
          ),
        ),
      );
    }
  }

  /// Method to build the frozen player row (UPDATED: using new keys)
  Widget buildFrozenPlayerRow() {
    Map<String, dynamic> player = grading.firstWhere(
          (p) => p['username'] == _frozenPlayerUsername,
      orElse: () => {},
    );
    if (player.isEmpty) {
      return SizedBox();
    }
    return GestureDetector(
      onTap: () {
        _selectPlayer(player['username']);
      },
      child: Container(
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Card(
                elevation: 1,
                margin: EdgeInsets.symmetric(vertical: 1),
                color: Colors.white,
                child: ListTile(
                  contentPadding: EdgeInsets.only(left: 4.0),
                  horizontalTitleGap: 4.0,
                  minLeadingWidth: 0,
                  visualDensity: VisualDensity.compact,
                  dense: true,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: DefaultTextStyle(
                          style: TextStyle(color: Colors.green),
                          child: Text('Full username: ${player['username']}'),
                        ),
                        duration: Duration(seconds: 3),
                        backgroundColor: Colors.white,
                      ),
                    );
                  },
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          player['username'],
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 4),
                      Text(
                        player['average'] != null ? player['average'].toStringAsFixed(1) : '0.0',
                        style: TextStyle(
                          color: Colors.green[700],
                          fontSize: 10,
                        ),
                      ),
                      SizedBox(width: 6),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: buildGradeButton(_frozenPlayerUsername!, 'param1', true),
            ),
            Expanded(
              child: buildGradeButton(_frozenPlayerUsername!, 'param2', true),
            ),
            Expanded(
              child: buildGradeButton(_frozenPlayerUsername!, 'param3', true),
            ),
            Expanded(
              child: buildGradeButton(_frozenPlayerUsername!, 'param4', true),
            ),
            Expanded(
              child: buildGradeButton(_frozenPlayerUsername!, 'param5', true),
            ),
            Expanded(
              child: buildGradeButton(_frozenPlayerUsername!, 'param6', true),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double textSize = Theme.of(context).textTheme.bodyLarge?.fontSize ?? 14;
    // Get the legend definitions based on sport
    final definitions = getLegendDefinitions(_sport);
    // Determine language (using locale)
    bool isHebrew = Localizations.localeOf(context).languageCode == 'he';
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              SizedBox(height: 10),
              // Legend widget
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                // Optionally, you might update the Legend widget to reflect new parameter names
                child: Legend(showTeamAverage: false),
              ),
              SizedBox(height: 10),
              // Instruction or frozen row
              _buildFrozenRowOrInstruction(),
              SizedBox(height: 10),
              // Legend row with icons and sorting (UPDATED: using icons and labels from legend_config)
              Container(
                color: Colors.grey[200],
                padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          Icon(
                            Icons.person,
                            color: Colors.green[700],
                            size: 22,
                            semanticLabel: 'Username',
                          ),
                          SizedBox(width: 6),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _isAscending = !_isAscending;
                                _sortGradingList();
                              });
                            },
                            icon: Icon(
                              Icons.swap_vert,
                              color: Colors.green[700],
                              size: 24,
                            ),
                            label: Text(
                              'Sort',
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
                        ],
                      ),
                    ),
                    ...['param1', 'param2', 'param3', 'param4', 'param5', 'param6']
                        .map((param) => Expanded(
                      child: Tooltip(
                        message: isHebrew
                            ? definitions[param]!['label_he']
                            : definitions[param]!['label_en'],
                        child: Icon(
                          definitions[param]!['icon'],
                          color: Colors.green[700],
                          size: 24,
                        ),
                      ),
                    ))
                        .toList(),
                  ],
                ),
              ),
              SizedBox(height: 10),
              // List of players
              Expanded(
                child: ListView.builder(
                  itemCount: grading.length,
                  itemBuilder: (context, index) {
                    Map<String, dynamic> player = grading[index];
                    return buildPlayerRow(player);
                  },
                ),
              ),
              // Submit button
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton(
                  onPressed: submitGrading,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[200],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                  child: Text(
                    'Submit',
                    style: TextStyle(
                      color: Colors.green[700],
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 10),
            ],
          ),
          // Information buttons at the bottom
          Positioned(
            bottom: 10,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // English Explanation Button
                TextButton(
                  onPressed: _showEnglishExplanation,
                  child: Text(
                    'help',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 16,
                    ),
                  ),
                ),
                // Hebrew Explanation Button
                TextButton(
                  onPressed: _showHebrewExplanation,
                  child: Text(
                    'עזרה',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom GradeButton Widget using Overlay
class GradeButton extends StatelessWidget {
  final int? grade;
  final IconData? icon;
  final bool isSelected;
  final bool isRowSelected;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final Function(Offset position) onTap;

  GradeButton({
    required this.grade,
    required this.icon,
    required this.isSelected,
    required this.isRowSelected,
    required this.onIncrement,
    required this.onDecrement,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        RenderBox renderBox = context.findRenderObject() as RenderBox;
        Offset position = renderBox.localToGlobal(Offset.zero);
        Size size = renderBox.size;
        Offset center = position + Offset(size.width / 2, size.height / 2);
        onTap(center);
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected
              ? Colors.green[100]
              : (isRowSelected
              ? Colors.green[50]
              : (grade != null && grade! > 0)
              ? Colors.white
              : Colors.white),
        ),
        alignment: Alignment.center,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            grade != null && grade! > 0
                ? Text(
              '$grade',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            )
                : CircleAvatar(
              radius: 10,
              backgroundImage: AssetImage('assets/images/basketball.jpeg'),
              backgroundColor: Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}
