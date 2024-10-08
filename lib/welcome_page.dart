// lib/welcome_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/model/player.dart'; // Adjust the path accordingly
import 'services/api_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class WelcomePage extends StatefulWidget {
  final bool showOnlyTeams;

  WelcomePage({this.showOnlyTeams = false});

  @override
  _WelcomePageState createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final ApiService _apiService = ApiService();
  List<List<Player>> teams = [];
  List<String> enlistedPlayers = [];
  String user = '';
  late IO.Socket socket;

  @override
  void initState() {
    super.initState();
    _initializeUser();
    _fetchData();
    _setupSocketListener();
  }

  @override
  void dispose() {
    socket.dispose();
    super.dispose();
  }

  Future<void> _initializeUser() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      user = prefs.getString('user') ?? '';
    });
  }

  Future<void> _fetchData() async {
    try {
      final enlistResponse = await _apiService.get('enlist');
      if (enlistResponse['success']) {
        setState(() {
          enlistedPlayers = List<String>.from(enlistResponse['usernames']);
        });
      }

      final teamsResponse = await _apiService.get('get-teams');
      if (teamsResponse['success']) {
        setState(() {
          teams = (teamsResponse['teams'] as List)
              .map<List<Player>>((team) => (team as List)
              .map<Player>((playerData) => Player.fromJson(playerData))
              .toList())
              .toList();
        });
      }
    } catch (error) {
      print('Error fetching data: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching data. Please try again later.')),
      );
    }
  }

  Future<void> _enlistForGame() async {
    try {
      final response = await _apiService.post('enlist-users', {
        'usernames': [user],
      });

      if (response['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You have been enlisted for the next game!')),
        );
        _fetchData();
      } else {
        throw Exception('Failed to enlist');
      }
    } catch (error) {
      print('Error enlisting: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to enlist for the next game.')),
      );
    }
  }

  void _setupSocketListener() {
    socket = IO.io(_apiService.apiUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket.connect();

    socket.on('connect', (_) {
      print('Connected to socket.io server');
    });

    socket.on('teamsUpdated', (_) {
      _fetchData();
    });

    socket.on('disconnect', (_) {
      print('Disconnected from socket.io server');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Removed AppBar as per the user's request
      body: Padding(
        padding: EdgeInsets.all(12.0), // Reduced padding for compactness
        child: Column(
          children: [
            // Main Content: Enlisted Players and Teams
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Column: Enlisted Players (30%)
                  Expanded(
                    flex: 3, // 30% of the width
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!widget.showOnlyTeams) ...[
                          EnlistButton(onPressed: _enlistForGame),
                          SizedBox(height: 10), // Reduced spacing
                          // Removed 'Enlisted Players' Text
                          // Moved 'Total Enlisted' to replace the 'Enlisted Players' label
                          Text(
                            'Total Enlisted: ${enlistedPlayers.length}',
                            style: TextStyle(
                                color: Colors.green[800],
                                fontWeight: FontWeight.bold,
                                fontSize: 14), // Smaller font
                          ),
                          SizedBox(height: 8), // Reduced spacing
                          Expanded(
                            child: enlistedPlayers.isNotEmpty
                                ? ListView.builder(
                              itemCount: enlistedPlayers.length,
                              itemBuilder: (context, index) {
                                return Card(
                                  elevation: 1, // Reduced elevation
                                  margin: EdgeInsets.symmetric(
                                      vertical: 1), // Reduced margin
                                  child: ListTile(
                                    leading: Icon(Icons.person,
                                        color: Colors.green[700],
                                        size: 20), // Smaller icon
                                    title: Text(
                                      enlistedPlayers[index],
                                      style: TextStyle(
                                          color: Colors.green[700],
                                          fontSize: 14), // Smaller font
                                      overflow:
                                      TextOverflow.ellipsis, // Ensure single line
                                    ),
                                  ),
                                );
                              },
                            )
                                : Center(
                              child: Text(
                                'No players enlisted.',
                                style: TextStyle(
                                    color: Colors.green[700],
                                    fontSize: 14), // Smaller font
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: 12), // Reduced space between columns
                  // Right Column: Teams and Averages (70%)
                  Expanded(
                    flex: 7, // 70% of the width
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                       Expanded(
                          child: teams.isNotEmpty
                              ? ListView.builder(
                            itemCount: teams.length,
                            itemBuilder: (context, teamIndex) {
                              List<Player> team = teams[teamIndex];

                              // Calculate Averages
                              Map<String, double> averages = {
                                'skillLevel': 0.0,
                                'scoringAbility': 0.0,
                                'defensiveSkills': 0.0,
                                'speedAndAgility': 0.0,
                                'shootingRange': 0.0,
                                'reboundSkills': 0.0,
                              };

                              for (var player in team) {
                                averages['skillLevel'] =
                                    averages['skillLevel']! +
                                        player.skillLevel;
                                averages['scoringAbility'] =
                                    averages['scoringAbility']! +
                                        player.scoringAbility;
                                averages['defensiveSkills'] =
                                    averages['defensiveSkills']! +
                                        player.defensiveSkills;
                                averages['speedAndAgility'] =
                                    averages['speedAndAgility']! +
                                        player.speedAndAgility;
                                averages['shootingRange'] =
                                    averages['shootingRange']! +
                                        player.shootingRange;
                                averages['reboundSkills'] =
                                    averages['reboundSkills']! +
                                        player.reboundSkills;
                              }

                              averages.updateAll(
                                      (key, value) => value / team.length);

                              double totalAverages =
                              averages.values.reduce((a, b) => a + b);

                              return TeamCard(
                                teamName: 'Team ${team.isNotEmpty ? team.first.username : 'Team ${teamIndex + 1}'}',
                                players:team.map((p) => p.username).toList(),
                                averages: averages,
                                totalAverages: totalAverages,
                              );
                            },
                          )
                              : Center(
                            child: Text(
                              'No teams created.',
                              style: TextStyle(
                                  color: Colors.green[700],
                                  fontSize: 14), // Smaller font
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12), // Reduced spacing
            // Legend Section
            Legend(),
          ],
        ),
      ),
    );
  }
}

// Enlist Button Widget
class EnlistButton extends StatelessWidget {
  final VoidCallback onPressed;

  EnlistButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: CircleAvatar(
        radius: 15, // Half of the original height and width (30)
        backgroundImage: AssetImage('assets/images/basketball.jpeg'),
        backgroundColor: Colors.transparent, // Optional: Makes the background transparent
      ),
      label: Text(
        'Enlist for Next Game',
        style: TextStyle(
          fontSize: 12, // Smaller font
          fontWeight: FontWeight.bold,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green[700], // Button background color
        foregroundColor: Colors.white, // Button text color
        padding:
        EdgeInsets.symmetric(horizontal: 5, vertical: 3), // Reduced padding
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 3, // Reduced elevation
      ),
    );
  }
}

// Team Card Widget with Separate Columns for Team Info and Averages
class TeamCard extends StatelessWidget {
  final String teamName;
  final List<String> players;
  final Map<String, double> averages;
  final double totalAverages;

  TeamCard({
    required this.teamName,
    required this.players,
    required this.averages,
    required this.totalAverages,
  });

  @override
  Widget build(BuildContext context) {
    // Define the order and labels for the parameters
    final parameters = [
      {
        'icon': Icons.handshake,
        'label': 'Skill Level',
        'value': averages['skillLevel']!.toStringAsFixed(2)
      },
      {
        'icon': Icons.score,
        'label': 'Scoring Ability',
        'value': averages['scoringAbility']!.toStringAsFixed(2)
      },
      {
        'icon': Icons.shield,
        'label': 'Defensive Skills',
        'value': averages['defensiveSkills']!.toStringAsFixed(2)
      },
      {
        'icon': Icons.speed,
        'label': 'Speed & Agility',
        'value': averages['speedAndAgility']!.toStringAsFixed(2)
      },
      {
        'icon': Icons.sports_basketball,
        'label': 'Shooting Range',
        'value': averages['shootingRange']!.toStringAsFixed(2)
      },
      {
        'icon': Icons.grain,
        'label': 'Rebound Skills',
        'value': averages['reboundSkills']!.toStringAsFixed(2)
      },
      {
        'icon': Icons.calculate,
        'label': 'Total Averages Sum',
        'value': (totalAverages / 6).toStringAsFixed(2)
      },
    ];

    return Card(
      color: Colors.green[50],
      elevation: 3, // Reduced elevation
      margin: EdgeInsets.symmetric(vertical: 6), // Reduced vertical margin
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10), // Slightly smaller radius
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0), // Reduced padding
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Column: Team Name and Players
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Team Header
                  Row(
                    children: [
                      Icon(Icons.group, color: Colors.green[700], size: 20), // Smaller icon
                      SizedBox(width: 8), // Reduced spacing
                      Flexible(
                        child: Text(
                          teamName,
                          style: TextStyle(
                              fontSize: 16, // Smaller font
                              fontWeight: FontWeight.bold,
                              color: Colors.green[800]),
                          overflow: TextOverflow.ellipsis, // Adds ellipsis (...) if text overflows
                          maxLines: 1, // Restricts text to a single line
                        ),
                      ),

                    ],
                  ),
                  SizedBox(height: 8), // Reduced spacing
                  // Display players directly without 'Players:' label
                  ...players.map((player) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      children: [
                        Icon(Icons.person,
                            color: Colors.green[600], size: 14), // Smaller icon
                        SizedBox(width: 4), // Reduced spacing
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return Text(
                                player,
                                style: TextStyle(
                                    color: Colors.green[700],
                                    fontSize: 12), // Smaller font
                                overflow:
                                TextOverflow.ellipsis, // Single line
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
            SizedBox(width: 12), // Reduced space between columns
            // Right Column: Averages
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Start Averages Display from top
                  // Iterate through parameters and handle 'Total Averages Sum' differently
                  ...parameters.asMap().entries.map((entry) {
                    int idx = entry.key;
                    var param = entry.value;
                    if (param['label'] == 'Total Averages Sum') {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 4), // Small spacing before divider
                          // Shorter Divider
                          Row(
                            children: [
                              Divider(
                                color: Colors.green[700],
                                thickness: 1,
                                indent: 0,
                                endIndent: 8,
                              ),
                              // No text here, just the divider
                            ],
                          ),
                          ParameterRow(
                            icon: param['icon'] as IconData,
                            tooltip: param['label'] as String,
                            value: param['value'] as String,
                            isTotal: true, // Indicate that this is the total
                          ),
                        ],
                      );
                    } else {
                      return ParameterRow(
                        icon: param['icon'] as IconData,
                        tooltip: param['label'] as String,
                        value: param['value'] as String,
                      );
                    }
                  }).toList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Parameter Row Widget with Icon and Value
class ParameterRow extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final String value;
  final bool isTotal;

  ParameterRow({
    required this.icon,
    required this.tooltip,
    required this.value,
    this.isTotal = false, // Default to false
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Row(
        children: [
          Icon(
            icon,
            color: Colors.green[700],
            size: 16, // Smaller icon
          ),
          SizedBox(width: 4), // Reduced spacing
          Expanded(
            child: Text(
              '$value',
              style: TextStyle(
                color: Colors.green[700],
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal, // Bolder if total
                fontSize: 12, // Smaller font
              ),
              overflow: TextOverflow.ellipsis, // Single line
            ),
          ),
        ],
      ),
    );
  }
}

// Legend Widget
class Legend extends StatelessWidget {
  // Define the legend items
  final List<Map<String, dynamic>> legendItems = [
    {'icon': Icons.handshake, 'label': 'Skill Level'},
    {'icon': Icons.score, 'label': 'Scoring Ability'},
    {'icon': Icons.shield, 'label': 'Defensive Skills'},
    {'icon': Icons.speed, 'label': 'Speed & Agility'},
    {'icon': Icons.sports_basketball, 'label': 'Shooting Range'},
    {'icon': Icons.grain, 'label': 'Rebound Skills'},
    {'icon': Icons.calculate, 'label': 'Team Average'},
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.green[50],
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10), // Slightly smaller radius
      ),
      child: Padding(
        padding: const EdgeInsets.all(10.0), // Reduced padding
        child: Wrap(
          spacing: 12, // Reduced spacing
          runSpacing: 8, // Reduced run spacing
          children: legendItems.map((item) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  item['icon'],
                  color: Colors.green[700],
                  size: 16, // Smaller icon
                ),
                SizedBox(width: 4), // Reduced spacing
                Text(
                  item['label'],
                  style: TextStyle(
                    color: Colors.green[700],
                    fontWeight: FontWeight.bold, // Made text bolder
                    fontSize: 12, // Smaller font
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
