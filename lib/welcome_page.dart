import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/model/player.dart'; // Adjust the path accordingly
import 'legend_page.dart';
import 'services/api_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:responsive_builder/responsive_builder.dart'; // Import responsive_builder

// Define keys for SharedPreferences
const String kUserKey = 'user';
const String kEnlistedPlayersKey = 'enlistedPlayers';

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
      user = prefs.getString(kUserKey) ?? '';
      enlistedPlayers = prefs.getStringList(kEnlistedPlayersKey) ?? [];
    });
  }

  Future<void> _saveEnlistedPlayers(List<String> players) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(kEnlistedPlayersKey, players);
  }

  Future<void> _fetchData() async {
    try {
      final enlistResponse = await _apiService.get('enlist');
      if (enlistResponse['success']) {
        List<String> fetchedPlayers = List<String>.from(enlistResponse['usernames']);
        setState(() {
          enlistedPlayers = fetchedPlayers;
        });
        await _saveEnlistedPlayers(fetchedPlayers); // Save to SharedPreferences
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
        await _fetchData(); // Fetch and save the updated enlistedPlayers
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

    // Example of handling enlistedPlayers update via socket
    socket.on('enlistedPlayersUpdated', (data) {
      if (data['success']) {
        List<String> updatedPlayers = List<String>.from(data['usernames']);
        setState(() {
          enlistedPlayers = updatedPlayers;
        });
        _saveEnlistedPlayers(updatedPlayers);
      }
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
              child: ResponsiveBuilder(
                builder: (context, sizingInformation) {
                  // Determine flex ratios based on device type
                  int playerFlex;
                  int teamFlex;

                  if (sizingInformation.deviceScreenType == DeviceScreenType.mobile) {
                    playerFlex = 4;
                    teamFlex = 6;
                  } else if (sizingInformation.deviceScreenType == DeviceScreenType.tablet) {
                    playerFlex = 3;
                    teamFlex = 7;
                  } else {
                    // Desktop and others
                    playerFlex = 3;
                    teamFlex = 7;
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column: Enlisted Players
                      Expanded(
                        flex: playerFlex,
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
                                        contentPadding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0), // Further reduced padding
                                        visualDensity: VisualDensity.compact,
                                        leading: Icon(Icons.person,
                                            color: Colors.green[700],
                                            size: 16), // Smaller icon
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
                      // Right Column: Teams and Averages
                      Expanded(
                        flex: teamFlex,
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
                                    teamName:
                                    'Team ${team.isNotEmpty ? team.first.username : (teamIndex + 1)}',
                                    players:
                                    team.map((p) => p.username).toList(),
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
                  );
                },
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
        radius: 20, // Half of the original height and width (30)
        backgroundImage: AssetImage('assets/images/basketball.jpeg'),
        backgroundColor: Colors.transparent, // Optional: Makes the background transparent
      ),
      label: Text(
        'Play Next Game',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 16, // Smaller font
          fontWeight: FontWeight.bold,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green[700], // Button background color
        foregroundColor: Colors.white, // Button text color
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10), // Adjust padding for a rounder look
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30), // More rounded shape
        ),
        elevation: 5, // Default elevation
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
        'label': 'Team Average',
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
              flex: 7, // Increased flex to make left column wider
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Team Header
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          teamName,
                          style: TextStyle(
                            fontSize: 16, // Smaller font
                            fontWeight: FontWeight.bold,
                            color: Colors.green[800],
                          ),
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
                                  fontSize: 12, // Smaller font
                                ),
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
              flex: 3, // Decreased flex to make right column narrower
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Start Averages Display from top
                  // Iterate through parameters and handle 'Team Average' differently
                  ...parameters.asMap().entries.map((entry) {
                    int idx = entry.key;
                    var param = entry.value;
                    if (param['label'] == 'Team Average') {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 4), // Small spacing before divider
                          // Shorter Divider
                          Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: Colors.green[700],
                                  thickness: 1,
                                  indent: 0,
                                  endIndent: 4, // Adjust endIndent to shorten divider
                                ),
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
  @override
  Widget build(BuildContext context) {
    // Your existing Legend implementation
    return Container(
      // Placeholder for the Legend widget
      child: Text(
        'Legend goes here',
        style: TextStyle(color: Colors.green[700]),
      ),
    );
  }
}
