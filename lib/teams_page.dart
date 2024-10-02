// lib/pages/teams_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'model/player.dart'; // Adjust the path according to your project structure.

class TeamsPage extends StatefulWidget {
  const TeamsPage({Key? key}) : super(key: key);

  @override
  _TeamsPageState createState() => _TeamsPageState();
}

class _TeamsPageState extends State<TeamsPage> {
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

  Future<void> _loadPlayersFromLocalStorage() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString(_cacheKey);
    if (jsonString != null) {
      List<dynamic> jsonData = jsonDecode(jsonString);
      setState(() {
        _players = jsonData.map((data) => Player.fromJson(data)).toList();
      });
    } else {
      // Handle the case when no data is found
      print('No players data found in local storage.');
    }
  }

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
  }

  void _clearSelection() {
    setState(() {
      _selectedPlayers.clear();
      _teams.clear();
      _selectedMethod = '';
    });
  }

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
    return Scaffold(
      appBar: AppBar(
        title: Text('Teams Page'),
      ),
      body: Row(
        children: [
          // Left side column (30% width)
          Container(
            width: MediaQuery.of(context).size.width * 0.3,
            color: Colors.grey[200],
            child: Column(
              children: [
                // Counter above player names
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'Selected Players: ${_selectedPlayers.length}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: _clearSelection,
                  child: Text('Clear Selection'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size(100, 36),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _players.length,
                    itemBuilder: (context, index) {
                      Player player = _players[index];
                      bool isSelected = _selectedPlayers.contains(player);
                      return ListTile(
                        title: Text(player.username),
                        trailing: isSelected
                            ? Icon(Icons.check_circle, color: Colors.green)
                            : Icon(Icons.radio_button_unchecked),
                        onTap: () => _togglePlayerSelection(player),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Right side (remaining 70% width)
          Expanded(
            child: Column(
              children: [
                // Top buttons
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: [

                      // Replace the ElevatedButtons inside the Wrap with these GestureDetector widgets
                      GestureDetector(
                        onTap: () => _createBalancedTeams(isAttributeBased: true),
                        child: Column(
                          children: [
                            Image.asset(
                              'assets/images/basketball.jpeg',  // Ensure this path matches your assets folder
                              width: 100,
                              height: 100,
                            ),
                            Text('Parameter'),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _createBalancedTeams(isAttributeBased: false),
                        child: Column(
                          children: [
                            Image.asset(
                              'assets/images/basketball.jpeg',  // Ensure this path matches your assets folder
                              width: 100,
                              height: 100,
                            ),
                            Text('Total'),
                          ],
                        ),
                      ),

                    ],
                  ),
                ),
                // Display teams
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
                      averages.updateAll((key, value) => value / team.length);
                      double totalAverages =
                      averages.values.reduce((a, b) => a + b);

                      return Card(
                        margin: EdgeInsets.all(8.0),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              // Team Members
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Team ${teamIndex + 1}',
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green),
                                    ),
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
                              // Averages
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Averages:',
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green),
                                    ),
                                    Text(
                                      'Playmaker: ${averages['skillLevel']!.toStringAsFixed(2)}',
                                      style: TextStyle(color: Colors.green),
                                    ),
                                    Text(
                                      'Scoring Ability: ${averages['scoringAbility']!.toStringAsFixed(2)}',
                                      style: TextStyle(color: Colors.green),
                                    ),
                                    Text(
                                      'Defensive Skills: ${averages['defensiveSkills']!.toStringAsFixed(2)}',
                                      style: TextStyle(color: Colors.green),
                                    ),
                                    Text(
                                      'Speed and Agility: ${averages['speedAndAgility']!.toStringAsFixed(2)}',
                                      style: TextStyle(color: Colors.green),
                                    ),
                                    Text(
                                      '3 pt Shooting: ${averages['shootingRange']!.toStringAsFixed(2)}',
                                      style: TextStyle(color: Colors.green),
                                    ),
                                    Text(
                                      'Rebound Skills: ${averages['reboundSkills']!.toStringAsFixed(2)}',
                                      style: TextStyle(color: Colors.green),
                                    ),
                                    Text(
                                      'Total Averages Sum: ${totalAverages.toStringAsFixed(2)}',
                                      style: TextStyle(color: Colors.green),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  )
                      : Center(
                    child: Text(
                      _selectedMethod.isNotEmpty
                          ? 'No teams created.'
                          : 'Select players and create balanced teams.',
                    ),
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
