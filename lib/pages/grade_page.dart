import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import 'legend_page.dart';
import '../services/rankings_service.dart';
import '../config/legend_config.dart';
import '../managers/asset_manager.dart';


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
  String _sport = 'bb'; // Default value

  // Language flag
  bool _isHebrew = false;

  String _teamImagePath = 'assets/images/basketball.png';
  @override
  void initState() {
    super.initState();
    _loadLanguage();
    fetchInitialData();
    _loadTeamImage();
  }

  @override
  void dispose() {
    _removeFloatingButtons(resetSelection: false); // Prevent setState() during dispose
    super.dispose();
  }

  // Load language setting from SharedPreferences using key 'isHebrew'
  Future<void> _loadLanguage() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isHebrew = prefs.getBool('isHebrew') ?? false;
    setState(() {
      _isHebrew = isHebrew;
    });
  }
  Future<void> _loadTeamImage() async {
    String imagePath = await AssetManager.getTeamImageFromCache();
    setState(() {
      _teamImagePath = imagePath;
    });
  }

  Future<void> fetchInitialData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    user = prefs.getString('user');
    _sport = prefs.getString('team_type') ?? 'bb';

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
              // If ranking exists, use it (using new keys param1...param6)
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
              // Initialize with default values
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

          // Compute average for each player
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
            double average = count > 0 ? sum / count : 0.0;
            player['average'] = average;
          }

          // Sort the grading list according to average
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isHebrew
                ? 'שגיאה בטעינת הנתונים. אנא נסה שוב מאוחר יותר.'
                : 'Error fetching data. Please try again later.'),
          ),
        );
      }
    }
  }

  Future<void> submitGrading() async {
    try {
      List<Map<String, dynamic>> validGrading = [];
      List<String> invalidPlayers = [];
      List<String> fields = ['param1', 'param2', 'param3', 'param4', 'param5', 'param6'];

      for (var player in grading) {
        bool allGradesNullish = fields.every((field) =>
        player[field] == null || player[field] == 0);
        if (allGradesNullish) {
          continue;
        }
        bool allGradesSet = true;
        for (var field in fields) {
          if (player[field] == null || player[field] == 0) {
            allGradesSet = false;
            break;
          }
        }
        if (allGradesSet) {
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

      if (validGrading.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isHebrew
                ? 'אין ציונים תקינים לשליחה.'
                : 'No valid grades to submit.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      final response = await _apiService.post('rankings', {
        'rater_username': user,
        'rankings': validGrading,
      });

      if (response['success']) {
        String successMessage = _isHebrew
            ? 'הציונים נשלחו בהצלחה!'
            : 'Grading submitted successfully!';
        if (invalidPlayers.isNotEmpty) {
          successMessage += _isHebrew
              ? '\nשחקנים שלא נשלחו בשל ציונים חלקיים: ${invalidPlayers.join(', ')}.'
              : '\nPlayers not submitted due to incomplete grades: ${invalidPlayers.join(', ')}.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 6),
          ),
        );

        List<bool> results = await Future.wait([
          RankingsService.fetchAndCachePlayerRankingsForUser(user!),
          RankingsService.fetchAndCacheOverallPlayerRankings(),
        ]);

        if (!results[0]) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isHebrew
                  ? 'נכשל עדכון דירוגי שחקנים במטמון.'
                  : 'Failed to update cached player rankings.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        if (!results[1]) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isHebrew
                  ? 'נכשל עדכון דירוג כולל במטמון.'
                  : 'Failed to update cached overall player rankings.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isHebrew
                ? 'נכשלת השליחה. אנא נסה שוב.'
                : 'Failed to submit grading. Please try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isHebrew
              ? 'אירעה שגיאה בשליחה: $error'
              : 'An error occurred while submitting: $error'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

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

  void _showFloatingButtons(Offset position, String username, String field) {
    _removeFloatingButtons(resetSelection: false);
    final overlay = Overlay.of(context)!;
    _floatingButtonsOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned(
            left: position.dx - 30,
            top: position.dy - 90,
            child: Column(
              children: [
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
                            grading[index][field] = 1;
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
                    tooltip: _isHebrew ? 'העלה ציון' : 'Increase Grade',
                  ),
                ),
                SizedBox(height: 70),
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
                            grading[index][field] =1;
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
                    tooltip: _isHebrew ? 'הורד ציון' : 'Decrease Grade',
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

  void _updatePlayerAverage(Map<String, dynamic> player) {
    double sum = 0;
    int count = 0;
    List<String> fields = ['param1', 'param2', 'param3', 'param4', 'param5', 'param6'];
    for (var field in fields) {
      int grade = player[field];
      if (grade != null && grade > 0) {
        sum += grade;
        count += 1;
      }
    }
    double average = count > 0 ? sum / count : 0.0;
    player['average'] = average;
  }

  void _selectPlayer(String username) {
    setState(() {
      _frozenPlayerUsername = _frozenPlayerUsername == username ? null : username;
    });
  }

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

    bool isSelected = _selectedGradeButtonUsername == username && _selectedGradeButtonField == field;
    final definitions = getLegendDefinitions(_sport);
    final iconData = definitions[field]?['icon'];

    return GradeButton(
      grade: player[field],
      icon: iconData,
      isSelected: isSelected,
      isRowSelected: isRowSelected,
      imagePath: _teamImagePath,
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
                      SizedBox(width: 2),
                      Text(
                        player['average'] != null ? player['average'].toStringAsFixed(1) : '0.0',
                        style: TextStyle(
                          color: Colors.green[700],
                          fontSize: 9,
                          fontWeight: FontWeight.bold
                        ),
                      ),
                      SizedBox(width: 6),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: buildGradeButton(player['username'], 'param1', isRowSelected)),
            Expanded(child: buildGradeButton(player['username'], 'param2', isRowSelected)),
            Expanded(child: buildGradeButton(player['username'], 'param3', isRowSelected)),
            Expanded(child: buildGradeButton(player['username'], 'param4', isRowSelected)),
            Expanded(child: buildGradeButton(player['username'], 'param5', isRowSelected)),
            Expanded(child: buildGradeButton(player['username'], 'param6', isRowSelected)),
          ],
        ),
      ),
    );
  }

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
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              // ... (Additional English explanation rows)
            ],
          ),
        ),
      ),
    );
  }

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
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                // ... (Additional Hebrew explanation rows)
              ],
            ),
          ),
        ),
      ),
    );
  }

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
              _isHebrew ? 'הקש על הציון ודרג (1-10)' : 'Tap on a grade to adjust it (1-10)',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.green,
                fontSize:  MediaQuery.of(context).size.width < 400 ? 14 : 20,
              ),
            ),
          ),
        ),
      );
    }
  }

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
            Expanded(child: buildGradeButton(_frozenPlayerUsername!, 'param1', true)),
            Expanded(child: buildGradeButton(_frozenPlayerUsername!, 'param2', true)),
            Expanded(child: buildGradeButton(_frozenPlayerUsername!, 'param3', true)),
            Expanded(child: buildGradeButton(_frozenPlayerUsername!, 'param4', true)),
            Expanded(child: buildGradeButton(_frozenPlayerUsername!, 'param5', true)),
            Expanded(child: buildGradeButton(_frozenPlayerUsername!, 'param6', true)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Localized text strings
    String selectedPlayersText = _isHebrew ? 'שחקנים שנבחרו: ' : 'Selected Players: ';
    String noPlayersText = _isHebrew ? 'אין שחקנים זמינים.' : 'No players available.';
    String clearText = _isHebrew ? 'נקה' : 'Clear';
    String submitText = _isHebrew ? 'שלח' : 'Submit';
    String sortText = _isHebrew ? 'מיין' : 'Sort';
    String helpText = _isHebrew ? 'עזרה' : 'help';
    String explanationText = _isHebrew ? 'עזרה' : 'help1';

    // Sorting players: selected first then alphabetical.
    List<Map<String, dynamic>> sortedGrading = List.from(grading);
    sortedGrading.sort((a, b) {
      bool aSelected = _selectedGradeButtonUsername == a['username'];
      bool bSelected = _selectedGradeButtonUsername == b['username'];
      if (aSelected && !bSelected) return -1;
      if (!aSelected && bSelected) return 1;
      return a['username'].toLowerCase().compareTo(b['username'].toLowerCase());
    });

    return Directionality(
        textDirection: _isHebrew ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
        body: Container(
        decoration: BoxDecoration(
        image: DecorationImage(
        image: AssetImage('assets/images/reka.webp'),
    fit: BoxFit.cover,
    colorFilter: ColorFilter.mode(
    Colors.white.withOpacity(0.1),
    BlendMode.dstATop,
    ),
    ),
    ),
    child: Stack(
    children: [
    Column(
    children: [
    SizedBox(height: 10),
    Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16.0),
    child: Legend(showTeamAverage: false),
    ),
    SizedBox(height: 10),
    _buildFrozenRowOrInstruction(),
    SizedBox(height: 10),
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
    semanticLabel: _isHebrew ? 'שם משתמש' : 'Username',
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
    sortText,
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
    message: _isHebrew
    ? getLegendDefinitions(_sport)[param]!['label_he']
        : getLegendDefinitions(_sport)[param]!['label_en'],
    child: Icon(
    getLegendDefinitions(_sport)[param]!['icon'],
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
    style: ElevatedButton.styleFrom(
    backgroundColor: Colors.green[200],
    shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(30),
    ),
    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
    ),
    child: Text(
    submitText,
    style: TextStyle(
    color: Colors.green[700],
    fontWeight: FontWeight.bold,
    fontSize: 16,
    ),
    textAlign: TextAlign.center,
    ),
    ),
    ),
    SizedBox(height: 10)
              ],
            ),
            // Positioned(
            //   bottom: 10,
            //   left: 20,
            //   right: 20,
            //   child: Row(
            //     mainAxisAlignment: MainAxisAlignment.spaceBetween,
            //     children: [
            //       TextButton(
            //         onPressed: _showEnglishExplanation,
            //         child: Text(
            //           _isHebrew ? explanationText : helpText,
            //           style: TextStyle(
            //             color: Colors.green,
            //             fontSize: 16,
            //           ),
            //           textAlign: TextAlign.center,
            //         ),
            //       ),
            //       // Optionally, show only one explanation button based on language.
            //     ],
            //   ),
            // ),
          ],
        ),
      ),
    )
    );
  }
}

class GradeButton extends StatelessWidget {
  final int? grade;
  final IconData? icon;
  final bool isSelected;
  final bool isRowSelected;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final Function(Offset position) onTap;
  final String imagePath;

  GradeButton({
    required this.grade,
    required this.icon,
    required this.isSelected,
    required this.isRowSelected,
    required this.onIncrement,
    required this.onDecrement,
    required this.onTap,
    required this.imagePath,
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
              textAlign: TextAlign.center,
            )
                : CircleAvatar(
              radius: 10,
              backgroundImage: AssetImage(imagePath),
              backgroundColor: Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}
