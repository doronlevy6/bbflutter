import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'model/player.dart';

class GetScorePage extends StatefulWidget {
  const GetScorePage({Key? key}) : super(key: key);
  @override
  _GetScorePageState createState() => _GetScorePageState();
}

class _GetScorePageState extends State<GetScorePage> {
  List<Player> playersRankings = [];
  static const String _cacheKey = 'players_cache';

  @override
  void initState() {
    super.initState();
    loadCachedData(); // Load cached data if available
  }

  Future<void> fetchAndCachePlayerRankings() async {
    final response = await http.get(Uri.parse('http://localhost:9090/players-rankings-doron'));

    if (response.statusCode == 200) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setString(_cacheKey, response.body); // Cache the response
      setState(() {
        playersRankings = (json.decode(response.body)['playersRankings'] as List)
            .map((data) => Player.fromJson(data))
            .toList();
      });
    } else {
      print('Failed to load player rankings');
    }
  }

  Future<void> loadCachedData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_cacheKey)) {
      String? cachedData = prefs.getString(_cacheKey);
      if (cachedData != null) {
        setState(() {
          playersRankings = (json.decode(cachedData)['playersRankings'] as List)
              .map((data) => Player.fromJson(data))
              .toList();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Get Score Page'),
      ),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: fetchAndCachePlayerRankings,
            child: Text('Load Players Rankings'),
          ),
          Expanded(
            child: playersRankings.isEmpty
                ? Center(child: Text('No Data Available. Press the button to load.'))
                : ListView.builder(
              itemCount: playersRankings.length,
              itemBuilder: (context, index) {
                final player = playersRankings[index];
                return ListTile(
                  title: Text(player.username),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Skill Level: ${player.skillLevel}'),
                      Text('Scoring Ability: ${player.scoringAbility}'),
                      Text('Defensive Skills: ${player.defensiveSkills}'),
                      Text('Speed and Agility: ${player.speedAndAgility}'),
                      Text('Shooting Range: ${player.shootingRange}'),
                      Text('Rebound Skills: ${player.reboundSkills}'),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
