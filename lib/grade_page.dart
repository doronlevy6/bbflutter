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

  // Variables to track the focused grade
  String? _focusedUsername;
  String? _focusedField;

  // Controller for the TextField
  TextEditingController _gradeController = TextEditingController();

  // FocusNode for the TextField
  FocusNode _gradeFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    fetchInitialData();
  }

  @override
  void dispose() {
    _removeFloatingButtons();
    _gradeController.dispose();
    _gradeFocusNode.dispose();
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

  /// Shows the floating + and - buttons at the specified position
  void _showFloatingButtons(Offset position, String username, String field) {
    _removeFloatingButtons(); // Remove existing floating buttons if any

    final overlay = Overlay.of(context)!;

    _floatingButtonsOverlay = OverlayEntry(
      builder: (context) => GestureDetector(
        onTap: () {
          _removeFloatingButtons();
          _unfocusGrade();
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
                          int index = grading.indexWhere((p) => p['username'] == username);
                          if (index != -1 && grading[index][field] < 10) {
                            grading[index][field]++;
                            _gradeController.text = grading[index][field].toString();
                          }
                        });
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
                          int index = grading.indexWhere((p) => p['username'] == username);
                          if (index != -1 && grading[index][field] > 1) {
                            grading[index][field]--;
                            _gradeController.text = grading[index][field].toString();
                          }
                        });
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

  /// Focuses on the grade button for manual input
  void _focusGrade(String username, String field) {
    setState(() {
      _focusedUsername = username;
      _focusedField = field;
    });

    // Delay to ensure the overlay has been rendered before requesting focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gradeFocusNode.requestFocus();
    });
  }

  /// Unfocuses the currently focused grade button
  void _unfocusGrade() {
    setState(() {
      _focusedUsername = null;
      _focusedField = null;
    });
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
      return SizedBox(); // Or any other widget you'd like to show
    }

    // Check if this grade button is currently focused
    bool isFocused = (_focusedUsername == username) && (_focusedField == field);

    if (isFocused) {
      // Show TextField for manual input
      _gradeController.text = player[field].toString();
      return SizedBox(
        width: 30, // Set a fixed width
        child: TextField(
          controller: _gradeController,
          focusNode: _gradeFocusNode,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14, // Reduced font size
          ),
          decoration: InputDecoration(
            isDense: true, // Reduces the height
            contentPadding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 6.0),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4.0),
            ),
          ),
          onSubmitted: (value) {
            int? newGrade = int.tryParse(value);
            if (newGrade != null && newGrade >= 1 && newGrade <= 10) {
              setState(() {
                int index = grading.indexWhere((p) => p['username'] == username);
                if (index != -1) {
                  grading[index][field] = newGrade;
                }
              });
              _removeFloatingButtons();
              _unfocusGrade();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Grade updated successfully!')),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Please enter a valid grade between 1 and 10.')),
              );
            }
          },
          onEditingComplete: () {
            _removeFloatingButtons();
            _unfocusGrade();
          },
        ),
      );
    } else {
      // Show the standard GradeButton
      return GradeButton(
        grade: player[field],
        onIncrement: () {
          setState(() {
            int index = grading.indexWhere((p) => p['username'] == username);
            if (index != -1 && grading[index][field] < 10) {
              grading[index][field]++;
            }
          });
        },
        onDecrement: () {
          setState(() {
            int index = grading.indexWhere((p) => p['username'] == username);
            if (index != -1 && grading[index][field] > 1) {
              grading[index][field]--;
            }
          });
        },
        onTap: (position) {
          _selectPlayer(player['username']);
          _showFloatingButtons(position, username, field);
          _focusGrade(username, field);
        },
      );
    }
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
                textAlign: TextAlign.center, // Center align the text
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
              Text(
                'Playmaker (PM): A player who excels at creating scoring opportunities for themselves or their teammates, often through passing or dribbling.',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 10),
              Text(
                'Scoring Ability (SA): The ability to score baskets effectively from various positions on the court, utilizing a variety of offensive moves.',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 10),
              Text(
                'Defensive Skills (DS): The ability to prevent opponents from scoring through techniques such as shot blocking, ball stealing, and maintaining good defensive positioning.',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 10),
              Text(
                'Speed and Agility (AG): The ability to move quickly and change direction easily, which aids both offensive and defensive plays.',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 10),
              Text(
                '3-Point Shooting (3PT): The ability to successfully make shots from beyond the three-point arc.',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 10),
              Text(
                'Rebound Skills (RB): The ability to secure rebounds on both offense and defense.',
                style: TextStyle(fontSize: 16),
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
        textDirection: TextDirection.rtl, // Ensure Hebrew text is right-to-left
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'רכז (playmaker): שחקן שטוב ביצירת הזדמנויות קליעה לעצמו או לחבריו לקבוצה, לרוב באמצעות מסירה או כדרור.',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 10),
                Text(
                  'יכולת קליעה (scoring ability): היכולת לקלוע סל באופן כללי מכל עמדות על המגרש, באמצעות מגוון של תנועות התקפיות.',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 10),
                Text(
                  'מיומנויות הגנה (defensive skills): היכולת למנוע מהיריב לקלוע, באמצעות טכניקות כגון חסימת זריקות, חטיפה של הכדור, ועמידה טובה במקום.',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 10),
                Text(
                  'מהירות וזריזות (speed and agility): היכולת לנוע מהר ולשנות כיוון בקלות, דבר המסייע גם במצבים ההתקפיים וגם במצבים ההגנתיים.',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 10),
                Text(
                  'קליעה לשלוש (3 pt shooting): היכולת לקלוע מעבר לקשת השלוש.',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 10),
                Text(
                  'ריבאונד (rebound skills): היכולת לקחת ריבאונד בהתקפה ובהגנה.',
                  style: TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'Tap on a grade to adjust it. Only players with a valid grade will be submitted.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black,
                  ),
                ),
              ),
              SizedBox(height: 20),
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
                        textAlign: TextAlign.center, // Center align the text
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'PM',
                        style: TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center, // Center align the text
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'SA',
                        style: TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center, // Center align the text
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'DS',
                        style: TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center, // Center align the text
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'AG',
                        style: TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center, // Center align the text
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '3PT',
                        style: TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center, // Center align the text
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'RB',
                        style: TextStyle(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center, // Center align the text
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
                          textAlign: TextAlign.center, // Center align the text
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
          // Information Buttons at the bottom
          Positioned(
            bottom: 10,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // English Explanation Button
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: CircleBorder(),
                    padding: EdgeInsets.all(12),
                    backgroundColor: Colors.blue, // Button color
                  ),
                  onPressed: _showEnglishExplanation,
                  child: Text(
                    'EN',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                // Hebrew Explanation Button
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: CircleBorder(),
                    padding: EdgeInsets.all(12),
                    backgroundColor: Colors.green, // Button color
                  ),
                  onPressed: _showHebrewExplanation,
                  child: Text(
                    'HE',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
