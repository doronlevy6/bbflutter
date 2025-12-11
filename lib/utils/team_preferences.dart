import 'package:shared_preferences/shared_preferences.dart';

class TeamPreferences {
  static const String _teamIdKey = 'team_id';

  static Future<void> setTeamId(int teamId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_teamIdKey, teamId);
  }

  static Future<int?> getTeamId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_teamIdKey);
  }

  static Future<void> clearTeamId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_teamIdKey);
  }
}
