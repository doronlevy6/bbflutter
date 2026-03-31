import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import '../../widgets/basketball_spinner.dart';
import '../../pages/player_management_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  int failedQueue = 0;
  int lastSyncedCount = 0;
  String? lastSyncedAt;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  StreamSubscription<bool>? _syncSub;
  bool _isSyncing = false;
  bool _autoRefreshing = false;
  String _preloadStatus = 'idle';
  String? _preloadUpdatedAt;
  String? _lastServerRefreshAt;

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
    // 1. Get Team ID
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final teamId = prefs.getInt('team_id');
    if (teamId == null) {
      setState(() {
        errorMessage = 'Missing team id. Please login again.';
        isLoading = false;
      });
      return;
    }
    String cacheKey = 'cache_team_summary_$teamId';

    // 2. Try to load from cache immediately (Stale-while-revalidate)
    final cachedData = await apiService.getFromCacheOnly(cacheKey);
    if (cachedData != null && mounted) {
      _processData(cachedData);
      setState(() => isLoading = false);
    } else {
      setState(() => isLoading = true);
    }

    // 3. Update from Network (background)
    try {
      final response = await apiService.getWithCache(
          'finance/team-financial-summary/$teamId',
          cacheKey: cacheKey);
      if (mounted) {
        if (response['success'] == true) {
          _processData(response);
        } else {
          // If network failed but we had cache, we are fine. If no cache, show error.
          if (players.isEmpty) {
            setState(() => errorMessage = response['message']);
          }
        }
      }
    } catch (e) {
      if (mounted && players.isEmpty) {
        setState(() => errorMessage = 'Offline and no cached data yet.');
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
    _loadQueueStats();
  }

  void _processData(Map<String, dynamic> response) {
    setState(() {
      players = response['summary'] ?? [];
      defaultCost = response['defaultGameCost'] ?? 0;
      fromCache = response['_cached'] == true;
      _lastServerRefreshAt = response['_cache_updated_at'] as String?;

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
    });
  }

  Future<void> _loadQueueStats() async {
    try {
      final stats = await apiService.getQueueStats();
      setState(() {
        pendingQueue = stats['pending'] ?? 0;
        failedQueue = stats['failed'] ?? 0;
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
      builder: (context) =>
          PlayerFinancialDialog(username: username, apiService: apiService),
    ).then((_) {
      // Refresh data after dialog closes
      _loadData();
    });
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
    final queueInfo = lastSyncedAt != null
        ? 'Queue synced: $lastSyncedCount at ${DateTime.tryParse(lastSyncedAt!) != null ? _fmtDateTime(DateTime.parse(lastSyncedAt!)) : lastSyncedAt}'
        : 'Queue not synced yet';
    final serverInfo = _lastServerRefreshAt != null
        ? 'Server data updated: ${DateTime.tryParse(_lastServerRefreshAt!) != null ? _fmtDateTime(DateTime.parse(_lastServerRefreshAt!)) : _lastServerRefreshAt}'
        : 'Server data not loaded yet';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Offline queue: $pendingQueue pending${failedQueue > 0 ? " | $failedQueue failed" : ""}',
            style: TextStyle(fontSize: 12, color: Colors.grey[800]),
          ),
          SizedBox(height: 2),
          Text(
            queueInfo,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          SizedBox(height: 2),
          Text(
            serverInfo,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  String _fmtDateTime(DateTime d) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
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

  void _showPendingQueueDialog() async {
    final items = await apiService.getQueueItems();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.cloud_off, color: Colors.orange),
              SizedBox(width: 8),
              Text('Pending Actions (${items.length})'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 48),
                        SizedBox(height: 8),
                        Text('No pending actions',
                            style: TextStyle(fontSize: 16)),
                        Text('All synced!',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final method = item['method'] ?? 'POST';
                      final endpoint = item['endpoint'] ?? '';
                      final createdAt = item['created_at'] ?? '';
                      final attempts = item['attempts'] ?? 0;

                      String description =
                          _getActionDescription(method, endpoint, item['body']);

                      return Card(
                        child: ListTile(
                          leading: Icon(
                            method == 'DELETE'
                                ? Icons.delete
                                : Icons.cloud_upload,
                            color:
                                method == 'DELETE' ? Colors.red : Colors.blue,
                          ),
                          title:
                              Text(description, style: TextStyle(fontSize: 13)),
                          subtitle: Text(
                            'Attempts: $attempts | ${_formatQueueTime(createdAt)}',
                            style: TextStyle(fontSize: 11),
                          ),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () async {
                              await apiService.removeFromQueue(item['id']);
                              final newItems = await apiService.getQueueItems();
                              setDialogState(() => items
                                ..clear()
                                ..addAll(newItems));
                              _loadQueueStats();
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Close'),
            ),
            if (items.isNotEmpty) ...[
              TextButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('Clear All?'),
                      content: Text(
                          'Delete all ${items.length} pending actions? Cannot be undone.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text('Cancel')),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text('Delete',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await apiService.clearQueue();
                    Navigator.pop(ctx);
                    _loadQueueStats();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Queue cleared')),
                    );
                  }
                },
                child: Text('Clear All', style: TextStyle(color: Colors.red)),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await apiService.processQueue();
                  _loadQueueStats();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Syncing...')),
                  );
                },
                child: Text('Sync Now'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getActionDescription(String method, String endpoint, dynamic body) {
    final bodyMap = body is Map<String, dynamic> ? body : <String, dynamic>{};
    final amount = bodyMap['amount'];
    final username = bodyMap['username'] ?? bodyMap['player_username'] ?? '';

    if (endpoint.contains('add-payment')) {
      return 'Payment: ${amount != null ? "₪$amount" : ""} ${username.isNotEmpty ? "($username)" : ""}';
    }
    if (endpoint.contains('record-game')) {
      final fee = bodyMap['game_fee'] ?? bodyMap['fee'];
      return 'Game: ${fee != null ? "₪$fee" : ""} ${username.isNotEmpty ? "($username)" : ""}';
    }
    if (endpoint.contains('delete-payment')) {
      return 'Delete Payment ${username.isNotEmpty ? "($username)" : ""}';
    }
    if (endpoint.contains('delete-attendance')) {
      return 'Delete Attendance ${username.isNotEmpty ? "($username)" : ""}';
    }
    if (endpoint.contains('enlist')) {
      return 'Enlist Player ${username.isNotEmpty ? "($username)" : ""}';
    }
    return '$method: $endpoint';
  }

  String _formatQueueTime(String isoString) {
    try {
      final d = DateTime.parse(isoString);
      return '${d.day}/${d.month} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoString;
    }
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
              ? Center(
                  child: Text(
                      'Offline/no cache yet. Connect once to load data.',
                      style: TextStyle(color: Colors.orange[700])))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: _buildContent(),
                ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        // SINGLE CACHE/SYNC INDICATOR - only when there are pending items
        if (pendingQueue > 0 || _isSyncing)
          GestureDetector(
            onTap: _showPendingQueueDialog,
            child: Container(
              width: double.infinity,
              color: Colors.orange[50],
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isSyncing) ...[
                    BasketballSpinner(size: 16),
                    SizedBox(width: 8),
                    Text('Syncing...',
                        style:
                            TextStyle(fontSize: 12, color: Colors.blue[800])),
                  ] else ...[
                    Icon(Icons.cloud_off, color: Colors.orange, size: 18),
                    SizedBox(width: 8),
                    Text('$pendingQueue pending (tap to view)',
                        style:
                            TextStyle(fontSize: 12, color: Colors.orange[800])),
                  ],
                ],
              ),
            ),
          ),

        // SUMMARY CARDS - more compact
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: Colors.teal[50], // Light teal bg
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSummaryCard('Debt', totalDebt, Colors.red),
              _buildSummaryCard('Paid', totalPaid, Colors.green),
              _buildSummaryCard('Balance', totalBalance,
                  totalBalance >= 0 ? Colors.green : Colors.red),
            ],
          ),
        ),

        // INFO ROW
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${players.length} players',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              Text('Game: $defaultCost₪',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
        _buildQueueInfo(),

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
                icon: Icon(
                    _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 18),
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

        // PLAYER LIST - ULTRA COMPACT GRID
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              // Always at least 3 columns as requested
              final crossAxisCount = width > 1200 ? 5 : (width > 900 ? 4 : 3);
              // Taller cards (30% increase): previously 4.0, now reduced to ~2.8 to make them taller
              final childAspectRatio = 2.8;

              return GridView.builder(
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: childAspectRatio,
                  mainAxisSpacing: 0,
                  crossAxisSpacing: 0,
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
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: tileColor,
                        border:
                            Border.all(color: Colors.grey[200]!, width: 0.3),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Name
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color:
                                        isPositive ? Colors.green : Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    player['username'],
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Games & Remainder (Remainder Left, Games Right)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Remainder in parens (Left)
                              if (remainder != 0) ...[
                                Text(
                                  '(${remainder > 0 ? '+' : ''}$remainder₪)',
                                  style: TextStyle(
                                      fontSize: 9, color: Colors.grey[600]),
                                ),
                                SizedBox(width: 2),
                              ],
                              // Games count (Right)
                              Text(
                                '${games >= 0 ? (games > 0 ? '+' : '') : ''}$games',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isPositive
                                      ? Colors.green[700]
                                      : Colors.red[700],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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
          Text('$value ₪',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
