import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageService {
  static bool _isHebrew = false;

  /// טוען את העדפת השפה מ־SharedPreferences
  static Future<void> loadLanguagePreference() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _isHebrew = prefs.getBool('isHebrew') ?? false;
  }

  /// מעדכן את העדפת השפה ושומר ב־SharedPreferences
  static Future<void> updateLanguagePreference(bool isHebrew) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    _isHebrew = isHebrew;
    await prefs.setBool('isHebrew', isHebrew);
  }

  /// גישה למשתנה העדפת השפה
  static bool get isHebrew => _isHebrew;

  /// מתודה לתרגום טקסטים על בסיס מפתח (key)
  static String translate(String key, {String? username}) {
    if (_isHebrew) {
      switch (key) {
        case 'teams_and_averages':
          return 'קבוצות וממוצעים';
        case 'login_register':
          return 'כניסה/רישום';
        case 'login':
          return 'כניסה';
        case 'home':
          return 'בית';
        case 'grades':
          return username != null ? 'ציוני $username' : 'ציונים';
        case 'management':
          return 'ניהול';
        case 'playground':
          return 'מגרש משחקים';
        case 'logout':
          return 'התנתק';
        case 'no_players_enlisted':
          return 'אין שחקנים רשומים';
        case 'play_next_game':
          return 'שחק במשחק הבא';
        case 'total_enlisted':
          return 'סה"כ רשומים: ';
        case 'sort':
          return 'מיון';
        case 'submit':
          return 'שלח';
        case 'help':
          return 'עזרה';
      // הוסיפו מפתחות נוספים לפי הצורך
        default:
          return key;
      }
    } else {
      switch (key) {
        case 'teams_and_averages':
          return 'Teams and Averages';
        case 'login_register':
          return 'Login/Register';
        case 'login':
          return 'Login';
        case 'home':
          return 'Home';
        case 'grades':
          return username != null ? "$username's Grades" : 'Grades';
        case 'management':
          return 'Management';
        case 'playground':
          return 'Playground';
        case 'logout':
          return 'Logout';
        case 'no_players_enlisted':
          return 'No players enlisted.';
        case 'play_next_game':
          return 'Play Next Game';
        case 'total_enlisted':
          return 'Total Enlisted: ';
        case 'sort':
          return 'Sort';
        case 'submit':
          return 'Submit';
        case 'help':
          return 'help';
      // הוסיפו מפתחות נוספים לפי הצורך
        default:
          return key;
      }
    }
  }

  /// בוחר את סגנון הפונט לכותרת (למשל ב-AppBar) על פי העדפת השפה
  static TextStyle getAppBarTextStyle(double fontSize) {
    if (_isHebrew) {
      return GoogleFonts.tinos(
        fontSize: fontSize,
        fontWeight: FontWeight.w400,
        color: Colors.white,
      );
    } else {
      return GoogleFonts.akayaKanadaka(
        fontSize: fontSize,
        fontWeight: FontWeight.w400,
        color: Colors.white,
      );
    }
  }

/// ניתן להוסיף פונקציות נוספות לבחירת סגנונות טקסט או פונטים לשימוש בכל חלקי האפליקציה
}
