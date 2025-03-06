import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../config/legend_config.dart';
import '../managers/asset_manager.dart';
import '../widgets/icon_butten_with_label.dart';
import '../model/player.dart'; // Adjust the path according to your project structure.
import 'legend_page.dart'; // Assuming you have a Legend widget similar to WelcomePage
import 'package:responsive_builder/responsive_builder.dart';


// Define keys for SharedPreferences
const String kEnlistedPlayersKey = 'enlistedPlayers';
const String kSelectedPlayersKey = 'selectedPlayers';
const String kOverallPlayersRankingsKey = 'overallPlayersRankings';

class PlayGround extends StatefulWidget {
  const PlayGround({Key? key}) : super(key: key);

  @override
  _PlayGroundState createState() => _PlayGroundState();
}

class _PlayGroundState extends State<PlayGround> {
  // Variables to hold both user-specific and overall rankings
  String? _userName;
  String? _userSpecificCacheKey;
  List<Player> _userPlayers = [];
  List<Player> _overallPlayers = [];
  List<Player> _players = []; // This will be the active list based on user choice
  List<Player> _selectedPlayers = [];
  List<List<Player>> _teams = [];
  String _selectedMethod = '';
  String _teamType ='bb';


  // Variable to track which rankings to use
  bool _useUserRankings = true; // Default to user rankings

  // New variable to track if the user is Doron
  bool _isDoron = false;

  // Language flag
  bool _isHebrew = false;

  String _teamImagePath = 'assets/images/default.png';
  @override
  void initState() {
    super.initState();
    _loadLanguage();
    _loadPlayersFromLocalStorage();
    _loadTeamImage();
    _loadTeamType();
  }

  Future<void> _loadTeamType() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String cachedTeamType = prefs.getString('team_type') ?? 'bb';
    setState(() {
      _teamType = cachedTeamType;
    });
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
  // Load both user-specific and overall player rankings
  Future<void> _loadPlayersFromLocalStorage() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _userName = prefs.getString('user'); // Retrieve the current username

    if (_userName != null) {
      _isDoron = _userName!.toLowerCase() == 'doron';
      if (_isDoron) {
        _userSpecificCacheKey = 'playersRankings_$_userName';
        String? userJsonString = prefs.getString(_userSpecificCacheKey!);
        if (userJsonString != null) {
          List<dynamic> userJsonData = jsonDecode(userJsonString);
          _userPlayers = userJsonData.map((data) => Player.fromJson(data)).toList();
        } else {
          print('No player rankings data found for user $_userName in local storage.');
        }
      }
    } else {
      print('No username found in SharedPreferences.');
    }

    // Load overall player rankings
    String? overallJsonString = prefs.getString(kOverallPlayersRankingsKey);
    if (overallJsonString != null) {
      List<dynamic> overallJsonData = jsonDecode(overallJsonString);
      _overallPlayers = overallJsonData.map((data) => Player.fromJson(data)).toList();
    } else {
      print('No overall player rankings data found in local storage.');
    }

    setState(() {
      if (_isDoron) {
        _useUserRankings = true;
        _players = _useUserRankings ? _userPlayers : _overallPlayers;
      } else {
        _useUserRankings = false;
        _players = _overallPlayers;
      }
    });

    await _loadSelectedPlayers();
  }

  // Load selected players from SharedPreferences
  Future<void> _loadSelectedPlayers() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? selectedPlayerUsernames = prefs.getStringList(kSelectedPlayersKey);
    if (selectedPlayerUsernames != null && selectedPlayerUsernames.isNotEmpty) {
      setState(() {
        _selectedPlayers = _players
            .where((player) => selectedPlayerUsernames.contains(player.username))
            .toList();
      });
    } else {
      await _loadEnlistedPlayers();
    }
  }

  // Load enlisted players from SharedPreferences and select them (limited to first 12)
  Future<void> _loadEnlistedPlayers() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? enlistedPlayerUsernames = prefs.getStringList(kEnlistedPlayersKey);
    if (enlistedPlayerUsernames != null && enlistedPlayerUsernames.isNotEmpty) {
      List<String> limitedEnlisted = enlistedPlayerUsernames.length > 12
          ? enlistedPlayerUsernames.take(12).toList()
          : enlistedPlayerUsernames;

      if (enlistedPlayerUsernames.length > 12) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isHebrew
                ? 'רק 12 השחקנים הראשונים נבחרו כברירת מחדל.'
                : 'Only the first 12 enlisted players are selected by default.'),
          ),
        );
      }

      setState(() {
        _selectedPlayers = _players
            .where((player) => limitedEnlisted.contains(player.username))
            .toList();
      });
      await _saveSelectedPlayers();
    }
  }

  // Save the current selection of players to SharedPreferences
  Future<void> _saveSelectedPlayers() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> selectedPlayerUsernames =
    _selectedPlayers.map((player) => player.username).toList();
    await prefs.setStringList(kSelectedPlayersKey, selectedPlayerUsernames);
  }

  // Toggle player selection
  void _togglePlayerSelection(Player player) {
    setState(() {
      if (_selectedPlayers.contains(player)) {
        _selectedPlayers.remove(player);
      } else {
        if (_selectedPlayers.length >= 12) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isHebrew
                  ? 'ניתן לבחור עד 12 שחקנים בלבד.'
                  : 'You can select up to 12 players only.'),
            ),
          );
          return;
        }
        _selectedPlayers.add(player);
      }
    });
    _saveSelectedPlayers();
  }

  // Clear all selections
  void _clearSelection() {
    setState(() {
      _selectedPlayers.clear();
      _teams.clear();
      _selectedMethod = '';
    });
    _saveSelectedPlayers();
  }

  // Select all enlisted players
  Future<void> _selectAllEnlistedPlayers() async {
    await _loadEnlistedPlayers();
  }

  // Toggle between user rankings and overall rankings
  void _toggleRankings(bool? value) {
    if (!_isDoron || value == null) return;
    setState(() {
      _useUserRankings = value;
      _players = _useUserRankings ? _userPlayers : _overallPlayers;
      _selectedPlayers.clear();
      _teams.clear();
      _selectedMethod = '';
    });
    _loadSelectedPlayers();
  }

  // Create balanced teams based on selected method and rankings source
  Future<void> _createBalancedTeams({required bool isAttributeBased}) async {
    if (_selectedPlayers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isHebrew
              ? 'אנא בחר שחקנים ליצירת קבוצות.'
              : 'Please select players to create teams.'),
        ),
      );
      return;
    }

    int selectedCount = _selectedPlayers.length;
    List<Player> playersToUse = _selectedPlayers;

    if (selectedCount > 12) {
      playersToUse = _selectedPlayers.take(12).toList();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isHebrew
              ? 'רק 12 השחקנים הראשונים ייעשה בהם שימוש ליצירת הקבוצות.'
              : 'Only the first 12 selected players will be used for team creation.'),
        ),
      );
    } else if (selectedCount >= 9 && selectedCount <= 12) {
      if (selectedCount < 12) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isHebrew
                ? 'נבחרים $selectedCount שחקנים ליצירת הקבוצות.'
                : 'Selecting the first $selectedCount players for team creation.'),
          ),
        );
      }
      playersToUse = selectedCount >= 12 ? _selectedPlayers.take(12).toList() : _selectedPlayers;
    }

    setState(() {
      int numTeams;
      if (playersToUse.length == 12) {
        numTeams = 3;
      } else if (playersToUse.length >= 9 && playersToUse.length <= 11) {
        numTeams = 3;
      } else if (playersToUse.length <= 8) {
        numTeams = playersToUse.length > 4 ? 2 : 1;
      } else {
        return;
      }
      if (isAttributeBased) {
        _teams = distributePlayers(playersToUse, numTeams: numTeams);
        _selectedMethod = _isHebrew ? 'חלוקה מבוססת פרמטרים' : 'Attribute-based Distribution';
      } else {
        _teams = distributePlayersTier(playersToUse, numTeams: numTeams);
        _selectedMethod = _isHebrew ? 'חלוקת דירוג כולל' : 'Total Average Ranking Distribution';
      }
    });
  }

  double computeTotalRanking(Player player) {
    return player.param1 +
        player.param2 +
        player.param3 +
        player.param4 +
        player.param5 +
        player.param6;
  }

  List<List<Player>> distributePlayers(List<Player> players, {required int numTeams}) {
    List<List<Player>> teams = List.generate(numTeams, (_) => []);

    Map<String, double> averages = {
      'param1': 0.0,
      'param2': 0.0,
      'param3': 0.0,
      'param4': 0.0,
      'param5': 0.0,
      'param6': 0.0,
    };

    for (var player in players) {
      averages['param1'] = averages['param1']! + player.param1;
      averages['param2'] = averages['param2']! + player.param2;
      averages['param3'] = averages['param3']! + player.param3;
      averages['param4'] = averages['param4']! + player.param4;
      averages['param5'] = averages['param5']! + player.param5;
      averages['param6'] = averages['param6']! + player.param6;
    }

    averages.updateAll((key, value) => value / players.length);

    double teamScore(List<Player> team, String attr) {
      double score = 0.0;
      for (var player in team) {
        switch (attr) {
          case 'param1':
            score += player.param1;
            break;
          case 'param2':
            score += player.param2;
            break;
          case 'param3':
            score += player.param3;
            break;
          case 'param4':
            score += player.param4;
            break;
          case 'param5':
            score += player.param5;
            break;
          case 'param6':
            score += player.param6;
            break;
        }
      }
      return score;
    }

    for (var player in players) {
      String strongestAttr = 'param1';
      double strongestVal = player.param1;
      Map<String, double> playerAttributes = {
        'param1': player.param1,
        'param2': player.param2,
        'param3': player.param3,
        'param4': player.param4,
        'param5': player.param5,
        'param6': player.param6,
      };

      playerAttributes.forEach((attr, value) {
        if (value > strongestVal) {
          strongestAttr = attr;
          strongestVal = value;
        }
      });

      int bestTeamIndex = -1;
      double bestTeamScore = double.infinity;
      for (int i = 0; i < numTeams; i++) {
        double score = teamScore(teams[i], strongestAttr);
        if (teams[i].length < 4 && score < bestTeamScore) {
          bestTeamIndex = i;
          bestTeamScore = score;
        }
      }

      if (bestTeamIndex >= 0) {
        teams[bestTeamIndex].add(player);
      } else {
        print('No suitable team found for player ${player.username}');
      }
    }

    return teams;
  }

  List<List<Player>> distributePlayersTier(List<Player> players, {required int numTeams}) {
    List<List<Player>> teams = List.generate(numTeams, (_) => []);
    List<Player> sortedPlayers = List.from(players);
    sortedPlayers.sort((a, b) => computeTotalRanking(b).compareTo(computeTotalRanking(a)));

    for (var player in sortedPlayers) {
      int lowestTeamIndex = -1;
      double lowestTeamRanking = double.infinity;
      for (int i = 0; i < numTeams; i++) {
        double teamRanking = teamTotalRanking(teams[i]);
        if (teams[i].length < 4 && teamRanking < lowestTeamRanking) {
          lowestTeamIndex = i;
          lowestTeamRanking = teamRanking;
        }
      }

      if (lowestTeamIndex >= 0) {
        teams[lowestTeamIndex].add(player);
      } else {
        print('No suitable team found for player ${player.username}');
      }
    }

    return teams;
  }

  double teamTotalRanking(List<Player> team) {
    double total = 0.0;
    for (var player in team) {
      total += computeTotalRanking(player);
    }
    return total;
  }

  Future<void> _loadOverallPlayerRankings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString(kOverallPlayersRankingsKey);
    if (jsonString != null) {
      List<dynamic> jsonData = jsonDecode(jsonString);
      setState(() {
        _players = jsonData.map((data) => Player.fromJson(data)).toList();
      });
      await _loadSelectedPlayers();
    } else {
      print('No overall player rankings data found in local storage.');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Localized text strings
    String selectedPlayersText =
    _isHebrew ? 'שחקנים שנבחרו: ' : 'Selected Players: ';
    String noPlayersText =
    _isHebrew ? 'אין שחקנים זמינים.' : 'No players available.';
    String clearText = _isHebrew ? 'נקה' : 'Clear';
    String enlistedText = _isHebrew ? 'נרשמים' : 'Enlisted';
    String parameterText = _isHebrew ? 'לפי עמדה' : 'By Position';
    String totalText = _isHebrew ? 'לפי ממוצע' : 'By Avg';
    String noTeamsText = _isHebrew ? 'לא נוצרו קבוצות.' : 'No teams created.';
    String selectPlayersText = _isHebrew
        ? 'בחר שחקנים וצור קבוצות מאוזנות.'
        : 'Select players and create balanced teams.';

    // Sorting players: selected players first, then not selected, both alphabetically.
    List<Player> sortedPlayers = List.from(_players);
    sortedPlayers.sort((a, b) {
      bool aSelected = _selectedPlayers.contains(a) ;
      bool bSelected = _selectedPlayers.contains(b);
      if (aSelected && !bSelected) {
        return -1;
      } else if (!aSelected && bSelected) {
        return 1;
      } else {
        return a.username.toLowerCase().compareTo(b.username.toLowerCase());
      }
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
                Colors.white.withOpacity(0.2),
                BlendMode.dstATop,
              ),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(12.0),
            child: Column(
              children: [
                Expanded(
                  child: ResponsiveBuilder(
                    builder: (context, sizingInformation) {
                      int playerFlex;
                      int teamFlex;
                      if (sizingInformation.deviceScreenType == DeviceScreenType.mobile) {
                        playerFlex = 4;
                        teamFlex = 6;
                      } else if (sizingInformation.deviceScreenType == DeviceScreenType.tablet) {
                        playerFlex = 3;
                        teamFlex = 7;
                      } else {
                        playerFlex = 3;
                        teamFlex = 7;
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Column: Player Selection
                          Expanded(
                            flex: playerFlex,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(height: 10),
                                Text(
                                  '$selectedPlayersText${_selectedPlayers.length}',
                                  style: TextStyle(
                                    color: Colors.green[800],
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButtonWithLabel(
                                      icon: Icons.refresh,
                                      label: clearText,
                                      onPressed: _clearSelection,
                                    ),
                                    SizedBox(width: 16),
                                    IconButtonWithLabel(
                                      icon: Icons.confirmation_number_outlined,
                                      label: enlistedText,
                                      onPressed: _selectAllEnlistedPlayers,
                                    ),
                                  ],
                                ),
                                SizedBox(height: 12),
                                Expanded(
                                  child: sortedPlayers.isNotEmpty
                                      ? ListView.builder(
                                    itemCount: sortedPlayers.length,
                                    itemBuilder: (context, index) {
                                      Player player = sortedPlayers[index];
                                      bool isSelected = _selectedPlayers.contains(player);
                                      return PlayGroundPlayerListTile(
                                        player: player,
                                        isSelected: isSelected,
                                        onTap: () => _togglePlayerSelection(player),
                                      );
                                    },
                                  )
                                      : Center(
                                    child: Text(
                                      noPlayersText,
                                      style: TextStyle(
                                        color: Colors.green[700],
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 12),
                          // Right Column: Teams Display
                          Expanded(
                            flex: teamFlex,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    PlayGroundTeamMethodButton(
                                      label: parameterText,
                                      imagePath: _teamImagePath,
                                      onPressed: () => _createBalancedTeams(isAttributeBased: true),
                                    ),
                                    SizedBox(width: 16),
                                    PlayGroundTeamMethodButton(
                                      label: totalText,
                                      imagePath: _teamImagePath,
                                      onPressed: () => _createBalancedTeams(isAttributeBased: false),
                                    ),
                                    if (_isDoron) ...[
                                      SizedBox(width: 5),
                                      Icon(
                                        Icons.group,
                                        color: Colors.green[800],
                                        size: 20,
                                      ),
                                      Transform.scale(
                                        scale: 0.7,
                                        child: Switch(
                                          value: _useUserRankings,
                                          onChanged: _toggleRankings,
                                          activeColor: Colors.green,
                                          inactiveThumbColor: Colors.grey,
                                          inactiveTrackColor: Colors.grey[300],
                                        ),
                                      ),
                                      Icon(
                                        Icons.person,
                                        color: Colors.green[800],
                                        size: 20,
                                      ),
                                    ],
                                  ],
                                ),
                                SizedBox(height: 12),
                                Expanded(
                                  child: _teams.isNotEmpty
                                      ? ListView.builder(
                                    itemCount: _teams.length,
                                    itemBuilder: (context, teamIndex) {
                                      List<Player> team = _teams[teamIndex];
                                      Map<String, double> averages = {
                                        'param1': 0.0,
                                        'param2': 0.0,
                                        'param3': 0.0,
                                        'param4': 0.0,
                                        'param5': 0.0,
                                        'param6': 0.0,
                                      };
                                      for (var player in team) {
                                        averages['param1'] = averages['param1']! + player.param1;
                                        averages['param2'] = averages['param2']! + player.param2;
                                        averages['param3'] = averages['param3']! + player.param3;
                                        averages['param4'] = averages['param4']! + player.param4;
                                        averages['param5'] = averages['param5']! + player.param5;
                                        averages['param6'] = averages['param6']! + player.param6;
                                      }
                                      averages.updateAll((key, value) => value / team.length);
                                      double totalAverages = averages.values.reduce((a, b) => a + b);
                                      String teamName = _isHebrew
                                          ? 'קבוצה ${teamIndex + 1}'
                                          : 'Team ${teamIndex + 1}';
                                      return PlayGroundTeamCard(
                                        teamName: teamName,
                                        players: team.map((p) => p.username).toList(),
                                        averages: averages,
                                        totalAverages: totalAverages,
                                        teamType: _teamType,
                                      );
                                    },
                                  )
                                      : Center(
                                    child: Text(
                                      _selectedMethod.isNotEmpty ? noTeamsText : selectPlayersText,
                                      style: TextStyle(
                                        color: Colors.green[700],
                                        fontSize: 14,
                                      ),
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
                SizedBox(height: 12),
                Legend(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Custom PlayGroundActionButton Widget
class PlayGroundActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData icon;

  PlayGroundActionButton({
    required this.label,
    required this.onPressed,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green[200],
        foregroundColor: Colors.green[700],
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 3,
      ),
    );
  }
}

// Custom PlayGroundPlayerListTile Widget
class PlayGroundPlayerListTile extends StatelessWidget {
  final Player player;
  final bool isSelected;
  final VoidCallback onTap;

  PlayGroundPlayerListTile({
    required this.player,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isSelected ? Colors.green[100] : Colors.white,
      elevation: 2,
      margin: EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.only(left: 4.0),
        horizontalTitleGap: 8.0,
        minLeadingWidth: 0,
        visualDensity: VisualDensity.compact,
        dense: true,
        leading: Icon(
          isSelected ? Icons.check_circle : Icons.person,
          color: isSelected ? Colors.green[700] : Colors.grey[400],
        ),
        title: Text(
          player.username,
          style: TextStyle(
            color: Colors.green[800],
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

// Custom PlayGroundTeamMethodButton Widget
class PlayGroundTeamMethodButton extends StatelessWidget {
  final String label;
  final String imagePath;
  final VoidCallback onPressed;

  PlayGroundTeamMethodButton({
    required this.label,
    required this.imagePath,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              imagePath,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 40,
                  height: 40,
                  color: Colors.grey[300],
                  child: Icon(
                    Icons.image_not_supported,
                    color: Colors.grey[700],
                  ),
                );
              },
            ),
          ),
          SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.green[800],
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// Custom PlayGroundTeamCard Widget
// Updated PlayGroundTeamCard Widget with teamType parameter
class PlayGroundTeamCard extends StatelessWidget {
  final String teamName;
  final List<String> players;
  final Map<String, double> averages;
  final double totalAverages;
  // הפרמטר החדש: סוג הקבוצה
  final String teamType;

  PlayGroundTeamCard({
    required this.teamName,
    required this.players,
    required this.averages,
    required this.totalAverages,
    this.teamType = 'bb', // אם אין הגדרה, ברירת מחדל 'fb'
  });

  @override
  Widget build(BuildContext context) {
    // קריאה להגדרות לפי סוג הקבוצה
    final legend = getLegendDefinitions(teamType);

    // בניית רשימת הפרמטרים עם האייקונים והטקסטים המתאימים
    final parameters = [
      {
        'icon': legend['param1']!['icon'],
        'label': legend['param1']![_isHebrew(context) ? 'label_he' : 'label_en'],
        'value': averages['param1']!.toStringAsFixed(2)
      },
      {
        'icon': legend['param2']!['icon'],
        'label': legend['param2']![_isHebrew(context) ? 'label_he' : 'label_en'],
        'value': averages['param2']!.toStringAsFixed(2)
      },
      {
        'icon': legend['param3']!['icon'],
        'label': legend['param3']![_isHebrew(context) ? 'label_he' : 'label_en'],
        'value': averages['param3']!.toStringAsFixed(2)
      },
      {
        'icon': legend['param4']!['icon'],
        'label': legend['param4']![_isHebrew(context) ? 'label_he' : 'label_en'],
        'value': averages['param4']!.toStringAsFixed(2)
      },
      {
        'icon': legend['param5']!['icon'],
        'label': legend['param5']![_isHebrew(context) ? 'label_he' : 'label_en'],
        'value': averages['param5']!.toStringAsFixed(2)
      },
      {
        'icon': legend['param6']!['icon'],
        'label': legend['param6']![_isHebrew(context) ? 'label_he' : 'label_en'],
        'value': averages['param6']!.toStringAsFixed(2)
      },
      {
        'icon': legend['teamAverage']!['icon'],
        'label': legend['teamAverage']![_isHebrew(context) ? 'label_he' : 'label_en'],
        'value': (totalAverages / 6).toStringAsFixed(2)
      },
    ];

    return Card(
      color: Colors.green[50],
      elevation: 3,
      margin: EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // עמודה שמאלית: שם הקבוצה ושמות השחקנים
            Flexible(
              flex: 7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    teamName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 8),
                  ...players.map((player) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person,
                          color: Colors.green[600],
                          size: 14,
                        ),
                        SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            player,
                            style: TextStyle(
                              color: Colors.green[700],
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
            SizedBox(width: 12),
            // עמודה ימנית: הציונים עם האייקונים והטקסטים
            Flexible(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...parameters.asMap().entries.map((entry) {
                    var param = entry.value;
                    if (param['label'] == legend['teamAverage']![_isHebrew(context) ? 'label_he' : 'label_en']) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Flexible(
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final width = constraints.maxWidth > 50 ? 50.0 : constraints.maxWidth;
                                    return Container(
                                      width: width,
                                      height: 1,
                                      color: Colors.green[700],
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),

                          PlayGroundParameterRow(
                            icon: param['icon'] as IconData,
                            tooltip: param['label'] as String,
                            value: param['value'] as String,
                            isTotal: true,
                          ),
                        ],
                      );
                    } else {
                      return PlayGroundParameterRow(
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

  // מתודה עזר לזיהוי אם הטקסט הוא בעברית
  bool _isHebrew(BuildContext context) {
    return Directionality.of(context) == TextDirection.rtl;
  }
}

// Custom PlayGroundParameterRow Widget with Icon and Value
class PlayGroundParameterRow extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final String value;
  final bool isTotal;

  PlayGroundParameterRow({
    required this.icon,
    required this.tooltip,
    required this.value,
    this.isTotal = false,
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
            size: 16,
          ),
          SizedBox(width: 4),
          Expanded(
            child: Text(
              '$value',
              style: TextStyle(
                color: Colors.green[700],
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
