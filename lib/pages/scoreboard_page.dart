import 'package:flutter/material.dart';
import 'dart:async';

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
  
  // Timeouts (5 per game)
  int homeTimeouts = 5;
  int awayTimeouts = 5;
  
  // Game State
  int quarter = 1;
  bool isOvertime = false;
  
  // Clocks
  int gameClockSeconds = 10 * 60; // 10 minutes per quarter
  int shotClockSeconds = 24;
  bool isRunning = false;
  Timer? gameTimer;
  
  // Possession (true = home, false = away)
  bool homePossession = true;
  
  // Undo History
  List<Map<String, dynamic>> history = [];
  
  @override
  void dispose() {
    gameTimer?.cancel();
    super.dispose();
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
      shotClockSeconds = 24;
      homePossession = !isHome; // Possession changes after score
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
      shotClockSeconds = 24;
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
    gameTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        if (shotClockSeconds > 0) shotClockSeconds--;
        if (gameClockSeconds > 0) {
          gameClockSeconds--;
        } else {
          _pauseClock();
          _endQuarter();
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
        gameClockSeconds = 10 * 60;
        homeFouls = 0;
        awayFouls = 0;
      } else {
        isOvertime = true;
        gameClockSeconds = 5 * 60;
      }
      shotClockSeconds = 24;
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
        title: Text('Reset Game?'),
        content: Text('This will clear all scores and start fresh.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                homeScore = 0;
                awayScore = 0;
                homeFouls = 0;
                awayFouls = 0;
                homeTimeouts = 5;
                awayTimeouts = 5;
                quarter = 1;
                isOvertime = false;
                gameClockSeconds = 10 * 60;
                shotClockSeconds = 24;
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
    final isBonus = (fouls) => fouls >= 5;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 600;
    
    return Scaffold(
      backgroundColor: Color(0xFF1a1a2e),
      appBar: AppBar(
        backgroundColor: Color(0xFF16213e),
        foregroundColor: Colors.white,
        title: Text('Scoreboard'),
        actions: [
          IconButton(
            icon: Icon(Icons.undo, color: history.isEmpty ? Colors.grey : Colors.white),
            onPressed: history.isEmpty ? null : _undo,
            tooltip: 'Undo',
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _resetGame,
            tooltip: 'Reset Game',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // CLOCK BAR
            Container(
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              color: Color(0xFF16213e),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Quarter
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange[700],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isOvertime ? 'OT' : 'Q$quarter',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  
                  // Game Clock
                  GestureDetector(
                    onTap: _startPauseClock,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: isRunning ? Colors.green[700] : Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _formatTime(gameClockSeconds),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                  
                  // Shot Clock
                  GestureDetector(
                    onTap: () => _resetShotClock(24),
                    onDoubleTap: () => _resetShotClock(14),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: shotClockSeconds <= 5 ? Colors.red : Colors.red[900],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$shotClockSeconds',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // MAIN CONTENT
            Expanded(
              child: isWide ? _buildWideLayout() : _buildMobileLayout(),
            ),
            
            // POSSESSION BAR
            Container(
              padding: EdgeInsets.symmetric(vertical: 8),
              color: Color(0xFF16213e),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.arrow_left,
                    size: 30,
                    color: homePossession ? Colors.yellow : Colors.grey[700],
                  ),
                  GestureDetector(
                    onTap: _togglePossession,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'POSSESSION',
                        style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 2),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_right,
                    size: 30,
                    color: !homePossession ? Colors.yellow : Colors.grey[700],
                  ),
                ],
              ),
            ),
            
            // ACTION BAR
            Container(
              padding: EdgeInsets.all(12),
              color: Color(0xFF0f0f23),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _actionButton(
                    icon: isRunning ? Icons.pause : Icons.play_arrow,
                    label: isRunning ? 'PAUSE' : 'START',
                    color: isRunning ? Colors.orange : Colors.green,
                    onTap: _startPauseClock,
                  ),
                  _actionButton(
                    icon: Icons.skip_next,
                    label: 'NEXT Q',
                    color: Colors.blue,
                    onTap: _nextQuarter,
                  ),
                  _actionButton(
                    icon: Icons.timer,
                    label: '24s',
                    color: Colors.red,
                    onTap: () => _resetShotClock(24),
                  ),
                  _actionButton(
                    icon: Icons.timer,
                    label: '14s',
                    color: Colors.red[300]!,
                    onTap: () => _resetShotClock(14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildTeamPanel(true),
          Divider(color: Colors.grey[700], height: 1),
          _buildTeamPanel(false),
        ],
      ),
    );
  }
  
  Widget _buildWideLayout() {
    return Row(
      children: [
        Expanded(child: _buildTeamPanel(true)),
        VerticalDivider(color: Colors.grey[700], width: 1),
        Expanded(child: _buildTeamPanel(false)),
      ],
    );
  }
  
  Widget _buildTeamPanel(bool isHome) {
    final score = isHome ? homeScore : awayScore;
    final fouls = isHome ? homeFouls : awayFouls;
    final timeouts = isHome ? homeTimeouts : awayTimeouts;
    final teamName = isHome ? homeTeam : awayTeam;
    final teamColor = isHome ? Colors.blue : Colors.red;
    final isBonus = fouls >= 5;
    
    return Container(
      padding: EdgeInsets.all(16),
      color: isHome ? Color(0xFF1a1a3e) : Color(0xFF2a1a1a),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Team Name
          GestureDetector(
            onTap: () => _editTeamName(isHome),
            child: Text(
              teamName,
              style: TextStyle(color: Colors.white70, fontSize: 16, letterSpacing: 2),
            ),
          ),
          SizedBox(height: 8),
          
          // Score
          Text(
            '$score',
            style: TextStyle(
              color: Colors.white,
              fontSize: 80,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 12),
          
          // Score Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _scoreButton('+1', teamColor[300]!, () => _addScore(isHome, 1)),
              SizedBox(width: 8),
              _scoreButton('+2', teamColor, () => _addScore(isHome, 2)),
              SizedBox(width: 8),
              _scoreButton('+3', teamColor[700]!, () => _addScore(isHome, 3)),
            ],
          ),
          SizedBox(height: 16),
          
          // Fouls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _addFoul(isHome),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isBonus ? Colors.yellow[700] : Colors.grey[800],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Text('FOULS: ', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Text('$fouls', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      if (isBonus) ...[
                        SizedBox(width: 4),
                        Icon(Icons.warning, color: Colors.red, size: 16),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          
          // Timeouts
          GestureDetector(
            onTap: () => _useTimeout(isHome),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('TO: ', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ...List.generate(5, (i) => Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                    Icons.circle,
                    size: 14,
                    color: i < timeouts ? Colors.green : Colors.grey[700],
                  ),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _scoreButton(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
  
  Widget _actionButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          SizedBox(height: 4),
          Text(label, style: TextStyle(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  }
  
  void _editTeamName(bool isHome) {
    final controller = TextEditingController(text: isHome ? homeTeam : awayTeam);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Team Name'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
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
            child: Text('Save'),
          ),
        ],
      ),
    );
  }
}
