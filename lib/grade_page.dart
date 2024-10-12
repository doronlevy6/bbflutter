// lib/screens/grade_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'legened_page.dart';

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

  // Map to hold GlobalKeys for each GradeButton
  Map<String, Map<String, GlobalKey>> _gradeButtonKeys = {};

  @override
  void initState() {
    super.initState();
    fetchInitialData();
  }

  @override
  void dispose() {
    _removeFloatingButtons();
    super.dispose();
  }

  Future<void> fetchInitialData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    user = prefs.getString('user');

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

            // If the current user is "doron" or "Moshe", they can rank themselves
            if ((username == 'doron' || username == 'Moshe') && user == username) {
              // Allow ranking themselves
            } else if (username == user) {
              // Other users cannot rank themselves
              continue;
            }

            if (rankingsByUser.containsKey(username)) {
              // If ranking exists, use it
              initialGrading.add({
                'username': username,
                'skillLevel': rankingsByUser[username]['skill_level'] ?? 0,
                'scoringAbility': rankingsByUser[username]['scoring_ability'] ?? 0,
                'defensiveSkills': rankingsByUser[username]['defensive_skills'] ?? 0,
                'speedAndAgility': rankingsByUser[username]['speed_and_agility'] ?? 0,
                'shootingRange': rankingsByUser[username]['shooting_range'] ?? 0,
                'reboundSkills': rankingsByUser[username]['rebound_skills'] ?? 0,
              });
            } else {
              // Initialize with default values
              initialGrading.add({
                'username': username,
                'skillLevel': 0, // 0 indicates no grade assigned
                'scoringAbility': 0,
                'defensiveSkills': 0,
                'speedAndAgility': 0,
                'shootingRange': 0,
                'reboundSkills': 0,
              });
            }
          }

          setState(() {
            grading = initialGrading;
            _recalculateAveragesAndSort(); // Sort the list at the beginning
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
      // Filter out players with invalid grades (ensure all grades are between 1 and 10)
      List<Map<String, dynamic>> validGrading = grading.where((player) {
        return player['skillLevel'] != null &&
            player['scoringAbility'] != null &&
            player['defensiveSkills'] != null &&
            player['speedAndAgility'] != null &&
            player['shootingRange'] != null &&
            player['reboundSkills'] != null &&
            player['skillLevel'] >= 1 &&
            player['skillLevel'] <= 10 &&
            player['scoringAbility'] >= 1 &&
            player['scoringAbility'] <= 10 &&
            player['defensiveSkills'] >= 1 &&
            player['defensiveSkills'] <= 10 &&
            player['speedAndAgility'] >= 1 &&
            player['speedAndAgility'] <= 10 &&
            player['shootingRange'] >= 1 &&
            player['shootingRange'] <= 10 &&
            player['reboundSkills'] >= 1 &&
            player['reboundSkills'] <= 10;
      }).toList();

      if (validGrading.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No valid grades to submit. Please assign grades between 1 and 10.')),
        );
        return;
      }

      final response = await _apiService.post('rankings', {
        'rater_username': user,
        'rankings': validGrading,
      });

      if (response['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Grading submitted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        // Optionally, you can refresh the data or navigate away
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit grading. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred while submitting: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Recalculate averages and sort the grading list
  void _recalculateAveragesAndSort() {
    for (var player in grading) {
      double total = 0;
      int count = 0;
      for (var field in [
        'skillLevel',
        'scoringAbility',
        'defensiveSkills',
        'speedAndAgility',
        'shootingRange',
        'reboundSkills'
      ]) {
        if (player[field] != null && player[field] > 0) {
          total += player[field];
          count++;
        }
      }
      player['average'] = count > 0 ? total / count : 0;
    }
    // Sort the grading list based on the average in descending order
    grading.sort((a, b) => b['average'].compareTo(a['average']));
  }

  /// Shows the floating + and - buttons at the specified position
  void _showFloatingButtons(Offset position, String username, String field) {
    _removeFloatingButtons(); // Remove existing floating buttons if any

    final overlay = Overlay.of(context)!;

    _floatingButtonsOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Positioned floating buttons aligned with the grade button
          Positioned(
            left: position.dx - 20, // Adjust to center the buttons horizontally
            top: position.dy - 90, // Position + button above the grade button
            child: Column(
              children: [
                // + Button
                AnimatedOpacity(
                  opacity: 0.8,
                  duration: Duration(milliseconds: 300),
                  child: FloatingActionButton(
                    mini: false, // Enlarge the button
                    backgroundColor: Colors.green[200], // Background color set to green 200
                    onPressed: () {
                      int index = grading.indexWhere((p) => p['username'] == username);
                      if (index != -1) {
                        setState(() {
                          if (grading[index][field] == null || grading[index][field] == 0) {
                            grading[index][field] = 5;
                          } else if (grading[index][field] < 10) {
                            grading[index][field]++;
                          }
                        });
                      }
                    },
                    child: Text(
                      '+',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.green, // Bold green + sign
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
                    mini: false, // Enlarge the button
                    backgroundColor: Colors.red[200], // Background color set to red 200
                    onPressed: () {
                      int index = grading.indexWhere((p) => p['username'] == username);
                      if (index != -1) {
                        setState(() {
                          if (grading[index][field] == null || grading[index][field] == 0) {
                            grading[index][field] = 5;
                          } else if (grading[index][field] > 1) {
                            grading[index][field]--;
                          }
                        });
                      }
                    },
                    child: Text(
                      '-',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.red, // Bold red - sign
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

    // Insert the overlay
    overlay.insert(_floatingButtonsOverlay!);
  }

  /// Removes the floating buttons overlay
  void _removeFloatingButtons() {
    _floatingButtonsOverlay?.remove();
    _floatingButtonsOverlay = null;
    // Do not reset _selectedGradeButtonUsername and _selectedGradeButtonField to keep buttons highlighted
  }

  Widget buildGradeButton(String username, String field) {
    Map<String, dynamic> player = grading.firstWhere(
          (p) => p['username'] == username,
      orElse: () => {
        'username': 'Unknown',
        'skillLevel': 0,
        'scoringAbility': 0,
        'defensiveSkills': 0,
        'speedAndAgility': 0,
        'shootingRange': 0,
        'reboundSkills': 0,
      },
    );

    if (player['username'] == 'Unknown') {
      return SizedBox();
    }

    // Check if this grade button is selected
    bool isSelected =
        _selectedGradeButtonUsername == username && _selectedGradeButtonField == field;
    bool isRowSelected = _selectedGradeButtonUsername == username;

    // Manage GlobalKeys for each GradeButton
    GlobalKey key = _gradeButtonKeys[username]?[field] ?? GlobalKey();
    _gradeButtonKeys[username] ??= {};
    _gradeButtonKeys[username]![field] = key;

    return GradeButton(
      key: key,
      grade: player[field],
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

  Widget buildPlayerRow(Map<String, dynamic> player, {bool isFrozenRow = false}) {
    bool isRowSelected = _selectedGradeButtonUsername == player['username'];
    if (isFrozenRow) {
      isRowSelected = true;
    }

    return GestureDetector(
      onTap: () {
        _selectPlayer(player['username']);
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
        decoration: BoxDecoration(
          color: Colors.white, // Row color remains the same
        ),
        child: Row(
          children: [
            // Username Section with Card and ListTile
            Expanded(
              flex: 2,
              child: Card(
                elevation: 1, // Reduced elevation
                margin: EdgeInsets.symmetric(vertical: 1), // Reduced margin
                child: ListTile(
                  contentPadding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                  horizontalTitleGap: 4.0,
                  minLeadingWidth: 0,
                  visualDensity: VisualDensity.compact,
                  dense: true,
                  leading: Icon(
                    Icons.person,
                    color: Colors.green[700],
                    size: 16, // Smaller icon
                  ),
                  title: Row(
                    children: [
                      Text(
                        player['username'],
                        style: TextStyle(
                          color: Colors.green[700],
                          fontSize: 14, // Smaller font
                        ),
                      ),
                      SizedBox(width: 5),
                      Text(
                        '(${player['average']?.toStringAsFixed(1) ?? '0.0'})',
                        style: TextStyle(
                          color: Colors.green[700], // Same color as name
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Grade Buttons
            Expanded(
              child: buildGradeButton(player['username'], 'skillLevel'),
            ),
            Expanded(
              child: buildGradeButton(player['username'], 'scoringAbility'),
            ),
            Expanded(
              child: buildGradeButton(player['username'], 'defensiveSkills'),
            ),
            Expanded(
              child: buildGradeButton(player['username'], 'speedAndAgility'),
            ),
            Expanded(
              child: buildGradeButton(player['username'], 'shootingRange'),
            ),
            Expanded(
              child: buildGradeButton(player['username'], 'reboundSkills'),
            ),
          ],
        ),
      ),
    );
  }

  /// Method to build frozen row or instruction
  Widget _buildFrozenRowOrInstruction() {
    if (_frozenPlayerUsername != null) {
      Map<String, dynamic> player = grading.firstWhere(
            (p) => p['username'] == _frozenPlayerUsername,
        orElse: () => {},
      );
      if (player.isNotEmpty) {
        return buildPlayerRow(player, isFrozenRow: true);
      } else {
        return SizedBox();
      }
    } else {
      return _buildInstruction();
    }
  }

  /// Method to build instruction
  Widget _buildInstruction() {
    return Container(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10),
        child: Center(
          child: Text(
            'Tap on a grade to adjust it',
            style: TextStyle(
              color: Colors.green,
              fontSize: 20,
            ),
          ),
        ),
      ),
    );
  }

  /// Function to show explanations in English
  void _showEnglishExplanation() {
    // Your existing code
  }

  /// Function to show explanations in Hebrew
  void _showHebrewExplanation() {
    // Your existing code
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              SizedBox(height: 10),
              // Legend widget
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Legend(),
              ),
              SizedBox(height: 10),
              // Instruction or frozen row
              _buildFrozenRowOrInstruction(),
              SizedBox(height: 10),
              // Legend row with icons
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
                            size: 24,
                            semanticLabel: 'Username',
                          ),
                          IconButton(
                            icon: Icon(Icons.sort),
                            color: Colors.green[700],
                            iconSize: 24,
                            tooltip: 'Sort by average',
                            onPressed: () {
                              setState(() {
                                _recalculateAveragesAndSort();
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Tooltip(
                        message: 'Playmaker',
                        child: Icon(
                          Icons.handshake,
                          color: Colors.green[700],
                          size: 24,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Tooltip(
                        message: 'Scoring Ability',
                        child: Icon(
                          Icons.score,
                          color: Colors.green[700],
                          size: 24,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Tooltip(
                        message: 'Defensive Skills',
                        child: Icon(
                          Icons.shield,
                          color: Colors.green[700],
                          size: 24,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Tooltip(
                        message: 'Speed and Agility',
                        child: Icon(
                          Icons.speed,
                          color: Colors.green[700],
                          size: 24,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Tooltip(
                        message: '3-Point Shooting',
                        child: Icon(
                          Icons.sports_basketball,
                          color: Colors.green[700],
                          size: 24,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Tooltip(
                        message: 'Rebound Skills',
                        child: Icon(
                          Icons.grain,
                          color: Colors.green[700],
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // List of players
              Expanded(
                child: ListView.builder(
                  itemCount: grading.length,
                  itemBuilder: (context, index) {
                    Map<String, dynamic> player = grading[index];
                    // Do not display the selected player in the list if it's frozen
                    if (_frozenPlayerUsername != null &&
                        player['username'] == _frozenPlayerUsername) {
                      return SizedBox();
                    }
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
  final bool isSelected;
  final bool isRowSelected;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final Function(Offset position) onTap;

  GradeButton({
    Key? key,
    required this.grade,
    required this.isSelected,
    required this.isRowSelected,
    required this.onIncrement,
    required this.onDecrement,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color buttonColor;
    if (isSelected) {
      buttonColor = Colors.green[700]!;
    } else if (isRowSelected) {
      buttonColor = Colors.green[200]!;
    } else {
      buttonColor = Colors.green[50]!;
    }

    Color textColor = isSelected ? Colors.white : Colors.green;

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
          color: buttonColor,
        ),
        alignment: Alignment.center,
        child: grade != null && grade! > 0
            ? Text(
          '$grade',
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        )
            : CircleAvatar(
          radius: 10,
          backgroundImage: AssetImage('assets/images/basketball.jpeg'),
          backgroundColor: Colors.transparent,
        ),
      ),
    );
  }
}
