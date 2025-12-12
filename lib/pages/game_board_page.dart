import 'dart:async';

import 'package:flutter/material.dart';

class GameBoardPage extends StatefulWidget {
  const GameBoardPage({super.key});

  @override
  State<GameBoardPage> createState() => _GameBoardPageState();
}

class _GameBoardPageState extends State<GameBoardPage> {
  final TextEditingController _homeController =
      TextEditingController(text: 'קבוצה א');
  final TextEditingController _awayController =
      TextEditingController(text: 'קבוצה ב');

  int _homeScore = 0;
  int _awayScore = 0;
  int _homeFouls = 0;
  int _awayFouls = 0;

  int _durationMinutes = 10;
  Duration _remaining = const Duration(minutes: 10);
  Timer? _timer;
  bool _isRunning = false;

  @override
  void dispose() {
    _timer?.cancel();
    _homeController.dispose();
    _awayController.dispose();
    super.dispose();
  }

  void _startTimer() {
    if (_isRunning) return;
    setState(() {
      _isRunning = true;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remaining.inSeconds <= 0) {
        timer.cancel();
        setState(() {
          _isRunning = false;
        });
        return;
      }

      setState(() {
        _remaining = _remaining - const Duration(seconds: 1);
      });
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
    });
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _remaining = Duration(minutes: _durationMinutes);
    });
  }

  void _updateDuration(double minutes) {
    _durationMinutes = minutes.round();
    if (!_isRunning) {
      setState(() {
        _remaining = Duration(minutes: _durationMinutes);
      });
    } else {
      setState(() {});
    }
  }

  void _updateScore(bool isHome, int delta) {
    setState(() {
      if (isHome) {
        _homeScore = (_homeScore + delta).clamp(0, 999);
      } else {
        _awayScore = (_awayScore + delta).clamp(0, 999);
      }
    });
  }

  void _updateFouls(bool isHome, int delta) {
    setState(() {
      if (isHome) {
        _homeFouls = (_homeFouls + delta).clamp(0, 99);
      } else {
        _awayFouls = (_awayFouls + delta).clamp(0, 99);
      }
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildTeamColumn({
    required String label,
    required TextEditingController controller,
    required int score,
    required int fouls,
    required VoidCallback onAddPoint,
    required VoidCallback onRemovePoint,
    required VoidCallback onAddFoul,
    required VoidCallback onRemoveFoul,
  }) {
    return Expanded(
      child: Card(
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                score.toString(),
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: onRemovePoint,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  IconButton(
                    onPressed: onAddPoint,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('עבירות'),
                  Text(
                    fouls.toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: onRemoveFoul,
                    icon: const Icon(Icons.remove_circle),
                  ),
                  IconButton(
                    onPressed: onAddFoul,
                    icon: const Icon(Icons.add_circle),
                  ),
                ],
              ),
            ],
          ),
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
              'לוח משחק חי',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'כל הכלים למשחק אחד: קבעו זמן, תעדו תוצאות ועבירות והפעילו טיימר מתקתק אחורה.',
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('משך משחק (דקות)'),
                        Text('$_durationMinutes דק\''),
                      ],
                    ),
                    Slider(
                      value: _durationMinutes.toDouble(),
                      min: 5,
                      max: 30,
                      divisions: 25,
                      label: '$_durationMinutes',
                      onChanged: (value) => _updateDuration(value),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatDuration(_remaining),
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _startTimer,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('התחל'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _pauseTimer,
                          icon: const Icon(Icons.pause),
                          label: const Text('הפסק'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _resetTimer,
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('איפוס'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildTeamColumn(
                  label: 'קבוצה א',
                  controller: _homeController,
                  score: _homeScore,
                  fouls: _homeFouls,
                  onAddPoint: () => _updateScore(true, 1),
                  onRemovePoint: () => _updateScore(true, -1),
                  onAddFoul: () => _updateFouls(true, 1),
                  onRemoveFoul: () => _updateFouls(true, -1),
                ),
                const SizedBox(width: 12),
                _buildTeamColumn(
                  label: 'קבוצה ב',
                  controller: _awayController,
                  score: _awayScore,
                  fouls: _awayFouls,
                  onAddPoint: () => _updateScore(false, 1),
                  onRemovePoint: () => _updateScore(false, -1),
                  onAddFoul: () => _updateFouls(false, 1),
                  onRemoveFoul: () => _updateFouls(false, -1),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'הגדרות מהירות',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    const Text('• עדכנו את שמות הקבוצות בשדה הכותרת של כל צד.'),
                    const Text('• הוסיפו או הורידו נקודות ועבירות עם הכפתורים המהירים.'),
                    const Text('• התאימו את משך המשחק והפעילו טיימר אחורה בזמן.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
