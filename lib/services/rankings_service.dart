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
}
