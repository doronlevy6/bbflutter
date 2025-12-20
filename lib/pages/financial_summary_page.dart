import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import '../widgets/basketball_spinner.dart';

class FinancialSummaryPage extends StatefulWidget {
  @override
  _FinancialSummaryPageState createState() => _FinancialSummaryPageState();
}

class _FinancialSummaryPageState extends State<FinancialSummaryPage> {
  final ApiService apiService = ApiService();
  bool isLoading = true;
  List<dynamic> players = [];
  int defaultCost = 0;
  String? errorMessage;
  bool fromCache = false;

  // Summary stats
  int totalDebt = 0;
  int totalPaid = 0;
  int totalBalance = 0;
  int pendingQueue = 0;
  int lastSyncedCount = 0;
  String? lastSyncedAt;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<bool>? _syncSub;
  bool _isSyncing = false;
  bool _autoRefreshing = false;
  String _preloadStatus = 'idle';
  String? _preloadUpdatedAt;

  // Sorting state
  String _sortBy = 'name'; // 'name' or 'balance'
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadQueueStats();
    _startConnectivityListener();
    _startSyncListener();
    _loadPreloadStatus();
  }

  void _startConnectivityListener() {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (hasConnection) {
        // Just got online!
        _handleOnlineRefresh(); 
      }
    });
  }

  void _startSyncListener() {
    _syncSub = apiService.isSyncing.listen((isSyncing) {
      if (mounted) {
        setState(() {
          _isSyncing = isSyncing;
        });
        if (!isSyncing) {
          // Sync finished, reload queue stats
          _loadQueueStats();
        }
      }
    });
  }

  Future<void> _handleOnlineRefresh() async {
    if (_autoRefreshing) return;
    _autoRefreshing = true;
    try {
      await apiService.processQueue();
      await _loadData();
      await _loadPreloadStatus();
    } finally {
      _autoRefreshing = false;
    }
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final response = await apiService.getWithCache('finance/team-financial-summary/1', cacheKey: 'cache_team_summary_1');
      if (response['success'] == true) {
        setState(() {
          players = response['summary'] ?? [];
          defaultCost = response['defaultGameCost'] ?? 0;
          fromCache = response['_cached'] == true;
          
          // Calculate totals
          totalDebt = 0;
          totalPaid = 0;
          totalBalance = 0;
          for (var p in players) {
            totalDebt += (p['debt'] as int? ?? 0);
            totalPaid += (p['paid'] as int? ?? 0);
            totalBalance += (p['balance'] as int? ?? 0);
          }

          _applySorting();
          
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = response['message'];
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Offline and no cached data yet.';
        isLoading = false;
      });
    }
    _loadQueueStats();
  }

  Future<void> _loadQueueStats() async {
    try {
      final stats = await apiService.getQueueStats();
      setState(() {
        pendingQueue = stats['pending'] ?? 0;
        lastSyncedCount = stats['last_synced_count'] ?? 0;
        lastSyncedAt = stats['last_synced_at'] as String?;
      });
    } catch (_) {}
  }

  Future<void> _loadPreloadStatus() async {
    try {
      final status = await apiService.getPreloadStatus();
      setState(() {
        _preloadStatus = status['status'] ?? 'idle';
        _preloadUpdatedAt = status['updatedAt'] as String?;
      });
    } catch (_) {}
  }

  void _applySorting() {
    players.sort((a, b) {
      int cmp;
      if (_sortBy == 'balance') {
        final int aBalance = a['balance'] as int? ?? 0;
        final int bBalance = b['balance'] as int? ?? 0;
        cmp = aBalance.compareTo(bBalance);
      } else {
        final String aName = (a['username'] ?? '') as String;
        final String bName = (b['username'] ?? '') as String;
        cmp = aName.toLowerCase().compareTo(bName.toLowerCase());
      }
      return _sortAscending ? cmp : -cmp;
    });
  }


  Future<void> _openPlayerFinancials(String username) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final res = await apiService.getWithCache('finance/player-financials/$username', cacheKey: 'cache_player_financials_$username');
      Navigator.of(context).pop();
      if (!mounted) return;
      if (res['success'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${res['message'] ?? 'Failed to load'}')),
        );
        return;
      }

      final balance = res['balance'] ?? 0;
      final historyObj = res['history'] as Map<String, dynamic>? ?? {};
      final games = (historyObj['games'] as List<dynamic>? ?? [])
          .map<Map<String, dynamic>>((g) => {
                'type': 'game',
                'date': g['date'],
                'amount': -1 * ((g['applied_cost'] ?? 0) as num),
                'desc': 'Game ${g['notes'] ?? ''}',
              })
          .toList();
      final payments = (historyObj['payments'] as List<dynamic>? ?? [])
          .map<Map<String, dynamic>>((p) => {
                'type': 'payment',
                'date': p['date'],
                'amount': p['amount'] ?? 0,
                'desc': 'Payment (${p['method'] ?? ''})',
              })
          .toList();
      final entries = [...games, ...payments]
        ..sort((a, b) => DateTime.parse(b['date']).compareTo(DateTime.parse(a['date'])));

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('$username • $balance₪'),
          content: SizedBox(
            width: 320,
            height: 320,
            child: entries.isEmpty
                ? const Center(child: Text('No data'))
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 12),
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      final amt = e['amount'] as num? ?? 0;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e['desc'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(e['date'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                              Text(
                                '${amt >= 0 ? '+' : ''}$amt₪',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: amt >= 0 ? Colors.green[700] : Colors.red[700],
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      Navigator.of(context).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Widget _buildSortChip(String label, String field) {
    final bool active = _sortBy == field;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (_) {
        setState(() {
          _sortBy = field;
          _applySorting();
        });
      },
    );
  }



  Widget _buildQueueInfo() {
    final syncedInfo = lastSyncedAt != null
        ? 'Last synced: $lastSyncedCount at ${DateTime.tryParse(lastSyncedAt!) != null ? _fmtTime(DateTime.parse(lastSyncedAt!)) : lastSyncedAt}'
        : 'No sync yet';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Offline queue: $pendingQueue pending', style: TextStyle(fontSize: 12, color: Colors.grey[800])),
          Text(syncedInfo, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  String _fmtTime(DateTime d) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }

  Widget _buildPreloadStatus() {
    String text;
    Color color;
    IconData icon;
    if (_preloadStatus == 'in_progress') {
      text = 'Refreshing cache in background…';
      color = Colors.orange[800]!;
      icon = Icons.cloud_download;
    } else if (_preloadStatus == 'ready') {
      text = 'Cache up to date';
      color = Colors.green[800]!;
      icon = Icons.check_circle;
    } else if (_preloadStatus == 'failed') {
      text = 'Cache refresh failed';
      color = Colors.red[700]!;
      icon = Icons.error_outline;
    } else {
      return SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color),
          SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _syncSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: isLoading
          ? Center(child: BasketballSpinner(size: 80))
          : errorMessage != null
              ? Center(child: Text('Offline/no cache yet. Connect once to load data.', style: TextStyle(color: Colors.orange[700])))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: _buildContent(),
                ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        if (fromCache)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('Showing cached data (offline)', style: TextStyle(color: Colors.orange[700], fontSize: 12)),
          ),
        
        // SYNC INDICATOR
        if (_isSyncing)
          Container(
            width: double.infinity,
            color: Colors.blue[50], // Light blue bg
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                BasketballSpinner(size: 16), // Mini spinner
                SizedBox(width: 8),
                Text('Syncing changes...', style: TextStyle(fontSize: 12, color: Colors.blue[800])),
              ],
            ),
          ),

        _buildPreloadStatus(),
        _buildQueueInfo(),
        // SUMMARY CARDS - more compact
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: Colors.teal[50], // Light teal bg
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSummaryCard('Debt', totalDebt, Colors.red),
              _buildSummaryCard('Paid', totalPaid, Colors.green),
              _buildSummaryCard('Balance', totalBalance, totalBalance >= 0 ? Colors.green : Colors.red),
            ],
          ),
        ),
        
        // INFO ROW
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${players.length} players', style: TextStyle(fontSize: 11, color: Colors.grey)),
              Text('Game: $defaultCost₪', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
        
        Divider(height: 1),

        // SORT CONTROLS
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              _buildSortChip('Name', 'name'),
              SizedBox(width: 8),
              _buildSortChip('Balance', 'balance'),
              Spacer(),
              IconButton(
                icon: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 18),
                tooltip: 'Toggle sort direction',
                onPressed: () {
                  setState(() {
                    _sortAscending = !_sortAscending;
                    _applySorting();
                  });
                },
              ),
            ],
          ),
        ),

        // PLAYER LIST - COMPACT / GRID WHEN SPACE ALLOWS
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width > 1100 ? 3 : (width > 700 ? 2 : 1);
              final childAspectRatio = crossAxisCount == 1
                  ? 4.5
                  : crossAxisCount == 2
                      ? 3.8
                      : 3.2;
              return GridView.builder(
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: childAspectRatio,
                ),
                itemCount: players.length,
                itemBuilder: (context, index) {
                  final player = players[index];
                  final balance = player['balance'] as int? ?? 0;
                  final customCost = player['custom_game_cost'] as int?;
                  final playerCost = customCost ?? defaultCost;
                  final isCached = fromCache;
                  final tileColor = isCached ? Colors.orange[50] : Colors.white;

                  // Calculate games and remainder
                  int games = 0;
                  int remainder = balance;
                  if (playerCost > 0) {
                    games = balance ~/ playerCost; // Floor division
                    remainder = balance - (games * playerCost);
                  }

                  final bool isPositive = balance >= 0;

                  return InkWell(
                    onTap: () => _openPlayerFinancials(player['username']),
                    child: Stack(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: tileColor,
                            border: Border(
                              bottom: BorderSide(color: Colors.grey[200]!, width: 0.5),
                              right: BorderSide(
                                color: crossAxisCount > 1 && (index % crossAxisCount != crossAxisCount - 1)
                                    ? Colors.grey[200]!
                                    : Colors.transparent,
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Status icon - small
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: isPositive ? Colors.green[50] : Colors.red[50],
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isPositive ? Icons.check : Icons.warning,
                                  size: 14,
                                  color: isPositive ? Colors.green : Colors.red,
                                ),
                              ),
                              SizedBox(width: 10),

                              // Name only
                              Expanded(
                                flex: 2,
                                child: Text(
                                  player['username'],
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),

                              // Balance + games/remainder (compact right side)
                              SizedBox(
                                width: 72,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '$balance₪',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isPositive ? Colors.green[700] : Colors.red[700],
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${games >= 0 ? (games > 0 ? '+' : '') : ''}$games',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: isPositive ? Colors.green[700] : Colors.red[700],
                                          ),
                                        ),
                                        SizedBox(width: 2),
                                        Icon(Icons.sports_basketball, size: 13, color: Colors.grey),
                                      ],
                                    ),
                                    if (remainder != 0)
                                      Text(
                                        '${remainder >= 0 ? '+' : ''}$remainder₪',
                                        style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isCached)
                          Positioned(
                            top: 6,
                            right: 8,
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange[200],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('Cache', style: TextStyle(fontSize: 10, color: Colors.orange[900])),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String label, int value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          SizedBox(height: 4),
          Text('$value ₪', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
