import 'package:flutter/material.dart';
import 'dart:async';
import '../services/sound_service.dart';

class ScoreboardPage extends StatefulWidget {
  @override
  _ScoreboardPageState createState() => _ScoreboardPageState();
}

class _ScoreboardPageState extends State<ScoreboardPage> {
  // Team Names
  String homeTeam = 'HOME';
  String awayTeam = 'AWAY';
  
  // Scores
  int homeScore = 0;
  int awayScore = 0;
  
  // Fouls
  int homeFouls = 0;
  int awayFouls = 0;
  
  // Timeouts
  int homeTimeouts = 5;
  int awayTimeouts = 5;
  
  // Game State
  int quarter = 1;
  bool isOvertime = false;
  
  // Clocks
  int gameClockSeconds = 10 * 60; // Starts at countdown time (10 min default)
  int shotClockSeconds = 24;
  bool isRunning = false;
  Timer? gameTimer;
  
  // Possession (true = home, false = away)
  bool homePossession = true;
  
  // Undo History
  List<Map<String, dynamic>> history = [];
  
  // Track if warning was already played
  bool _warningPlayed = false;
  
  // === CONFIGURABLE SETTINGS ===
  // Clock settings
  bool settingCountUp = false; // false = countdown (default), true = stopwatch
  int settingCountdownMinutes = 10; // Default countdown time
  int settingQuarterMinutes = 10;
  int settingShotClock = 24;
  int settingShotClockReset = 14;
  int settingOvertimeMinutes = 5;
  
  // Sound settings
  bool settingEnableSounds = true; // Enable all sounds
  int settingWarningSeconds = 60; // Warning sound X seconds before end
  
  // Feature toggles (defaults for street basketball)
  bool settingEnableQuarters = false; // OFF by default
  bool settingEnableShotClock = false; // OFF by default
  bool settingEnableTimeouts = false; // OFF by default
  bool settingEnablePossession = false; // OFF by default
  
  // Fouls settings
  int settingMaxFouls = 3; // Max fouls per team (default 3)
  int settingTimeoutsPerTeam = 5;
  
  // Sound options
  static const List<String> buzzerNames = ['Long Buzzer', 'Short Buzzer', 'Triple Beep'];
  static const List<String> warningNames = ['Single Beep', 'Double Beep', 'Whistle'];
  
  int settingBuzzerIndex = 0;
  int settingWarningIndex = 0;
  
  // Sound service
  final SoundService _soundService = SoundService();
  
  @override
  void initState() {
    super.initState();
    _soundService.setSoundEnabled(settingEnableSounds);
  }
  
  void _playBuzzer() {
    if (!settingEnableSounds) return;
    _soundService.playBuzzer(type: settingBuzzerIndex);
  }
  
  void _playWarning() {
    if (!settingEnableSounds) return;
    _soundService.playWarning(type: settingWarningIndex);
  }
  
  void _testBuzzer(int index) {
    _soundService.playBuzzer(type: index);
  }
  
  void _testWarning(int index) {
    _soundService.playWarning(type: index);
  }
  
  @override
  void dispose() {
    gameTimer?.cancel();
    super.dispose();
  }
  
  void _showSettingsDialog() {
    // Create temporary copies for the dialog
    bool tempCountUp = settingCountUp;
    int tempCountdownMinutes = settingCountdownMinutes;
    bool tempEnableQuarters = settingEnableQuarters;
    bool tempEnableShotClock = settingEnableShotClock;
    bool tempEnableTimeouts = settingEnableTimeouts;
    bool tempEnablePossession = settingEnablePossession;
    int tempQuarterMinutes = settingQuarterMinutes;
    int tempShotClock = settingShotClock;
    int tempShotClockReset = settingShotClockReset;
    int tempMaxFouls = settingMaxFouls;
    int tempTimeoutsPerTeam = settingTimeoutsPerTeam;
    bool tempEnableSounds = settingEnableSounds;
    int tempWarningSeconds = settingWarningSeconds;
    int tempBuzzerIndex = settingBuzzerIndex;
    int tempWarningIndex = settingWarningIndex;
    
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Color(0xFF1a1a2e),
              title: Text('Game Settings', style: TextStyle(color: Colors.white)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // CLOCK MODE
                    Text('Clock Mode', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                    SwitchListTile(
                      title: Text('Count Up (Stopwatch)', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      value: tempCountUp,
                      onChanged: (v) => setDialogState(() => tempCountUp = v),
                      activeColor: Colors.green,
                      dense: true,
                    ),
                    if (!tempCountUp)
                      _settingRow('Countdown Time (min)', tempCountdownMinutes, (v) => setDialogState(() => tempCountdownMinutes = v), 1, 60),
                    Divider(color: Colors.grey[700]),
                    
                    // FEATURES
                    Text('Features', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                    SwitchListTile(
                      title: Text('Enable Quarters', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      value: tempEnableQuarters,
                      onChanged: (v) => setDialogState(() => tempEnableQuarters = v),
                      activeColor: Colors.green,
                      dense: true,
                    ),
                    if (tempEnableQuarters)
                      _settingRow('Quarter Length (min)', tempQuarterMinutes, (v) => setDialogState(() => tempQuarterMinutes = v), 1, 20),
                    SwitchListTile(
                      title: Text('Enable Shot Clock', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      value: tempEnableShotClock,
                      onChanged: (v) => setDialogState(() => tempEnableShotClock = v),
                      activeColor: Colors.green,
                      dense: true,
                    ),
                    if (tempEnableShotClock) ...[
                      _settingRow('Shot Clock (sec)', tempShotClock, (v) => setDialogState(() => tempShotClock = v), 14, 35),
                      _settingRow('Reset to (sec)', tempShotClockReset, (v) => setDialogState(() => tempShotClockReset = v), 10, 24),
                    ],
                    SwitchListTile(
                      title: Text('Enable Timeouts', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      value: tempEnableTimeouts,
                      onChanged: (v) => setDialogState(() => tempEnableTimeouts = v),
                      activeColor: Colors.green,
                      dense: true,
                    ),
                    if (tempEnableTimeouts)
                      _settingRow('Timeouts per Team', tempTimeoutsPerTeam, (v) => setDialogState(() => tempTimeoutsPerTeam = v), 1, 7),
                    SwitchListTile(
                      title: Text('Enable Possession Arrow', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      value: tempEnablePossession,
                      onChanged: (v) => setDialogState(() => tempEnablePossession = v),
                      activeColor: Colors.green,
                      dense: true,
                    ),
                    Divider(color: Colors.grey[700]),
                    
                    // FOULS
                    Text('Fouls', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                    _settingRow('Max Fouls per Team', tempMaxFouls, (v) => setDialogState(() => tempMaxFouls = v), 1, 10),
                    Divider(color: Colors.grey[700]),
                    
                    // SOUNDS
                    Text('Sounds', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                    SwitchListTile(
                      title: Text('Enable Sounds', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      value: tempEnableSounds,
                      onChanged: (v) => setDialogState(() => tempEnableSounds = v),
                      activeColor: Colors.green,
                      dense: true,
                    ),
                    if (tempEnableSounds) ...[
                      // Buzzer sound selection
                      Row(
                        children: [
                          Text('End Buzzer: ', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          Expanded(
                            child: DropdownButton<int>(
                              value: tempBuzzerIndex,
                              dropdownColor: Color(0xFF2a2a4e),
                              style: TextStyle(color: Colors.white, fontSize: 13),
                              isExpanded: true,
                              items: buzzerNames.asMap().entries.map((e) => 
                                DropdownMenuItem(value: e.key, child: Text(e.value))
                              ).toList(),
                              onChanged: (v) => setDialogState(() => tempBuzzerIndex = v!),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.play_arrow, color: Colors.green, size: 20),
                            onPressed: () => _testBuzzer(tempBuzzerIndex),
                          ),
                        ],
                      ),
                      // Warning sound selection
                      Row(
                        children: [
                          Text('Warning: ', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          Expanded(
                            child: DropdownButton<int>(
                              value: tempWarningIndex,
                              dropdownColor: Color(0xFF2a2a4e),
                              style: TextStyle(color: Colors.white, fontSize: 13),
                              isExpanded: true,
                              items: warningNames.asMap().entries.map((e) => 
                                DropdownMenuItem(value: e.key, child: Text(e.value))
                              ).toList(),
                              onChanged: (v) => setDialogState(() => tempWarningIndex = v!),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.play_arrow, color: Colors.green, size: 20),
                            onPressed: () => _testWarning(tempWarningIndex),
                          ),
                        ],
                      ),
                      if (!tempCountUp)
                        _settingRow('Warning at (sec)', tempWarningSeconds, (v) => setDialogState(() => tempWarningSeconds = v), 10, 300),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: () {
                    setState(() {
                      // Apply all settings
                      settingCountUp = tempCountUp;
                      settingCountdownMinutes = tempCountdownMinutes;
                      settingEnableQuarters = tempEnableQuarters;
                      settingEnableShotClock = tempEnableShotClock;
                      settingEnableTimeouts = tempEnableTimeouts;
                      settingEnablePossession = tempEnablePossession;
                      settingQuarterMinutes = tempQuarterMinutes;
                      settingShotClock = tempShotClock;
                      settingShotClockReset = tempShotClockReset;
                      settingMaxFouls = tempMaxFouls;
                      settingTimeoutsPerTeam = tempTimeoutsPerTeam;
                      settingEnableSounds = tempEnableSounds;
                      settingWarningSeconds = tempWarningSeconds;
                      settingBuzzerIndex = tempBuzzerIndex;
                      settingWarningIndex = tempWarningIndex;
                      
                      // Reset clocks based on new settings
                      if (settingCountUp) {
                        gameClockSeconds = 0;
                      } else {
                        gameClockSeconds = settingCountdownMinutes * 60;
                      }
                      shotClockSeconds = settingShotClock;
                      homeTimeouts = settingTimeoutsPerTeam;
                      awayTimeouts = settingTimeoutsPerTeam;
                      _warningPlayed = false; // Reset warning flag
                    });
                    Navigator.pop(ctx);
                  },
                  child: Text('Apply', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  Widget _settingRow(String label, int value, Function(int) onChanged, int min, int max) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: TextStyle(color: Colors.white70, fontSize: 13))),
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.remove_circle, color: value > min ? Colors.red[300] : Colors.grey),
                onPressed: value > min ? () => onChanged(value - 1) : null,
                iconSize: 28,
              ),
              Container(
                width: 40,
                alignment: Alignment.center,
                child: Text('$value', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: Icon(Icons.add_circle, color: value < max ? Colors.green[300] : Colors.grey),
                onPressed: value < max ? () => onChanged(value + 1) : null,
                iconSize: 28,
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  void _saveState() {
    history.add({
      'homeScore': homeScore,
      'awayScore': awayScore,
      'homeFouls': homeFouls,
      'awayFouls': awayFouls,
      'homeTimeouts': homeTimeouts,
      'awayTimeouts': awayTimeouts,
      'quarter': quarter,
      'isOvertime': isOvertime,
      'gameClockSeconds': gameClockSeconds,
      'shotClockSeconds': shotClockSeconds,
      'homePossession': homePossession,
    });
    if (history.length > 50) history.removeAt(0);
  }
  
  void _undo() {
    if (history.isEmpty) return;
    final prev = history.removeLast();
    setState(() {
      homeScore = prev['homeScore'];
      awayScore = prev['awayScore'];
      homeFouls = prev['homeFouls'];
      awayFouls = prev['awayFouls'];
      homeTimeouts = prev['homeTimeouts'];
      awayTimeouts = prev['awayTimeouts'];
      quarter = prev['quarter'];
      isOvertime = prev['isOvertime'];
      gameClockSeconds = prev['gameClockSeconds'];
      shotClockSeconds = prev['shotClockSeconds'];
      homePossession = prev['homePossession'];
    });
  }
  
  void _addScore(bool isHome, int points) {
    _saveState();
    setState(() {
      if (isHome) {
        homeScore += points;
      } else {
        awayScore += points;
      }
      shotClockSeconds = settingShotClock;
      homePossession = !isHome;
    });
  }
  
  void _removeScore(bool isHome) {
    if ((isHome && homeScore <= 0) || (!isHome && awayScore <= 0)) return;
    _saveState();
    setState(() {
      if (isHome && homeScore > 0) {
        homeScore--;
      } else if (!isHome && awayScore > 0) {
        awayScore--;
      }
    });
  }
  
  void _addFoul(bool isHome) {
    _saveState();
    setState(() {
      if (isHome) {
        homeFouls++;
      } else {
        awayFouls++;
      }
    });
  }
  
  void _removeFoul(bool isHome) {
    _saveState();
    setState(() {
      if (isHome && homeFouls > 0) {
        homeFouls--;
      } else if (!isHome && awayFouls > 0) {
        awayFouls--;
      }
    });
  }
  
  void _useTimeout(bool isHome) {
    _saveState();
    setState(() {
      if (isHome && homeTimeouts > 0) {
        homeTimeouts--;
      } else if (!isHome && awayTimeouts > 0) {
        awayTimeouts--;
      }
      _pauseClock();
    });
  }
  
  void _togglePossession() {
    _saveState();
    setState(() {
      homePossession = !homePossession;
      shotClockSeconds = settingShotClock;
    });
  }
  
  void _startPauseClock() {
    if (isRunning) {
      _pauseClock();
    } else {
      _startClock();
    }
  }
  
  void _startClock() {
    setState(() => isRunning = true);
    _warningPlayed = false; // Reset warning flag when starting
    gameTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        // Shot clock (only if enabled)
        if (settingEnableShotClock && shotClockSeconds > 0) {
          shotClockSeconds--;
        }
        
        // Game clock
        if (settingCountUp) {
          // Count UP (stopwatch mode)
          gameClockSeconds++;
        } else {
          // Count DOWN
          if (gameClockSeconds > 0) {
            // Check for warning sound
            if (gameClockSeconds == settingWarningSeconds && !_warningPlayed) {
              _playWarning();
              _warningPlayed = true;
            }
            gameClockSeconds--;
          } else {
            // End of countdown - play buzzer
            _playBuzzer();
            _pauseClock();
            if (settingEnableQuarters) _endQuarter();
          }
        }
      });
    });
  }
  
  void _pauseClock() {
    setState(() => isRunning = false);
    gameTimer?.cancel();
  }
  
  void _resetShotClock([int seconds = 24]) {
    _saveState();
    setState(() => shotClockSeconds = seconds);
  }
  
  void _endQuarter() {
    setState(() {
      if (quarter < 4) {
        quarter++;
        gameClockSeconds = settingQuarterMinutes * 60;
        homeFouls = 0;
        awayFouls = 0;
      } else {
        isOvertime = true;
        gameClockSeconds = settingOvertimeMinutes * 60;
      }
      shotClockSeconds = settingShotClock;
    });
  }
  
  void _nextQuarter() {
    _saveState();
    _endQuarter();
  }
  
  void _resetGame() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Color(0xFF1a1a2e),
        title: Text('Reset Game?', style: TextStyle(color: Colors.white)),
        content: Text('This will clear all scores and start fresh.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                homeScore = 0;
                awayScore = 0;
                homeFouls = 0;
                awayFouls = 0;
                homeTimeouts = settingTimeoutsPerTeam;
                awayTimeouts = settingTimeoutsPerTeam;
                quarter = 1;
                isOvertime = false;
                // Start at 0 if counting up, otherwise use countdown time
                gameClockSeconds = settingCountUp ? 0 : (settingCountdownMinutes * 60);
                shotClockSeconds = settingShotClock;
                homePossession = true;
                history.clear();
                _pauseClock();
              });
            },
            child: Text('Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
  
  String _formatTime(int seconds) {
    int min = seconds ~/ 60;
    int sec = seconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isLandscape = screenWidth > screenHeight;
    
    return Scaffold(
      backgroundColor: Color(0xFF1a1a2e),
      appBar: isLandscape ? null : AppBar(
        backgroundColor: Color(0xFF16213e),
        foregroundColor: Colors.white,
        title: Text('Scoreboard'),
        toolbarHeight: 40,
        actions: [
          IconButton(icon: Icon(Icons.undo, size: 20), onPressed: history.isEmpty ? null : _undo, iconSize: 20),
          IconButton(icon: Icon(Icons.refresh, size: 20), onPressed: _resetGame, iconSize: 20),
          IconButton(icon: Icon(Icons.settings, size: 20), onPressed: _showSettingsDialog, iconSize: 20),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // CONTROL BAR (clock + start/pause + reset)
            Container(
              padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              color: Color(0xFF16213e),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Quarter (only if enabled)
                  if (settingEnableQuarters) ...[
                    GestureDetector(
                      onTap: _nextQuarter,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange[700],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isOvertime ? 'OT' : 'Q$quarter',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                  ],
                  
                  // Start/Pause button
                  GestureDetector(
                    onTap: _startPauseClock,
                    child: Container(
                      padding: EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isRunning ? Colors.orange : Colors.green,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isRunning ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  
                  // Game Clock
                  GestureDetector(
                    onTap: _startPauseClock,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: isRunning ? Colors.green[800] : Colors.grey[800],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _formatTime(gameClockSeconds),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  
                  // Reset button
                  GestureDetector(
                    onTap: _resetGame,
                    child: Container(
                      padding: EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red[700],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.refresh, color: Colors.white, size: 20),
                    ),
                  ),
                  
                  // Shot Clock (only if enabled)
                  if (settingEnableShotClock) ...[
                    SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _resetShotClock(settingShotClock),
                      onDoubleTap: () => _resetShotClock(settingShotClockReset),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: shotClockSeconds <= 5 ? Colors.red : Colors.red[900],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$shotClockSeconds',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                  
                  // Settings (in landscape only)
                  if (isLandscape) ...[
                    SizedBox(width: 8),
                    GestureDetector(
                      onTap: _showSettingsDialog,
                      child: Icon(Icons.settings, color: Colors.white54, size: 20),
                    ),
                    SizedBox(width: 6),
                    GestureDetector(
                      onTap: history.isEmpty ? null : _undo,
                      child: Icon(Icons.undo, color: history.isEmpty ? Colors.grey[700] : Colors.white54, size: 20),
                    ),
                  ],
                ],
              ),
            ),
            
            // TEAMS CONTENT with START/STOP in center
            Expanded(
              child: Row(
                children: [
                  // HOME TEAM
                  Expanded(child: _buildTeamPanel(true)),
                  
                  // CENTER CONTROL - Big Start/Stop button
                  Container(
                    width: 70,
                    color: Color(0xFF0f0f23),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // BIG START/STOP BUTTON
                        GestureDetector(
                          onTap: _startPauseClock,
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: isRunning ? Colors.orange : Colors.green,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (isRunning ? Colors.orange : Colors.green).withOpacity(0.5),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Icon(
                              isRunning ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ),
                        SizedBox(height: 16),
                        // Reset button
                        GestureDetector(
                          onTap: _resetGame,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.red[800],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.refresh, color: Colors.white, size: 22),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // AWAY TEAM
                  Expanded(child: _buildTeamPanel(false)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTeamPanel(bool isHome) {
    final score = isHome ? homeScore : awayScore;
    final fouls = isHome ? homeFouls : awayFouls;
    final timeouts = isHome ? homeTimeouts : awayTimeouts;
    final teamName = isHome ? homeTeam : awayTeam;
    final teamColor = isHome ? Colors.blue : Colors.red;
    final isMaxFouls = fouls >= settingMaxFouls;
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: isHome ? Color(0xFF1a1a3e) : Color(0xFF2a1a1a),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Team Name (tap to edit)
          GestureDetector(
            onTap: () => _editTeamName(isHome),
            child: Text(
              teamName,
              style: TextStyle(color: Colors.white60, fontSize: 11, letterSpacing: 1),
            ),
          ),
          
          // Score with minus button
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Minus button
              GestureDetector(
                onTap: () => _removeScore(isHome),
                child: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.remove, color: Colors.white54, size: 18),
                ),
              ),
              SizedBox(width: 8),
              // Score display
              Text(
                '$score',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 52,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          
          // Score Buttons Row - BIGGER with more spacing
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _bigScoreButton('+1', teamColor[400]!, () => _addScore(isHome, 1)),
              SizedBox(width: 10),
              _bigScoreButton('+2', teamColor, () => _addScore(isHome, 2)),
              SizedBox(width: 10),
              _bigScoreButton('+3', teamColor[700]!, () => _addScore(isHome, 3)),
            ],
          ),
          SizedBox(height: 12),
          
          // Fouls Row with bigger +/- buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Minus foul - BIGGER
              GestureDetector(
                onTap: () => _removeFoul(isHome),
                child: Container(
                  padding: EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.remove, color: Colors.white54, size: 16),
                ),
              ),
              SizedBox(width: 8),
              // Foul circles - bigger
              ...List.generate(settingMaxFouls, (i) => Container(
                margin: EdgeInsets.symmetric(horizontal: 3),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < fouls ? Colors.red : Colors.grey[700],
                  border: Border.all(color: Colors.white24, width: 1),
                ),
              )),
              SizedBox(width: 8),
              // Plus foul - BIGGER
              GestureDetector(
                onTap: () => _addFoul(isHome),
                child: Container(
                  padding: EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add, color: Colors.white54, size: 16),
                ),
              ),
              // Warning if max fouls
              if (isMaxFouls) ...[
                SizedBox(width: 6),
                Icon(Icons.warning, color: Colors.red, size: 16),
              ],
            ],
          ),
          
          // Timeouts (only if enabled)
          if (settingEnableTimeouts) ...[
            SizedBox(height: 6),
            GestureDetector(
              onTap: () => _useTimeout(isHome),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('TO ', style: TextStyle(color: Colors.white38, fontSize: 10)),
                  ...List.generate(settingTimeoutsPerTeam, (i) => Container(
                    margin: EdgeInsets.symmetric(horizontal: 1),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < timeouts ? Colors.green : Colors.grey[700],
                    ),
                  )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _bigScoreButton(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: Text(
          label,
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
  
  void _editTeamName(bool isHome) {
    final controller = TextEditingController(text: isHome ? homeTeam : awayTeam);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Color(0xFF1a1a2e),
        title: Text('Team Name', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller, 
          autofocus: true,
          style: TextStyle(color: Colors.black),
          cursorColor: Colors.blue,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.blue, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () {
              setState(() {
                if (isHome) {
                  homeTeam = controller.text.toUpperCase();
                } else {
                  awayTeam = controller.text.toUpperCase();
                }
              });
              Navigator.pop(ctx);
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }
}
