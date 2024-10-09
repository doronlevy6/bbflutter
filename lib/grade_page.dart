// lib/screens/grade_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

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

      final response = await _apiService.post('rankings', {
        'rater_username': user,
        'rankings': validGrading,
      });

      if (response['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully submitted grading!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit grading.')),
        );
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit grading: $error')),
      );
    }
  }

  /// Shows the floating + and - buttons at the specified position
  void _showFloatingButtons(Offset position, String username, String field) {
    _removeFloatingButtons(); // Remove existing floating buttons if any

    final overlay = Overlay.of(context)!;

    _floatingButtonsOverlay = OverlayEntry(
      builder: (context) => GestureDetector(
        onTap: () {
          _removeFloatingButtons(); // Remove floating buttons when tapping outside
        },
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            // Positioned floating buttons aligned with the grade button
            Positioned(
              left: position.dx - 20, // Adjust to center the buttons horizontally
              top: position.dy - 65, // Position + button above the grade button
              child: Column(
                children: [
                  // + Button
                  AnimatedOpacity(
                    opacity: 1.0,
                    duration: Duration(milliseconds: 300),
                    child: FloatingActionButton(
                      mini: true,
                      backgroundColor: Colors.green,
                      onPressed: () {
                        setState(() {
                          // Find the player in the grading list
                          int index = grading.indexWhere((p) => p['username'] == username);
                          if (index != -1 && grading[index][field] < 10) {
                            grading[index][field]++;
                          }
                        });
                        _removeFloatingButtons();

                        // If the frozen row is for this player, the UI will update automatically
                      },
                      child: Icon(Icons.add),
                      tooltip: 'Increase Grade',
                    ),
                  ),
                  SizedBox(height: 50),
                  // - Button
                  AnimatedOpacity(
                    opacity: 1.0,
                    duration: Duration(milliseconds: 300),
                    child: FloatingActionButton(
                      mini: true,
                      backgroundColor: Colors.red,
                      onPressed: () {
                        setState(() {
                          // Find the player in the grading list
                          int index = grading.indexWhere((p) => p['username'] == username);
                          if (index != -1 && grading[index][field] > 1) {
                            grading[index][field]--;
                          }
                        });
                        _removeFloatingButtons();

                        // If the frozen row is for this player, the UI will update automatically
                      },
                      child: Icon(Icons.remove),
                      tooltip: 'Decrease Grade',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // Insert the overlay
    overlay.insert(_floatingButtonsOverlay!);
  }

  /// Removes the floating buttons overlay
  void _removeFloatingButtons() {
    _floatingButtonsOverlay?.remove();
    _floatingButtonsOverlay = null;
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

  Widget buildGradeButton(String username, String field) {
    // Fetch the updated player data from the grading list
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

    // Optionally, handle the 'Unknown' player differently if needed
    if (player['username'] == 'Unknown') {
      return SizedBox(); // Or any other widget you'd like to show
    }

    return GradeButton(
      grade: player[field],
      onIncrement: () {
        setState(() {
          int index = grading.indexWhere((p) => p['username'] == username);
          if (index != -1 && grading[index][field] < 10) {
            grading[index][field]++;
          }
        });
        _removeFloatingButtons();

        // If the frozen row is for this player, the UI will update automatically
      },
      onDecrement: () {
        setState(() {
          int index = grading.indexWhere((p) => p['username'] == username);
          if (index != -1 && grading[index][field] > 1) {
            grading[index][field]--;
          }
        });
        _removeFloatingButtons();

        // If the frozen row is for this player, the UI will update automatically
      },
      onTap: (position) {
        _showFloatingButtons(position, username, field);
      },
    );
  }

  Widget buildPlayerRow(Map<String, dynamic> player) {
    return GestureDetector(
      onTap: () {
        _selectPlayer(player['username']);
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
        decoration: BoxDecoration(
          color: _frozenPlayerUsername == player['username']
              ? Colors.grey[300]
              : Colors.white,
          border: Border(bottom: BorderSide(color: Colors.grey)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                player['username'],
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$user 🏀 Your Grades 🏀'),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'Tap on a grade to adjust it using the + and - buttons. Only players with a valid grade will be submitted.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black,
                  ),
                ),
              ),
              SizedBox(height: 10),
              // Legend row
              Container(
                color: Colors.grey[200],
                padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Username',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'PM',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'SA',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'DS',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'AG',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '3PT',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'RB',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              // The list of players
              Expanded(
                child: ListView.builder(
                  itemCount: grading.length,
                  itemBuilder: (context, index) {
                    Map<String, dynamic> player = grading[index];
                    return buildPlayerRow(player);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton(
                  onPressed: submitGrading,
                  child: Text('Submit'),
                ),
              ),
              SizedBox(height: 10),
            ],
          ),
          // Frozen Row Overlay
          if (_frozenPlayerUsername != null)
            Positioned(
              top: 0, // Adjust based on where you want to position the frozen row
              left: 0,
              right: 0,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    border: Border(
                      bottom: BorderSide(color: Colors.grey),
                      top: BorderSide(color: Colors.grey),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          _frozenPlayerUsername!,
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: buildGradeButton(_frozenPlayerUsername!, 'skillLevel'),
                      ),
                      Expanded(
                        child: buildGradeButton(_frozenPlayerUsername!, 'scoringAbility'),
                      ),
                      Expanded(
                        child: buildGradeButton(_frozenPlayerUsername!, 'defensiveSkills'),
                      ),
                      Expanded(
                        child: buildGradeButton(_frozenPlayerUsername!, 'speedAndAgility'),
                      ),
                      Expanded(
                        child: buildGradeButton(_frozenPlayerUsername!, 'shootingRange'),
                      ),
                      Expanded(
                        child: buildGradeButton(_frozenPlayerUsername!, 'reboundSkills'),
                      ),
                    ],
                  ),
                ),
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
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final Function(Offset position) onTap;

  GradeButton({
    required this.grade,
    required this.onIncrement,
    required this.onDecrement,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Get the position of the grade button
        RenderBox renderBox = context.findRenderObject() as RenderBox;
        Offset position = renderBox.localToGlobal(Offset.zero);
        Size size = renderBox.size;
        Offset center = position + Offset(size.width / 2, size.height / 2);

        // Call the onTap callback with the center position
        onTap(center);
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: (grade != null && grade! > 0) ? Colors.blueAccent : Colors.orangeAccent,
        ),
        alignment: Alignment.center,
        child: grade != null && grade! > 0
            ? Text(
          '$grade',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        )
            : Text(
          '🏀',
          style: TextStyle(
            fontSize: 20,
          ),
        ),
      ),
    );
  }
}
