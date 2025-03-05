import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../managers/asset_manager.dart';
import '/model/player.dart'; // Adjust the path accordingly
import 'legend_page.dart';
import '../services/api_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:responsive_builder/responsive_builder.dart';

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

  bool _isHebrew = false;
  late IO.Socket socket;

  String _teamImagePath = 'assets/images/basketball.png';

  @override
  void initState() {
    super.initState();
    _initializeUser();
    _loadLanguage();
    _setupSocketListener();
    _loadRankingsData();
    _loadTeamImage();

  }

  @override
  void dispose() {
    socket.dispose();
    super.dispose();
  }

  Future<void> _loadTeamImage() async {
    String imagePath = await AssetManager.getTeamImageFromCache();
    setState(() {
      _teamImagePath = imagePath;
    });
  }
  // Load the language setting from SharedPreferences using key 'isHebrew'
  Future<void> _loadLanguage() async {
    String imagePath = await AssetManager.getTeamImageFromCache();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isHebrew = prefs.getBool('isHebrew') ?? false;
    setState(() {
      _isHebrew = isHebrew;
    });
  }

  // Load ranking data from SharedPreferences
  Future<void> _loadRankingsData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      String? overallPlayersRankingsString = prefs.getString(kOverallPlayersRankingsKey);
      if (overallPlayersRankingsString != null && overallPlayersRankingsString.isNotEmpty) {
        overallPlayersRankings = List<Map<String, dynamic>>.from(jsonDecode(overallPlayersRankingsString));
      } else {
        overallPlayersRankings = [];
      }
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
        await _saveEnlistedPlayers(fetchedPlayers);
      }
      // Uncomment and adjust if teams data is needed:
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
        SnackBar(content: Text(_isHebrew ? 'שגיאה בטעינת הנתונים. אנא נסה שוב מאוחר יותר.' : 'Error fetching data. Please try again later.')),
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
          SnackBar(content: Text(_isHebrew ? 'נרשמת למשחק הבא!' : 'You have been enlisted for the next game!')),
        );
        await _fetchData();
      } else {
        throw Exception('Failed to enlist');
      }
    } catch (error) {
      print('Error enlisting: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isHebrew ? 'נכשלת ברישום למשחק הבא.' : 'Failed to enlist for the next game.')),
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
    // Define localized text strings
    String playNextGameText = _isHebrew ? 'שחק במשחק הבא' : 'Play Next Game';
    String totalEnlistedText = _isHebrew ? 'סה"כ רשומים: ' : 'Total Enlisted: ';
    String noPlayersText = _isHebrew ? 'אין שחקנים רשומים.' : 'No players enlisted.';

    // Build greeting message based on enrollment status
    String greetingMessage;
    if (enlistedPlayers.contains(user)) {
      int index = enlistedPlayers.indexOf(user);
      if (index < 12) {
        greetingMessage = _isHebrew
            ? 'שלום $user, אתה משחק במשחק הבא!'
            : 'Hello $user, you\'re playing in the next game!';
      } else {
        greetingMessage = _isHebrew
            ? 'שלום $user, אתה בהמתנה.\nאנא הישאר זמין לעדכונים.'
            : 'Hello $user, you are on standby.\nPlease stay available for updates.';
      }
    } else {
      if (enlistedPlayers.length < 12) {
        greetingMessage = _isHebrew
            ? 'שלום $user, כדי להירשם למשחק הבא, לחץ על כפתור "$playNextGameText".'
            : 'Hello $user, to sign up for the next game, please click the "$playNextGameText" button.';
      } else if (enlistedPlayers.length >= 12) {
        greetingMessage = _isHebrew
            ? 'שלום $user, לחץ על "$playNextGameText" כדי להצטרף לרשימת ההמתנה.'
            : 'Hello $user, click the "$playNextGameText" button to join the standby list.';
      } else {
        greetingMessage = _isHebrew ? 'שלום $user!' : 'Hello $user!';
      }
    }

    int totalPlayers = overallPlayersRankings.length;
    int ratedPlayers = playersRankings.length;
    int remaining = totalPlayers - ratedPlayers;
    String ratingMessage = _isHebrew
        ? 'דירגת $ratedPlayers שחקנים. אנא דרג עוד $remaining שחקנים.'
        : 'You have rated $ratedPlayers players. Please rate $remaining more players.';

    return Directionality(
      textDirection: _isHebrew ? TextDirection.rtl : TextDirection.ltr,
      child: Stack(
        children: [
          // רקע עם תמונת ball-logo.png שקופה
          Opacity(
            opacity: 0.2,
            child: Image.asset(
              'assets/images/reka.webp',
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            body: Padding(
              padding: EdgeInsets.all(12.0),
              child: Column(
                children: [
                  Expanded(
                    child: ResponsiveBuilder(
                      builder: (context, sizingInformation) {
                        int playerFlex;
                        int greetingFlex;
                        if (sizingInformation.deviceScreenType == DeviceScreenType.mobile) {
                          playerFlex = 4;
                          greetingFlex = 6;
                        } else if (sizingInformation.deviceScreenType == DeviceScreenType.tablet) {
                          playerFlex = 3;
                          greetingFlex = 7;
                        } else {
                          playerFlex = 3;
                          greetingFlex = 7;
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: playerFlex,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!widget.showOnlyTeams) ...[
                                    EnlistButton(
                                      onPressed: _enlistForGame,
                                      buttonText: playNextGameText,
                                      imagePath: _teamImagePath,
                                    ),
                                    SizedBox(height: 10),
                                    Text(
                                      '$totalEnlistedText${enlistedPlayers.length}',
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
                                              contentPadding: EdgeInsets.symmetric(horizontal: 4.0),
                                              visualDensity: VisualDensity(horizontal: -4, vertical: -4),
                                              minVerticalPadding: 0,
                                              dense: true,
                                              leading: Padding(
                                                padding: EdgeInsets.only(left: 2.0),
                                                child: Icon(
                                                  Icons.person,
                                                  color: Colors.green[700],
                                                  size: 16,
                                                ),
                                              ),
                                              horizontalTitleGap: 5.0,
                                              title: Text(
                                                enlistedPlayers[index],
                                                style: TextStyle(
                                                  color: Colors.green[700],
                                                  fontSize: 14,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          );
                                        },
                                      )
                                          : Center(
                                        child: Text(
                                          noPlayersText,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Enlist Button Widget with customizable text
class EnlistButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String buttonText;
  final String imagePath;

  EnlistButton({required this.onPressed, required this.buttonText,required this.imagePath,});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: CircleAvatar(
        radius: 20,
        backgroundImage: AssetImage(imagePath),
        backgroundColor: Colors.transparent,
      ),
      label: Text(
        buttonText,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,

        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green[100],
        foregroundColor: Colors.green,
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        elevation: 5,
      ),
    );
  }
}
