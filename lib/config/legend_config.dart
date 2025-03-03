// lib/config/legend_config.dart
import 'package:flutter/material.dart';



Map<String, Map<String, dynamic>> getLegendDefinitions(String sport) {
  if (sport.toLowerCase() == 'fb') {
    return {
      'param1': {
        'icon': Icons.sports_soccer,
        'label_en': 'Ball Control',
        'label_he': 'שליטה בכדור',
      },
      'param2': {
        'icon': Icons.emoji_events,
        'label_en': 'Scoring ',
        'label_he': 'יכולת הבקעה',
      },
      'param3': {
        'icon': Icons.remove_red_eye,
        'label_en': 'Vision',
        'label_he': 'ראיית משחק',
      },
      'param4': {
        'icon': Icons.sports,
        'label_en': 'Shooting Threat',
        'label_he': 'איומים לשער',
      },
      'param5': {
        'icon': Icons.shield,
        'label_en': ' Defense',
        'label_he': ' הגנה',
      },
      'param6': {
        'icon': Icons.speed,
        'label_en': ' speed',
        'label_he': 'תנועה ומהירות',
      },
      'teamAverage': {
        'icon': Icons.calculate,
        'label_en': 'Team Average',
        'label_he': 'ממוצע קבוצה',
      },
    };
  } else {
    return {
      'param1': {
        'icon': Icons.handshake,
        'label_en': 'Play Maker',
        'label_he': 'ניהול משחק',
      },
      'param2': {
        'icon': Icons.score,
        'label_en': 'Scoring Ability',
        'label_he': 'יצירת נקודות',
      },
      'param3': {
        'icon': Icons.shield,
        'label_en': 'Defensive ',
        'label_he': 'הגנה',
      },
      'param4': {
        'icon': Icons.speed,
        'label_en': 'Speed & Agility',
        'label_he': 'מהירות וזריזות',
      },
      'param5': {
        'icon': Icons.sports_basketball,
        'label_en': '3 Pt',
        'label_he': 'שלשות',
      },
      'param6': {
        'icon': Icons.grain,
        'label_en': 'Rebound ',
        'label_he': ' ריבאונד',
      },
      'teamAverage': {
        'icon': Icons.calculate,
        'label_en': 'Team Average',
        'label_he': 'ממוצע קבוצתי',
      },
    };
  }
}
