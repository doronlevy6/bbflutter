import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Legend extends StatefulWidget {
  final bool showTeamAverage;
  Legend({Key? key, this.showTeamAverage = true}) : super(key: key);

  @override
  _LegendState createState() => _LegendState();
}

class _LegendState extends State<Legend> {
  bool _isHebrew = false;

  // רשימת האייטמים למדריך
  final List<Map<String, dynamic>> legendItems = [
    {
      'icon': Icons.handshake,
      'label_en': 'Play Maker',
      'label_he': 'רכז משחק',
    },
    {
      'icon': Icons.score,
      'label_en': 'Scoring Ability',
      'label_he': 'יכולת קליעה',
    },
    {
      'icon': Icons.shield,
      'label_en': 'Defensive Skills',
      'label_he': 'מיומנויות הגנה',
    },
    {
      'icon': Icons.speed,
      'label_en': 'Speed & Agility',
      'label_he': 'מהירות וזריזות',
    },
    {
      'icon': Icons.sports_basketball,
      'label_en': 'Shooting Range',
      'label_he': 'טווח קליעה',
    },
    {
      'icon': Icons.grain,
      'label_en': 'Rebound Skills',
      'label_he': 'מיומנויות ריבאונד',
    },
    {
      'icon': Icons.calculate,
      'label_en': 'Team Average',
      'label_he': 'ממוצע קבוצה',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
  }

  // טעינת הבחירה בשפה מ־SharedPreferences
  Future<void> _loadLanguagePreference() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _isHebrew = prefs.getBool('isHebrew') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // סינון האייטמים בהתאם לפרמטר showTeamAverage
    final displayedItems = widget.showTeamAverage
        ? legendItems
        : legendItems.where((item) => item['label_en'] != 'Team Average').toList();

    return Card(
      color: Colors.green[50],
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.0),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          children: displayedItems.map((item) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  item['icon'],
                  color: Colors.green[700],
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  _isHebrew ? item['label_he'] : item['label_en'],
                  style: TextStyle(
                    color: Colors.green[700],
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
