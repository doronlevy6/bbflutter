// asset_manager.dart
import 'package:shared_preferences/shared_preferences.dart';

class AssetManager {
  /// קורא את ה-team type מה-SharedPreferences ומחזיר את הנתיב המתאים לתמונה
  static Future<String> getTeamImageFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final teamType = prefs.getString('team_type') ?? '';
    if (teamType == 'bb') {
      return 'assets/images/basketball.png';
    } else if (teamType == 'fb') {
      return 'assets/images/fb.png';
    }
    // תמונה ברירת מחדל במקרה שה-team type אינו תואם
    return 'assets/images/default.png';
  }
}
