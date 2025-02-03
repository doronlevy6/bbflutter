import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/model/player.dart'; // Adjust the path accordingly
import 'legend_page.dart';
import '../services/api_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:responsive_builder/responsive_builder.dart'; // Import responsive_builder

// Define keys for SharedPreferences
const String kUserKey = 'user';
const String kEnlistedPlayersKey = 'enlistedPlayers';
const String kOverallPlayersRankingsKey = 'overallPlayersRankings';
const String kPlayersRankingsKey = 'playersRankings';

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
  List<Map<String, dynamic>> overallPlayersRankings = [];
  List<Map<String, dynamic>> playersRankings = [];

  late IO.Socket socket;

  @override
  void initState() {
    super.initState();
    _initializeUser();
    _fetchData();
    _setupSocketListener();
    _loadRankingsData();
  }

  @override
  void dispose() {
    socket.dispose();
    super.dispose();
  }
// This function loads both ranking keys from cache
  Future<void> _loadRankingsData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      // Decode overallPlayersRankings from JSON string into a list of maps.
      String? overallPlayersRankingsString = prefs.getString(kOverallPlayersRankingsKey);
      if (overallPlayersRankingsString != null && overallPlayersRankingsString.isNotEmpty) {
        overallPlayersRankings = List<Map<String, dynamic>>.from(jsonDecode(overallPlayersRankingsString));
      } else {
        overallPlayersRankings = [];
      }

      // Build the user-specific key for playersRankings.
      String userPlayersRankingsKey = 'playersRankings_$user';
      String? playersRankingsString = prefs.getString(userPlayersRankingsKey);
      if (playersRankingsString != null && playersRankingsString.isNotEmpty) {
        playersRankings = List<Map<String, dynamic>>.from(jsonDecode(playersRankingsString));
      } else {
        playersRankings = [];
      }
    });
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

      // final teamsResponse = await _apiService.get('get-teams');
      // if (teamsResponse['success']) {
      //   setState(() {
      //     teams = (teamsResponse['teams'] as List)
      //         .map<List<Player>>((team) => (team as List)
      //         .map<Player>((playerData) => Player.fromJson(playerData))
      //         .toList())
      //         .toList();
      //   });
      // }
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

// Inside _WelcomePageState, within the build() method where the greeting is displayed:

  // בתוך הפונקציה build() של _WelcomePageState:

  @override
  Widget build(BuildContext context) {
    // Determine the greeting message based on the user's enrollment status and the number of enlisted players.
    String greetingMessage;
    if (enlistedPlayers.contains(user)) {
      int index = enlistedPlayers.indexOf(user);
      if (index < 12) {
        greetingMessage = 'Hello $user, you\'re playing in the next game!';
      } else {
        greetingMessage =
        'Hello $user, you are on standby.\nPlease stay available for updates.';
      }
    } else {
      if (enlistedPlayers.length < 12) {
        greetingMessage =
        'Hello $user, to sign up for the next game, please click the "Play Next Game" button.';
      } else if (enlistedPlayers.length >= 12) {
        greetingMessage =
        'Hello $user, click the "Play Next Game" button to join the standby list.';
      } else {
        greetingMessage = 'Hello $user!';
      }
    }
/// Calculate the rating message using the ranking keys from cache.
    int totalPlayers = overallPlayersRankings.length;
    int ratedPlayers = playersRankings.length; // Use the total number of items in playersRankings
    int remaining = totalPlayers - ratedPlayers;
    String ratingMessage = 'You have rated $ratedPlayers players. Please rate $remaining more players.';




    return Scaffold(
      // AppBar removed as per the user’s request.
      body: Padding(
        padding: EdgeInsets.all(12.0), // Reduced padding for compactness.
        child: Column(
          children: [
            // Main Content: Enlisted Players and Greeting Message.
            Expanded(
              child: ResponsiveBuilder(
                builder: (context, sizingInformation) {
                  // Determine flex ratios based on the device type.
                  int playerFlex;
                  int greetingFlex;

                  if (sizingInformation.deviceScreenType == DeviceScreenType.mobile) {
                    playerFlex = 4;
                    greetingFlex = 6;
                  } else if (sizingInformation.deviceScreenType == DeviceScreenType.tablet) {
                    playerFlex = 3;
                    greetingFlex = 7;
                  } else {
                    // For desktop and others.
                    playerFlex = 3;
                    greetingFlex = 7;
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column: Enlisted Players list.
                      Expanded(
                        flex: playerFlex,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!widget.showOnlyTeams) ...[
                              EnlistButton(onPressed: _enlistForGame),
                              SizedBox(height: 10),
                              Text(
                                'Total Enlisted: ${enlistedPlayers.length}',
                                style: TextStyle(
                                    color: Colors.green[800],
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14),
                              ),
                              SizedBox(height: 8),
                              Expanded(
                                child: enlistedPlayers.isNotEmpty
                                    ? ListView.builder(
                                  itemCount: enlistedPlayers.length,
                                  itemBuilder: (context, index) {
                                    return Card(
                                      elevation: 1,
                                      margin: EdgeInsets.symmetric(vertical: 1),
                                      child: ListTile(
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8.0, vertical: 2.0),
                                        visualDensity: VisualDensity.compact,
                                        leading: Icon(
                                          Icons.person,
                                          color: Colors.green[700],
                                          size: 16,
                                        ),
                                        title: Text(
                                          enlistedPlayers[index],
                                          style: TextStyle(
                                              color: Colors.green[700],
                                              fontSize: 14),
                                          overflow: TextOverflow.ellipsis,
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
                                        fontSize: 14),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(width: 12),
                      // Right Column: Greeting Message.
                      // Right Column: Greeting and Rating Messages.
                      Expanded(
                        flex: greetingFlex,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                greetingMessage,
                                style: TextStyle(
                                  color: Colors.green[800],
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 20),
                              Text(
                                ratingMessage,
                                style: TextStyle(
                                  color: Colors.green[800],
                                  fontSize: 18,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),

                    ],
                  );
                },
              ),
            ),
            SizedBox(height: 12),
            // Legend Section (as defined earlier).
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
        style: TextStyle(
          fontSize: 16, // Smaller font
          fontWeight: FontWeight.bold,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green[100], // Button background color
        foregroundColor: Colors.green, // Button text color
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4), // Adjust padding for a rounder look
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30), // More rounded shape
        ),
        elevation: 5, // Default elevation
      ),
    );
  }
}
