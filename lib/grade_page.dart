// lib/screens/grade_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'legend_page.dart';

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

  @override
  void initState() {
    super.initState();
    fetchInitialData();
  }

  @override
  void dispose() {
    _removeFloatingButtons(); // This will reset the selection
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

          // Compute average for each player
          for (var player in initialGrading) {
            double sum = 0;
            int count = 0;
            List<String> fields = [
              'skillLevel',
              'scoringAbility',
              'defensiveSkills',
              'speedAndAgility',
              'shootingRange',
              'reboundSkills'
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

          // Sort the initialGrading list according to average (descending)
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

  /// Removes the floating buttons overlay with optional selection reset
  void _removeFloatingButtons({bool resetSelection = true}) {
    _floatingButtonsOverlay?.remove();
    _floatingButtonsOverlay = null;
    if (resetSelection) {
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
            left: position.dx - 30, // Adjust to center the buttons horizontally
            top: position.dy - 90, // Position + button above the grade button
            child: Column(
              children: [
                // + Button
                AnimatedOpacity(
                  opacity: 0.8,
                  duration: Duration(milliseconds: 300),
                  child: FloatingActionButton(
                    mini: false, // Enlarge the button
                    backgroundColor: Colors.green[200],
                    // Background color set to green 200
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

  /// Updates the average grade for a player
  void _updatePlayerAverage(Map<String, dynamic> player) {
    double sum = 0;
    int count = 0;
    List<String> fields = [
      'skillLevel',
      'scoringAbility',
      'defensiveSkills',
      'speedAndAgility',
      'shootingRange',
      'reboundSkills'
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
    bool isSelected = _selectedGradeButtonUsername == username && _selectedGradeButtonField == field;

    return GradeButton(
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
                child: ListTile(
                  contentPadding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                  horizontalTitleGap: 4.0,
                  minLeadingWidth: 0,
                  visualDensity: VisualDensity.compact,
                  dense: true,
                  leading: Icon(
                    Icons.person,
                    color: Colors.green[700],
                    size: 16,
                  ),
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
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Grade Buttons
            Expanded(
              child: buildGradeButton(player['username'], 'skillLevel', isRowSelected),
            ),
            Expanded(
              child: buildGradeButton(player['username'], 'scoringAbility', isRowSelected),
            ),
            Expanded(
              child: buildGradeButton(player['username'], 'defensiveSkills', isRowSelected),
            ),
            Expanded(
              child: buildGradeButton(player['username'], 'speedAndAgility', isRowSelected),
            ),
            Expanded(
              child: buildGradeButton(player['username'], 'shootingRange', isRowSelected),
            ),
            Expanded(
              child: buildGradeButton(player['username'], 'reboundSkills', isRowSelected),
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
                    child: Text('Player grades will also appear above the table for easy scrolling and comparison with others: ' ,style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Icon(Icons.handshake, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Playmaker (PM): A player who excels at creating scoring opportunities for themselves or their teammates, often through passing or dribbling.',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.score, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Scoring Ability (SA): The ability to score baskets effectively from various positions on the court, utilizing a variety of offensive moves.',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.shield, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Defensive Skills (DS): The ability to prevent opponents from scoring through techniques such as shot blocking, ball stealing, and maintaining good defensive positioning.',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.speed, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Speed and Agility (AG): The ability to move quickly and change direction easily, which aids both offensive and defensive plays.',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.sports_basketball, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '3-Point Shooting (3PT): The ability to successfully make shots from beyond the three-point arc.',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.grain, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Rebound Skills (RB): The ability to secure rebounds on both offense and defense.',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ],
          )
          ,
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
                      child: Text(' ציוני השחקן יופיעו גם מעל הטבלה להשוואה נוחה עם אחרים: ' ,style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Icon(Icons.handshake, size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'רכז (playmaker): שחקן שטוב ביצירת הזדמנויות קליעה לעצמו או לחבריו לקבוצה, לרוב באמצעות מסירה או כדרור.',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.score, size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'יכולת קליעה (scoring ability): היכולת לקלוע סל באופן כללי מכל עמדות על המגרש, באמצעות מגוון של תנועות התקפיות.',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.shield, size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'מיומנויות הגנה (defensive skills): היכולת למנוע מהיריב לקלוע, באמצעות טכניקות כגון חסימת זריקות, חטיפה של הכדור, ועמידה טובה במקום.',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.speed, size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'מהירות וזריזות (speed and agility): היכולת לנוע מהר ולשנות כיוון בקלות, דבר המסייע גם במצבים ההתקפיים וגם במצבים ההגנתיים.',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.sports_basketball, size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'קליעה לשלוש (3 pt shooting): היכולת לקלוע מעבר לקשת השלוש.',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.grain, size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'ריבאונד (rebound skills): היכולת לקחת ריבאונד בהתקפה ובהגנה.',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
              ],
            )
            ,
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

  /// Method to build the frozen player row
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
        // Unfreeze the row when it's tapped again
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
                child: ListTile(
                  contentPadding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                  horizontalTitleGap: 4.0,
                  minLeadingWidth: 0,
                  visualDensity: VisualDensity.compact,
                  dense: true,
                  leading: Icon(
                    Icons.person,
                    color: Colors.green[700],
                    size: 16,
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _frozenPlayerUsername!,
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
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: buildGradeButton(_frozenPlayerUsername!, 'skillLevel', true),
            ),
            Expanded(
              child: buildGradeButton(_frozenPlayerUsername!, 'scoringAbility', true),
            ),
            Expanded(
              child: buildGradeButton(_frozenPlayerUsername!, 'defensiveSkills', true),
            ),
            Expanded(
              child: buildGradeButton(_frozenPlayerUsername!, 'speedAndAgility', true),
            ),
            Expanded(
              child: buildGradeButton(_frozenPlayerUsername!, 'shootingRange', true),
            ),
            Expanded(
              child: buildGradeButton(_frozenPlayerUsername!, 'reboundSkills', true),
            ),
          ],
        ),
      ),
    );
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
                child: Legend(showTeamAverage: false),
              ),
              SizedBox(height: 10),
              // Instruction or frozen row
              _buildFrozenRowOrInstruction(),
              SizedBox(height: 10),
              // Legend row with icons and sorting
              Container(
                color: Colors.grey[200],
                padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              _isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                              color: Colors.green[700],
                              size: 24,
                            ),
                            onPressed: () {
                              _isAscending = !_isAscending;
                              _sortGradingList();
                            },
                          ),
                          Icon(
                            Icons.person,
                            color: Colors.green[700],
                            size: 24,
                            semanticLabel: 'Username',
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
    required this.grade,
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
              ? Colors.green[200]
              : (isRowSelected
              ? Colors.green[100]
              : (grade != null && grade! > 0)
              ? Colors.green[50]
              : Colors.green[50]),
        ),
        alignment: Alignment.center,
        child: grade != null && grade! > 0
            ? Text(
          '$grade',
          style: TextStyle(
            color: isRowSelected ? Colors.green : Colors.green,
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

