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

  @override
  void initState() {
    super.initState();
    fetchInitialData();
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
                'skillLevel': rankingsByUser[username]['skill_level'],
                'scoringAbility': rankingsByUser[username]['scoring_ability'],
                'defensiveSkills': rankingsByUser[username]['defensive_skills'],
                'speedAndAgility': rankingsByUser[username]['speed_and_agility'],
                'shootingRange': rankingsByUser[username]['shooting_range'],
                'reboundSkills': rankingsByUser[username]['rebound_skills'],
              });
            } else {
              // Initialize with empty values
              initialGrading.add({
                'username': username,
                'skillLevel': '',
                'scoringAbility': '',
                'defensiveSkills': '',
                'speedAndAgility': '',
                'shootingRange': '',
                'reboundSkills': '',
              });
            }
          }

          setState(() {
            grading = initialGrading;
          });
        }
      } catch (error) {
        print('Error fetching data: $error');
      }
    }
  }

  Future<void> submitGrading() async {
    try {
      // Filter out players with invalid grades
      List<Map<String, dynamic>> validGrading = grading.where((player) {
        return player['skillLevel'] != '' &&
            player['scoringAbility'] != '' &&
            player['defensiveSkills'] != '' &&
            player['speedAndAgility'] != '' &&
            player['shootingRange'] != '' &&
            player['reboundSkills'] != '';
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

  DataRow buildDataRow(Map<String, dynamic> player) {
    return DataRow(cells: [
      DataCell(Text(
        player['username'],
        style: TextStyle(
          color: Colors.green,
          fontWeight: FontWeight.bold,
        ),
      )),
      DataCell(
        buildTextField(player, 'skillLevel'),
      ),
      DataCell(
        buildTextField(player, 'scoringAbility'),
      ),
      DataCell(
        buildTextField(player, 'defensiveSkills'),
      ),
      DataCell(
        buildTextField(player, 'speedAndAgility'),
      ),
      DataCell(
        buildTextField(player, 'shootingRange'),
      ),
      DataCell(
        buildTextField(player, 'reboundSkills'),
      ),
    ]);
  }

  Widget buildTextField(Map<String, dynamic> player, String field) {
    return TextFormField(
      initialValue: player[field].toString(),
      keyboardType: TextInputType.number,
      style: TextStyle(
        color: Colors.green,
        fontWeight: FontWeight.bold,
      ),
      decoration: InputDecoration(
        hintText: '🙄',
        hintStyle: TextStyle(color: Colors.green.withOpacity(0.5)),
        border: InputBorder.none, // Remove the default border
        filled: true,
        fillColor: Colors.white.withOpacity(0.2), // Semi-transparent background
        contentPadding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      ),
      onChanged: (value) {
        setState(() {
          player[field] = value.isNotEmpty ? int.tryParse(value) ?? 0 : 0;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Grade Page')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('$user 🏀 your grades are shown here 🏀')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(height: 10),
            Text(
              'Enter a number between 1 and 10 or use the arrow keys. Only players with a valid grade will be submitted.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black, // Adjust color if needed
              ),
            ),
            SizedBox(height: 10),
            // DataTable without borders
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 12.0,
                headingRowHeight: 40.0,
                dataRowHeight: 60.0,
                // Remove borders by not specifying decoration
                columns: [
                  DataColumn(
                    label: Text(
                      'Username',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Playmaker',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Scoring Ability',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Defensive Skills',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Speed and Agility',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      '3 pt Shooting',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Rebound Skills',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
                rows: grading.map((player) => buildDataRow(player)).toList(),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: submitGrading,
              child: Text('Submit'),
            ),
            SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Text(
                    'רכז (playmaker): שחקן שטוב ביצירת הזדמנויות קליעה לעצמו או לחבריו לקבוצה, לרוב באמצעות מסירה או כדרור.',
                  ),
                  SizedBox(height: 5),
                  Text(
                    'יכולת קליעה (scoring ability): היכולת לקלוע סל באופן כללי מכל עמדות על המגרש, באמצעות מגוון של תנועות התקפיות.',
                  ),
                  SizedBox(height: 5),
                  Text(
                    'מיומנויות הגנה (defensive skills): היכולת למנוע מהיריב לקלוע, באמצעות טכניקות כגון חסימת זריקות, חטיפה של הכדור, ועמידה טובה במקום.',
                  ),
                  SizedBox(height: 5),
                  Text(
                    'מהירות וזריזות (speed and agility): היכולת לנוע מהר ולשנות כיוון בקלות, דבר המסייע גם במצבים ההתקפיים וגם במצבים ההגנתיים.',
                  ),
                  SizedBox(height: 5),
                  Text(
                    'קליעה לשלוש (3 pt shooting): היכולת לקלוע מעבר לקשת השלוש.',
                  ),
                  SizedBox(height: 5),
                  Text(
                    'ריבאונד (rebound skills): היכולת לקחת ריבאונד בהתקפה ובהגנה.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
