// lib/services/rankings_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class RankingsService {
  static final ApiService _apiService = ApiService();

  /// Fetch player rankings for a specific user and cache them in SharedPreferences.
  static  Future<bool> fetchAndCachePlayerRankingsForUser(String username) async {
    try {
      final data = await _apiService.get('players-rankings/$username');

      if (data['success'] == true) {
        String jsonString = jsonEncode(data['playersRankings']);
        SharedPreferences prefs = await SharedPreferences.getInstance();
        bool isSet = await prefs.setString('playersRankings_$username', jsonString);

        if (isSet) {
          print("Player rankings for $username successfully cached.");
        }
        return isSet;
      } else {
        print("Failed to load player rankings for $username.");
        return false;
      }
    } catch (error) {
      print("Error fetching rankings for $username: $error");
      return false;
    }
  }

  /// Fetch overall player rankings and cache them in SharedPreferences.
  static  Future<bool> fetchAndCacheOverallPlayerRankings() async {
    try {
      final data = await _apiService.get('players-rankings');

      if (data['success'] == true) {
        String jsonString = jsonEncode(data['playersRankings']);
        SharedPreferences prefs = await SharedPreferences.getInstance();
        bool isSet = await prefs.setString('overallPlayersRankings', jsonString);

        if (isSet) {
          print("Overall player rankings successfully cached.");
        }
        return isSet;
      } else {
        print("Failed to load overall player rankings.");
        return false;
      }
    } catch (error) {
      print("Error fetching overall rankings: $error");
      return false;
    }
  }
  static Future<bool> getEnlisted() async {
    try {
      final enlistResponse = await _apiService.get('enlist');
      if (enlistResponse['success'] == true) {
        List<String> fetchedPlayers = List<String>.from(enlistResponse['usernames']);
        bool isSet = await _saveEnlistedPlayers(fetchedPlayers);
        if (isSet) {
          print("Enlisted players successfully cached using setStringList.");
        }
        return isSet;
      } else {
        print("Failed to load enlisted players.");
        return false;
      }
    } catch (error) {
      print("Error fetching enlisted players: $error");
      return false;
    }
  }

  static Future<bool> _saveEnlistedPlayers(List<String> players) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return await prefs.setStringList("enlistedPlayers", players);
  }

}
