import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../model/player.dart';
import '../utils/calc.dart';
import '../services/rankings_service.dart';
import '../widgets/icon_butten_with_label.dart';

class InteractivePlaygroundPage extends StatefulWidget {
  const InteractivePlaygroundPage({Key? key}) : super(key: key);

  @override
  _InteractivePlaygroundPageState createState() => _InteractivePlaygroundPageState();
}

class _InteractivePlaygroundPageState extends State<InteractivePlaygroundPage> {
  // Settings
  int _numberOfTeams = 3;
  int _playersPerTeam = 5;
  bool _isHebrew = false;
  
  // User specific settings
  bool _isDoron = false;
  bool _useUserRankings = false;
  String? _userName;

  // Data
  List<Player> _allPlayers = [];
  List<Player> _overallPlayers = [];
  List<Player> _userPlayers = [];
  
  Set<String> _selectedPlayerUsernames = {};
  List<List<Player>> _teams = List.generate(3, (_) => []);
  
  // Track manually placed players (via drag-and-drop)
  Set<String> _manuallyPlacedPlayers = {};
  
  // Loading state
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _refreshAndLoadData();
  }

  Future<void> _refreshAndLoadData() async {
    setState(() => _isLoading = true);
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      _userName = prefs.getString('user');
      _isDoron = _userName?.toLowerCase() == 'doron';

      // 1. Load players from cache (Local Storage only)
      await _loadPlayers();

      // 2. Load selection
      await _loadInitialSelection();
    } catch (e) {
      print('Error refreshing data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _isHebrew = prefs.getBool('is_hebrew') ?? false;
      _numberOfTeams = prefs.getInt('numberOfTeams') ?? 3;
      _playersPerTeam = prefs.getInt('playersPerTeam') ?? 5;
    });
  }

  Future<void> _loadPlayers() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    
    // Load Overall
    String? overallJson = prefs.getString('overallPlayersRankings');
    if (overallJson != null) {
      List<dynamic> data = jsonDecode(overallJson);
      _overallPlayers = data.map((d) => Player.fromJson(d)).toList();
    }

    // Load User Specific
    if (_isDoron) {
      String? userJson = prefs.getString('playersRankings_$_userName');
      if (userJson != null) {
        List<dynamic> data = jsonDecode(userJson);
        _userPlayers = data.map((d) => Player.fromJson(d)).toList();
      }
    }

    _updateActivePlayerList();
  }

  void _updateActivePlayerList() {
    setState(() {
      if (_useUserRankings && _isDoron && _userPlayers.isNotEmpty) {
        _allPlayers = List.from(_userPlayers);
      } else {
        _allPlayers = List.from(_overallPlayers);
      }
      _sortPlayers();
      _refreshTeamPlayers(); // Update player objects in teams to match new stats
    });
  }

  void _refreshTeamPlayers() {
    // Replaces player objects in teams with the ones from the active list
    // to ensure stats are correct
    for (int i = 0; i < _teams.length; i++) {
      List<Player> newTeam = [];
      for (var p in _teams[i]) {
        var match = _allPlayers.firstWhere(
          (ap) => ap.username == p.username, 
          orElse: () => p
        );
        newTeam.add(match);
      }
      _teams[i] = newTeam;
    }
  }

  void _toggleRankingSource(bool useUser) {
    setState(() {
      _useUserRankings = useUser;
      _updateActivePlayerList();
    });
  }

  Future<void> _loadInitialSelection() async {
     SharedPreferences prefs = await SharedPreferences.getInstance();
     List<String>? saved = prefs.getStringList('interactive_selection');
     
     if (saved != null && saved.isNotEmpty) {
       setState(() {
         _selectedPlayerUsernames = saved.toSet();
         _initializeTeams();
       });
     } else {
       // Default to enlisted
       await _loadEnlistedPlayers();
     }
     _sortPlayers(); // Sort after loading selection
  }

  Future<void> _saveSelection() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setStringList('interactive_selection', _selectedPlayerUsernames.toList());
  }

  Future<void> _loadEnlistedPlayers() async {
    // setState(() => _isLoading = true); // Handled by caller or separate button
    try {
      // Load from local storage only (as requested)
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> enlistedUsernames = prefs.getStringList('enlistedPlayers') ?? [];
      
      setState(() {
        _selectedPlayerUsernames.clear();
        _selectedPlayerUsernames.addAll(enlistedUsernames);
        _initializeTeams();
      });
      _saveSelection(); // Save this as the new selection
      _sortPlayers(); // Sort after loading selection
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isHebrew ? 'נרשמים נטענו בהצלחה' : 'Enlisted players loaded')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading enlisted: $e')),
      );
    } 
    // finally { setState(() => _isLoading = false); }
  }

  void _initializeTeams() {
    List<List<Player>> newTeams = List.generate(_numberOfTeams, (_) => []);
    // Try to preserve existing players in teams if they are still selected
    for (int i = 0; i < _teams.length && i < _numberOfTeams; i++) {
      for (var player in _teams[i]) {
        if (_selectedPlayerUsernames.contains(player.username)) {
          newTeams[i].add(player);
        }
      }
    }
    _teams = newTeams;
  }

  void _toggleSelection(Player player) {
    setState(() {
      if (_selectedPlayerUsernames.contains(player.username)) {
        _selectedPlayerUsernames.remove(player.username);
        // Remove from teams if present
        for (var team in _teams) {
          team.removeWhere((p) => p.username == player.username);
        }
      } else {
        _selectedPlayerUsernames.add(player.username);
      }
      _saveSelection();
      _sortPlayers(); // Re-sort to move selected players to top
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedPlayerUsernames.clear();
      _initializeTeams();
      _manuallyPlacedPlayers.clear();
      _saveSelection();
      _sortPlayers(); // Re-sort after clearing selection
    });
  }

  void _clearAutoPlayers() {
    setState(() {
      // Remove only players that are NOT in the manually placed set
      for (int i = 0; i < _teams.length; i++) {
        _teams[i].removeWhere((p) => !_manuallyPlacedPlayers.contains(p.username));
      }
      
      // Feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isHebrew 
            ? 'נמחקו שחקנים שנוספו אוטומטית' 
            : 'Removed auto-balanced players'),
          duration: Duration(milliseconds: 1000),
        ),
      );
    });
  }

  void _clearAllTeams() {
    setState(() {
      // Explicitly create empty teams (don't use _initializeTeams as it preserves players)
      _teams = List.generate(_numberOfTeams, (_) => []);
      _manuallyPlacedPlayers.clear();
      
      // Feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isHebrew 
            ? 'כל הקבוצות נוקו' 
            : 'All teams cleared'),
          duration: Duration(milliseconds: 1000),
        ),
      );
    });
  }

  void _removePlayerFromTeam(Player player) {
    setState(() {
      for (var team in _teams) {
        team.removeWhere((p) => p.username == player.username);
      }
      _manuallyPlacedPlayers.remove(player.username);
    });
  }

  void _onDropToTeam(Player player, int teamIndex) {
    setState(() {
      // Remove from other teams if present
      for (var team in _teams) {
        team.removeWhere((p) => p.username == player.username);
      }

      // Add to new team
      if (_teams[teamIndex].length < _playersPerTeam) {
        _teams[teamIndex].add(player);
        _manuallyPlacedPlayers.add(player.username); // Track as manually placed
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isHebrew ? 'הקבוצה מלאה' : 'Team is full')),
        );
      }
    });
  }

  void _smartBalance() {
    setState(() {
      // Get pool of selected players NOT currently in any team
      List<Player> pool = _allPlayers.where((p) {
        bool isSelected = _selectedPlayerUsernames.contains(p.username);
        bool isInTeam = _teams.any((team) => team.any((tp) => tp.username == p.username));
        return isSelected && !isInTeam;
      }).toList();

      // Distribute
      _teams = distributePlayersWithConstraints(_teams, pool, _playersPerTeam);
      // Note: players added by smart balance are NOT marked as manually placed
    });
  }

  // ... (existing code)



  double _getTeamAverage(List<Player> team) {
    if (team.isEmpty) return 0.0;
    double total = team.fold(0.0, (sum, p) => sum + computeTotalRanking(p));
    // Average score per player (divided by 6 parameters)
    // Then average of the team
    return (total / 6) / team.length;
  }
  
  double _getPlayerAverage(Player player) {
    return computeTotalRanking(player) / 6;
  }

  // Sorting state
  bool _isAscending = true;

  void _toggleSort() {
    setState(() {
      _isAscending = !_isAscending;
      _sortPlayers();
    });
  }

  void _sortPlayers() {
    _allPlayers.sort((a, b) {
      // First, sort by selection status (selected players first)
      bool aSelected = _selectedPlayerUsernames.contains(a.username);
      bool bSelected = _selectedPlayerUsernames.contains(b.username);
      
      if (aSelected != bSelected) {
        return aSelected ? -1 : 1; // Selected players come first
      }
      
      // Within same selection status, sort alphabetically (case-insensitive)
      String aName = a.username.toLowerCase();
      String bName = b.username.toLowerCase();
      return _isAscending 
          ? aName.compareTo(bName) 
          : bName.compareTo(aName);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Calculate selected count
    int selectedCount = _selectedPlayerUsernames.length;

    return Directionality(
      textDirection: _isHebrew ? TextDirection.rtl : TextDirection.ltr,
      child: Row(
        children: [
          // Left Column: Player Selection
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.grey[100],
              child: Column(
                children: [
                  // Actions Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Selected Count
                            Text(
                              _isHebrew 
                                  ? 'נבחרו: $selectedCount' 
                                  : 'Selected: $selectedCount',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800],
                              ),
                            ),
                            // Sort Button
                            IconButton(
                              icon: Icon(
                                _isAscending ? Icons.arrow_downward : Icons.arrow_upward,
                                color: Colors.grey[700],
                                size: 20,
                              ),
                              tooltip: _isHebrew ? 'מיון א-ת' : 'Sort A-Z',
                              onPressed: _toggleSort,
                            ),
                            // User Rankings Toggle (Doron only)
                            if (_isDoron)
                              IconButton(
                                icon: Icon(
                                  _useUserRankings ? Icons.person : Icons.group,
                                  color: _useUserRankings ? Colors.blue : Colors.grey[700],
                                  size: 20,
                                ),
                                tooltip: _useUserRankings 
                                    ? (_isHebrew ? 'הציונים שלי' : 'My Rankings')
                                    : (_isHebrew ? 'ממוצע כללי' : 'Overall Average'),
                                onPressed: () => _toggleRankingSource(!_useUserRankings),
                              ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButtonWithLabel(
                              icon: Icons.refresh,
                              label: _isHebrew ? 'נקה' : 'Clear',
                              onPressed: _clearSelection,
                            ),
                            IconButtonWithLabel(
                              icon: Icons.cloud_download,
                              label: _isHebrew ? 'נרשמים' : 'Enlisted',
                              onPressed: _isLoading ? () {} : _loadEnlistedPlayers,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Player List
                  Expanded(
                    child: ListView.builder(
                      itemCount: _allPlayers.length,
                      itemBuilder: (context, index) {
                        final player = _allPlayers[index];
                        final isSelected = _selectedPlayerUsernames.contains(player.username);
                        final isInTeam = _teams.any((t) => t.any((p) => p.username == player.username));
                        
                        return _buildPlayerListItem(player, isSelected, isInTeam);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Right Column: Teams & Settings
          Expanded(
            flex: 7,
            child: Column(
              children: [
                // Compact Settings Bar
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: Colors.green[50],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Teams Control
                      _buildCompactControl(
                        label: _isHebrew ? 'קבוצות' : 'Teams',
                        value: _numberOfTeams,
                        min: 2,
                        max: 6,
                        onChanged: (val) {
                          setState(() {
                            _numberOfTeams = val;
                            _initializeTeams();
                          });
                        },
                      ),
                      // Players Control
                      _buildCompactControl(
                        label: _isHebrew ? 'שחקנים' : 'Players',
                        value: _playersPerTeam,
                        min: 2,
                        max: 11,
                        onChanged: (val) {
                          setState(() {
                            _playersPerTeam = val;
                          });
                        },
                      ),
                      // Smart Balance Button
                      ElevatedButton.icon(
                        onPressed: _smartBalance,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          minimumSize: Size(0, 36),
                        ),
                        icon: Icon(Icons.auto_fix_high, size: 16),
                        label: Text(_isHebrew ? 'מלא' : 'Fill', style: TextStyle(fontSize: 12)),
                      ),
                      // Clear Teams Button (Custom for Double Tap)
                      Material(
                        color: Colors.orange[700],
                        borderRadius: BorderRadius.circular(20),
                        elevation: 2,
                        child: InkWell(
                          onTap: _clearAutoPlayers,
                          onDoubleTap: _clearAllTeams,
                          onLongPress: _clearAllTeams, // Added Long Press support
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            constraints: BoxConstraints(minHeight: 36),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cleaning_services, size: 16, color: Colors.white),
                                SizedBox(width: 8),
                                Text(_isHebrew ? 'נקה' : 'Clear', style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Teams Area - 2 Column Grid
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(8),
                    child: GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.8,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _numberOfTeams,
                      itemBuilder: (context, index) => _buildTeamColumn(index),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactControl({
    required String label,
    required int value,
    required int min,
    required int max,
    required Function(int) onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green[900])),
        SizedBox(width: 4),
        InkWell(
          onTap: value > min ? () => onChanged(value - 1) : null,
          child: Container(
            padding: EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.green[100],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.green[300]!),
            ),
            child: Icon(Icons.remove, size: 16, color: Colors.green[700]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.0),
          child: Text('$value', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[900])),
        ),
        InkWell(
          onTap: value < max ? () => onChanged(value + 1) : null,
          child: Container(
            padding: EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.green[100],
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.green[300]!),
            ),
            child: Icon(Icons.add, size: 16, color: Colors.green[700]),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerListItem(Player player, bool isSelected, bool isInTeam) {
    Widget content = Container(
      margin: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: isSelected ? Colors.green[50] : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected ? Colors.green[200]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.check_circle : Icons.circle_outlined,
            color: isSelected ? Colors.green : Colors.grey[400],
            size: 16,
          ),
          SizedBox(width: 4),
          Expanded(
            child: Text(
              player.username,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isInTeam ? Colors.grey : Colors.black,
                decoration: isInTeam ? TextDecoration.lineThrough : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isSelected)
            Text(
              _getPlayerAverage(player).toStringAsFixed(1),
              style: TextStyle(fontSize: 10, color: Colors.green[800], fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );

    // Only selected players can be dragged
    if (isSelected && !isInTeam) {
      return Draggable<Player>(
        data: player,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            width: 150,
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black26)],
            ),
            child: Row(
              children: [
                Icon(Icons.person, color: Colors.green),
                SizedBox(width: 8),
                Text(player.username, style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        child: InkWell(
          onTap: () => _toggleSelection(player),
          child: content,
        ),
      );
    } else {
      return InkWell(
        onTap: () => _toggleSelection(player),
        child: content,
      );
    }
  }

  Widget _buildTeamColumn(int index) {
    List<Player> team = _teams[index];
    double avg = _getTeamAverage(team);
    
    return DragTarget<Player>(
      onWillAccept: (data) => team.length < _playersPerTeam,
      onAccept: (player) => _onDropToTeam(player, index),
      builder: (context, candidateData, rejectedData) {
        return Container(
          margin: EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: candidateData.isNotEmpty ? Colors.green : Colors.grey[300]!,
              width: candidateData.isNotEmpty ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            children: [
              // Team Header
              Container(
                padding: EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green[900]),
                  ),
                ),
              ),
              // Team Players
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.all(4),
                  itemCount: team.length,
                  itemBuilder: (context, playerIndex) {
                    return _buildTeamPlayerCard(team[playerIndex]);
                  },
                ),
              ),
              // Team Footer (Average)
              Container(
                padding: EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(top: BorderSide(color: Colors.grey[200]!)),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
                ),
                child: Column(
                  children: [
                    Text(
                      'Avg: ${avg.toStringAsFixed(2)}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[800], fontSize: 12),
                    ),
                    Text(
                      '${team.length}/$_playersPerTeam',
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTeamPlayerCard(Player player) {
    return Draggable<Player>(
      data: player,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.7,
          child: Container(
            width: 100,
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black26)],
            ),
            child: Text(player.username),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _teamPlayerContent(player)),
      child: InkWell(
        onTap: () => _removePlayerFromTeam(player),
        child: _teamPlayerContent(player),
      ),
    );
  }
  
  Widget _teamPlayerContent(Player player) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 2),
      padding: EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.green[100]!),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 1)],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: Colors.green[200],
            child: Text(player.username[0].toUpperCase(), style: TextStyle(fontSize: 10, color: Colors.white)),
          ),
          SizedBox(width: 4),
          Expanded(
            child: Text(
              player.username,
              style: TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
