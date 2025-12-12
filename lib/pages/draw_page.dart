import 'dart:math';

import 'package:flutter/material.dart';

class DrawPage extends StatefulWidget {
  const DrawPage({super.key});

  @override
  State<DrawPage> createState() => _DrawPageState();
}

class _DrawPageState extends State<DrawPage> {
  static const int _minTeams = 2;
  static const int _maxTeams = 6;

  int _teamCount = 3;
  List<TextEditingController> _controllers =
      List.generate(3, (index) => TextEditingController());

  String? _sitOutResult;
  String? _startResult;
  String? _jerseyPair;

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> _teamNames() {
    return List.generate(_teamCount, (index) {
      final text = _controllers[index].text.trim();
      return text.isEmpty ? 'קבוצה ${index + 1}' : text;
    });
  }

  void _updateTeamCount(int count) {
    setState(() {
      _teamCount = count;
      if (_controllers.length < count) {
        _controllers.addAll(List.generate(
          count - _controllers.length,
          (index) => TextEditingController(),
        ));
      } else if (_controllers.length > count) {
        _controllers = _controllers.sublist(0, count);
      }
      _sitOutResult = null;
      _startResult = null;
      _jerseyPair = null;
    });
  }

  void _drawSitOut() {
    final names = _teamNames();
    if (names.length < 2) return;

    final random = Random();
    final index = random.nextInt(names.length);
    setState(() {
      _sitOutResult = names[index];
      _startResult = null;
      _jerseyPair = null;
    });
  }

  void _drawStartingTeam() {
    final names = _teamNames();
    if (names.length < 2) return;

    final availableTeams = List<String>.from(names);
    if (_sitOutResult != null && availableTeams.length > 2) {
      availableTeams.remove(_sitOutResult);
    }

    if (availableTeams.isEmpty) return;

    final random = Random();
    final startIndex = random.nextInt(availableTeams.length);
    final chosenTeam = availableTeams[startIndex];

    const jerseyOptions = [
      'כחול',
      'אדום',
      'ירוק',
      'כתום',
      'שחור',
      'לבן',
      'צהוב',
      'סגול',
    ];

    final firstColor = jerseyOptions[random.nextInt(jerseyOptions.length)];
    String secondColor = firstColor;
    while (secondColor == firstColor) {
      secondColor = jerseyOptions[random.nextInt(jerseyOptions.length)];
    }

    setState(() {
      _startResult = chosenTeam;
      _jerseyPair = '$firstColor / $secondColor';
    });
  }

  Widget _buildTeamFields() {
    return Column(
      children: List.generate(_teamCount, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: TextField(
            controller: _controllers[index],
            decoration: InputDecoration(
              labelText: 'שם קבוצה ${index + 1}',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildResultCard(String title, String? value, IconData icon) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, color: Colors.green[700]),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(value ?? 'עדיין אין תוצאה'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'הגרלת משחקים',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'בחרו כמה קבוצות משתתפות (2 עד 6), הגדירו את השמות ובצעו שתי הגרלות: מי נשארת בחוץ ומי מתחילה עם הכדור והחולצות.',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('מספר קבוצות:'),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: _teamCount,
                  onChanged: (value) {
                    if (value != null) {
                      _updateTeamCount(value);
                    }
                  },
                  items: List.generate(
                    _maxTeams - _minTeams + 1,
                    (index) => _minTeams + index,
                  ).map((count) {
                    return DropdownMenuItem<int>(
                      value: count,
                      child: Text(count.toString()),
                    );
                  }).toList(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTeamFields(),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: _drawSitOut,
                  icon: const Icon(Icons.remove_circle_outline),
                  label: const Text('הגרלת מי בחוץ'),
                ),
                ElevatedButton.icon(
                  onPressed: _drawStartingTeam,
                  icon: const Icon(Icons.sports_soccer),
                  label: const Text('הגרלת קבוצה פותחת'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildResultCard('קבוצה שתשב בחוץ', _sitOutResult,
                Icons.event_busy_rounded),
            _buildResultCard(
                'קבוצה שמתחילה עם הכדור', _startResult, Icons.sports_rounded),
            _buildResultCard('צבעי חולצות להגרלה', _jerseyPair,
                Icons.checkroom_outlined),
          ],
        ),
      ),
    );
  }
}
