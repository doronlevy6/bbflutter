// lib/pages/playground.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'widgets/icon_butten_with_label.dart';
import 'model/player.dart'; // Adjust the path according to your project structure.
import 'legend_page.dart'; // Assuming you have a Legend widget similar to WelcomePage
import 'package:responsive_builder/responsive_builder.dart'; // Import responsive_builder

// Import the new IconButtonWithLabel widget

// Define keys for SharedPreferences
const String kEnlistedPlayersKey = 'enlistedPlayers';
const String kSelectedPlayersKey = 'selectedPlayers';

class PlayGround extends StatefulWidget {
  const PlayGround({Key? key}) : super(key: key);

  @override
  _PlayGroundState createState() => _PlayGroundState();
}

class _PlayGroundState extends State<PlayGround> {
  final String _cacheKey = 'playersRankings';
  List<Player> _players = [];
  List<Player> _selectedPlayers = [];
  List<List<Player>> _teams = [];
  String _selectedMethod = '';

  @override
  void initState() {
    super.initState();
    _loadPlayersFromLocalStorage();
  }

  // Load all players from local storage and then load selected players
  Future<void> _loadPlayersFromLocalStorage() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString(_cacheKey);
    if (jsonString != null) {
      List<dynamic> jsonData = jsonDecode(jsonString);
      setState(() {
        _players = jsonData.map((data) => Player.fromJson(data)).toList();
      });
      await _loadSelectedPlayers();
    } else {
      // Handle the case when no data is found
      print('No players data found in local storage.');
    }
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
      // If no saved selection, load enlisted players
      await _loadEnlistedPlayers();
    }
  }

  // Load enlisted players from SharedPreferences and select them
  Future<void> _loadEnlistedPlayers() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? enlistedPlayerUsernames = prefs.getStringList(kEnlistedPlayersKey);
    if (enlistedPlayerUsernames != null && enlistedPlayerUsernames.isNotEmpty) {
      setState(() {
        _selectedPlayers = _players
            .where((player) => enlistedPlayerUsernames.contains(player.username))
            .toList();
      });
      // Save the enlisted players as the current selection
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
            SnackBar(content: Text('You can select up to 12 players only.')),
          );
          return;
        }
        _selectedPlayers.add(player);
      }
    });
    // Save the updated selection
    _saveSelectedPlayers();
  }

  // Clear all selections
  void _clearSelection() {
    setState(() {
      _selectedPlayers.clear();
      _teams.clear();
      _selectedMethod = '';
    });
    // Save the updated selection
    _saveSelectedPlayers();
  }

  // Select all enlisted players
  Future<void> _selectAllEnlistedPlayers() async {
    await _loadEnlistedPlayers();
  }

  // Create balanced teams based on selected method
  Future<void> _createBalancedTeams({required bool isAttributeBased}) async {
    if (_selectedPlayers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select players to create teams.')),
      );
      return;
    }

    int selectedCount = _selectedPlayers.length;

    if (selectedCount > 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Maximum number of players is 12.')),
      );
      return;
    }

    List<Player> playersToUse = _selectedPlayers;

    if (selectedCount >= 9 && selectedCount <= 11) {
      playersToUse = _selectedPlayers.take(8).toList();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Only the first 8 players will be used for team creation.')),
      );
    }

    setState(() {
      int numTeams;

      // Determine the number of teams and handle special cases
      if (selectedCount == 12) {
        numTeams = 3;
      } else if (selectedCount >= 9 && selectedCount <= 11) {
        playersToUse = playersToUse.take(8).toList();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Only the first 8 players will be used for team creation.')),
        );
        numTeams = 2;
      } else if (selectedCount <= 8) {
        numTeams = selectedCount > 4 ? 2 : 1;
      } else {
        // Handle any other unexpected cases if necessary
        return;
      }

      // Now, based on isAttributeBased, call the appropriate distribution method
      if (isAttributeBased) {
        _teams = distributePlayers(playersToUse, numTeams: numTeams);
        _selectedMethod = 'Attribute-based Distribution';
      } else {
        _teams = distributePlayersTier(playersToUse, numTeams: numTeams);
        _selectedMethod = 'Total Average Ranking Distribution';
      }
    });
  }

  // Function to compute the total ranking of a player
  double computeTotalRanking(Player player) {
    return player.skillLevel +
        player.scoringAbility +
        player.defensiveSkills +
        player.speedAndAgility +
        player.shootingRange +
        player.reboundSkills;
  }

  // Existing method: Distribute players into balanced teams based on attributes
  List<List<Player>> distributePlayers(List<Player> players, {required int numTeams}) {
    List<List<Player>> teams = List.generate(numTeams, (_) => []);

    // Calculate the average of each attribute across all players
    Map<String, double> averages = {
      'skillLevel': 0.0,
      'scoringAbility': 0.0,
      'defensiveSkills': 0.0,
      'speedAndAgility': 0.0,
      'shootingRange': 0.0,
      'reboundSkills': 0.0,
    };

    for (var player in players) {
      averages['skillLevel'] = averages['skillLevel']! + player.skillLevel;
      averages['scoringAbility'] =
          averages['scoringAbility']! + player.scoringAbility;
      averages['defensiveSkills'] =
          averages['defensiveSkills']! + player.defensiveSkills;
      averages['speedAndAgility'] =
          averages['speedAndAgility']! + player.speedAndAgility;
      averages['shootingRange'] =
          averages['shootingRange']! + player.shootingRange;
      averages['reboundSkills'] =
          averages['reboundSkills']! + player.reboundSkills;
    }

    averages.updateAll((key, value) => value / players.length);

    // Function to calculate a team's total score in an attribute
    double teamScore(List<Player> team, String attr) {
      double score = 0.0;
      for (var player in team) {
        switch (attr) {
          case 'skillLevel':
            score += player.skillLevel;
            break;
          case 'scoringAbility':
            score += player.scoringAbility;
            break;
          case 'defensiveSkills':
            score += player.defensiveSkills;
            break;
          case 'speedAndAgility':
            score += player.speedAndAgility;
            break;
          case 'shootingRange':
            score += player.shootingRange;
            break;
          case 'reboundSkills':
            score += player.reboundSkills;
            break;
        }
      }
      return score;
    }

    // Distribute players to the teams that most need them
    for (var player in players) {
      // Find the attribute that this player is strongest in
      String strongestAttr = 'skillLevel';
      double strongestVal = player.skillLevel;
      Map<String, double> playerAttributes = {
        'skillLevel': player.skillLevel,
        'scoringAbility': player.scoringAbility,
        'defensiveSkills': player.defensiveSkills,
        'speedAndAgility': player.speedAndAgility,
        'shootingRange': player.shootingRange,
        'reboundSkills': player.reboundSkills,
      };

      playerAttributes.forEach((attr, value) {
        if (value > strongestVal) {
          strongestAttr = attr;
          strongestVal = value;
        }
      });

      // Find the team that is furthest below the average in this attribute and has fewer than 4 players
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
        // Handle any remaining players
        print('No suitable team found for player ${player.username}');
      }
    }

    return teams;
  }

  // New method: Distribute players into balanced teams based on total average ranking
  List<List<Player>> distributePlayersTier(List<Player> players, {required int numTeams}) {
    List<List<Player>> teams = List.generate(numTeams, (_) => []);

    // Create a copy of the players list and sort it
    List<Player> sortedPlayers = List.from(players);
    sortedPlayers.sort((a, b) => computeTotalRanking(b).compareTo(computeTotalRanking(a)));

    // Distribute players to teams to balance total ranking
    for (var player in sortedPlayers) {
      // Find the team with the lowest total ranking and has fewer than 4 players
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
        // Handle any remaining players
        print('No suitable team found for player ${player.username}');
      }
    }

    return teams;
  }

  // Function to calculate a team's total ranking
  double teamTotalRanking(List<Player> team) {
    double total = 0.0;
    for (var player in team) {
      total += computeTotalRanking(player);
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    // Sort players: selected players first, then not selected, both sorted alphabetically
    List<Player> sortedPlayers = List.from(_players);
    sortedPlayers.sort((a, b) {
      bool aSelected = _selectedPlayers.contains(a);
      bool bSelected = _selectedPlayers.contains(b);
      if (aSelected && !bSelected) {
        return -1;
      } else if (!aSelected && bSelected) {
        return 1;
      } else {
        return a.username.toLowerCase().compareTo(b.username.toLowerCase());
      }
    });

    return Scaffold(
      // Removed AppBar to match WelcomePage style
      body: Padding(
        padding: EdgeInsets.all(12.0), // Reduced padding for compactness
        child: Column(
          children: [
            // Main Content: Player Selection and Teams
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
                      // Left Column: Player Selection
                      Expanded(
                        flex: playerFlex,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Selected Players Count
                            SizedBox(height: 10), // Spacing
                            Text(
                              'Selected Players: ${_selectedPlayers.length}',
                              style: TextStyle(
                                color: Colors.green[800],
                                fontWeight: FontWeight.bold,
                                fontSize: 12, // Consistent font size
                              ),
                            ),

                            Row(
                            // New Row for Icon Buttons
                              children: [
                                // Clear Selection Icon Button
                                IconButtonWithLabel(
                                  icon: Icons.refresh,
                                  label: 'Clear',
                                  onPressed: _clearSelection,
                                ),
                                SizedBox(width: 24), // Spacing between buttons
                                // Select All Enlisted Players Icon Button
                                IconButtonWithLabel(
                                  icon: Icons.confirmation_number_outlined,
                                  label: 'Enlisted',
                                  onPressed: _selectAllEnlistedPlayers,
                                ),
                              ],
                            ),
                            SizedBox(height: 12), // Spacing

                            // Players List
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
                                  'No players available.',
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
                      SizedBox(width: 12), // Spacing between columns

                      // Right Column: Teams Display
                      Expanded(
                        flex: teamFlex,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top Buttons: Create Teams
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                // Parameter-based Distribution Button
                                PlayGroundTeamMethodButton(
                                  label: 'Parameter',
                                  imagePath: 'assets/images/basketball.jpeg',
                                  onPressed: () => _createBalancedTeams(isAttributeBased: true),
                                ),
                                SizedBox(width: 16), // Spacing
                                // Total Average Ranking Distribution Button
                                PlayGroundTeamMethodButton(
                                  label: 'Total',
                                  imagePath: 'assets/images/basketball.jpeg',
                                  onPressed: () => _createBalancedTeams(isAttributeBased: false),
                                ),
                              ],
                            ),
                            SizedBox(height: 12), // Spacing

                            // Teams List
                            Expanded(
                              child: _teams.isNotEmpty
                                  ? ListView.builder(
                                itemCount: _teams.length,
                                itemBuilder: (context, teamIndex) {
                                  List<Player> team = _teams[teamIndex];
                                  // Calculate averages for the team
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
                                        averages['scoringAbility']! + player.scoringAbility;
                                    averages['defensiveSkills'] =
                                        averages['defensiveSkills']! + player.defensiveSkills;
                                    averages['speedAndAgility'] =
                                        averages['speedAndAgility']! + player.speedAndAgility;
                                    averages['shootingRange'] =
                                        averages['shootingRange']! + player.shootingRange;
                                    averages['reboundSkills'] =
                                        averages['reboundSkills']! + player.reboundSkills;
                                  }
                                  averages.updateAll((key, value) => value / team.length);
                                  double totalAverages =
                                  averages.values.reduce((a, b) => a + b);

                                  return PlayGroundTeamCard(
                                    teamName: 'Team ${teamIndex + 1}',
                                    players: team.map((p) => p.username).toList(),
                                    averages: averages,
                                    totalAverages: totalAverages,
                                  );
                                },
                              )
                                  : Center(
                                child: Text(
                                  _selectedMethod.isNotEmpty
                                      ? 'No teams created.'
                                      : 'Select players and create balanced teams.',
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
            SizedBox(height: 12), // Spacing

            // Legend Section positioned lower
            Legend(),
          ],
        ),
      ),
    );
  }
}

// ... [Rest of your custom widgets like PlayGroundPlayerListTile, PlayGroundTeamMethodButton, PlayGroundTeamCard, PlayGroundParameterRow]


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
          fontSize: 14, // Smaller font
          fontWeight: FontWeight.bold,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green[200], // Button background color
        foregroundColor: Colors.green[700], // Button text color

        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4), // Adjust padding
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8), // Rounded corners
        ),
        elevation: 3, // Button elevation
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
          // Image with error handling
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
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// Custom PlayGroundTeamCard Widget
class PlayGroundTeamCard extends StatelessWidget {
  final String teamName;
  final List<String> players;
  final Map<String, double> averages;
  final double totalAverages;

  PlayGroundTeamCard({
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
            // Left Column: Team Name and Players
            Expanded(
              flex: 7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Team Header
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
                  // Players List
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
                        Expanded(
                          child: Text(
                            player,
                            style: TextStyle(
                              color: Colors.green[700],
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
            SizedBox(width: 12), // Spacing between columns

            // Right Column: Averages
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Divider before averages

                  // Averages List
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
                              Container(
                                width: 50, // Fixed width of 50 pixels
                                height: 1, // Height of the line
                                color: Colors.green[700], // Line color
                              ),
                              // No text here, just the divider
                            ],
                          ),
                          PlayGroundParameterRow(
                            icon: param['icon'] as IconData,
                            tooltip: param['label'] as String,
                            value: param['value'] as String,
                            isTotal: true, // Indicate that this is the total
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
