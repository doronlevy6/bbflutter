import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/legend_config.dart';

class Legend extends StatefulWidget {
  final bool showTeamAverage;
  Legend({Key? key, this.showTeamAverage = true}) : super(key: key);

  @override
  _LegendState createState() => _LegendState();
}

class _LegendState extends State<Legend> {
  bool _isHebrew = false;
  String _sport = 'bb'; // ערך ברירת מחדל

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  // טעינת הבחירה בשפה ובסוג הספורט מ־SharedPreferences
  Future<void> _loadPreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _isHebrew = prefs.getBool('isHebrew') ?? false;
      _sport = prefs.getString('team_type') ?? 'bb';
    });
  }

  @override
  Widget build(BuildContext context) {
    // משיכת ההגדרות מתוך הקובץ המשותף לפי סוג הספורט
    final definitions = getLegendDefinitions(_sport);
    final legendItems = definitions.entries.where((entry) {
      if (!widget.showTeamAverage && entry.key == 'teamAverage') {
        return false;
      }
      return true;
    }).map((entry) => entry.value).toList();

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
          children: legendItems.map((item) {
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
