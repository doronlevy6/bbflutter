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
      appBar: AppBar(
        title: Text('Team Management'),
      ),
      body: Container(
        padding: EdgeInsets.all(16.0),
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
                    ElevatedButton(
                      onPressed: _enlistForGame,
                      child: Text('Enlist for Next Game'),
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Enlisted Players',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green),
                    ),
                    SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: enlistedPlayers.length,
                        itemBuilder: (context, index) {
                          return ListTile(
                            title: Text(
                              enlistedPlayers[index],
                              style: TextStyle(color: Colors.green),
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Players: ${enlistedPlayers.length}',
                      style: TextStyle(
                          color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: 20), // Space between columns
            // Right Column: Teams and Averages (70%)
            Expanded(
              flex: 7, // 70% of the width
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Teams and Averages',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green),
                  ),
                  SizedBox(height: 10),
                  Expanded(
                    child: teams.isNotEmpty
                        ? ListView.builder(
                      itemCount: teams.length,
                      itemBuilder: (context, teamIndex) {
                        List<Player> team = teams[teamIndex];

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
                              averages['skillLevel']! + player.skillLevel;
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

                        return Container(
                          margin: EdgeInsets.symmetric(vertical: 10),
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.green),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Team Members
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Team ${teamIndex + 1}',
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green),
                                    ),
                                    SizedBox(height: 5),
                                    ...team.map((player) {
                                      return Text(
                                        player.username,
                                        style:
                                        TextStyle(color: Colors.green),
                                      );
                                    }).toList(),
                                  ],
                                ),
                              ),
                              SizedBox(width: 10),
                              // Averages
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Averages:',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green),
                                    ),
                                    SizedBox(height: 5),
                                    Text(
                                      'Playmaker: ${averages['skillLevel']!.toStringAsFixed(2)}',
                                      style:
                                      TextStyle(color: Colors.green),
                                    ),
                                    Text(
                                      'Scoring Ability: ${averages['scoringAbility']!.toStringAsFixed(2)}',
                                      style:
                                      TextStyle(color: Colors.green),
                                    ),
                                    Text(
                                      'Defensive Skills: ${averages['defensiveSkills']!.toStringAsFixed(2)}',
                                      style:
                                      TextStyle(color: Colors.green),
                                    ),
                                    Text(
                                      'Speed and Agility: ${averages['speedAndAgility']!.toStringAsFixed(2)}',
                                      style:
                                      TextStyle(color: Colors.green),
                                    ),
                                    Text(
                                      '3 pt Shooting: ${averages['shootingRange']!.toStringAsFixed(2)}',
                                      style:
                                      TextStyle(color: Colors.green),
                                    ),
                                    Text(
                                      'Rebound Skills: ${averages['reboundSkills']!.toStringAsFixed(2)}',
                                      style:
                                      TextStyle(color: Colors.green),
                                    ),
                                    SizedBox(height: 5),
                                    Text(
                                      'Total Averages Sum: ${totalAverages.toStringAsFixed(2)}',
                                      style:
                                      TextStyle(color: Colors.green),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    )
                        : Center(
                      child: Text(
                        'No teams created.',
                        style: TextStyle(color: Colors.green),
                      ),
                    ),
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
