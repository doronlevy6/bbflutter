import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../../services/api_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import '../../pages/player_management_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:super_clipboard/super_clipboard.dart';
import '../../config/theme.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

enum RoleVisibilityFilter {
  all,
  hideGuests,
  guestsOnly,
}

class FinancialSummaryPage extends StatefulWidget {
  @override
  _FinancialSummaryPageState createState() => _FinancialSummaryPageState();
}

class _FinancialSummaryPageState extends State<FinancialSummaryPage> {
  final ApiService apiService = ApiService();
  bool isLoading = true;
  bool _isRefreshingData = false;
  bool accessDenied = false;
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
  bool _isForceRefreshing = false;
  String _preloadStatus = 'idle';
  String? _preloadUpdatedAt;
  String? _lastServerRefreshAt;
  IO.Socket? _socket;
  Timer? _liveRefreshTimer;
  int? _teamId;
  DateTime? _lastLiveRefreshAt;

  // Sorting state
  String _sortBy = 'name'; // 'name' or 'balance'
  bool _sortAscending = true;
  RoleVisibilityFilter _roleFilter = RoleVisibilityFilter.hideGuests;
  final Set<String> _manuallyHiddenPlayers = <String>{};

  @override
  void initState() {
    super.initState();
    _initializeAccess();
  }

  Future<void> _initializeAccess() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final isAdmin = prefs.getBool('is_admin') ?? false;
    _teamId = prefs.getInt('team_id');

    if (!isAdmin) {
      if (!mounted) return;
      setState(() {
        accessDenied = true;
        isLoading = false;
      });
      return;
    }

    _loadData();
    _loadQueueStats();
    _startConnectivityListener();
    _startSyncListener();
    _startRealtimeFinanceListener();
    _startPeriodicRefresh();
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
          _loadData(preferCache: false);
        }
      }
    });
  }

  void _startRealtimeFinanceListener() {
    final teamId = _teamId;
    if (teamId == null) return;

    _socket?.dispose();
    final socket = IO.io(apiService.apiUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    _socket = socket;

    socket.on('connect', (_) {
      socket.emit('joinTeam', {'team_id': teamId});
    });

    socket.on('financeSummaryUpdated', (payload) {
      if (!_belongsToCurrentTeam(payload)) return;
      _handleRealtimeFinanceUpdate();
    });

    socket.connect();
  }

  bool _belongsToCurrentTeam(dynamic payload) {
    final teamId = _teamId;
    if (teamId == null) return true;
    if (payload is Map) {
      final raw = payload['team_id'];
      if (raw is int) return raw == teamId;
      if (raw is String) return int.tryParse(raw) == teamId;
    }
    return true;
  }

  void _startPeriodicRefresh() {
    _liveRefreshTimer?.cancel();
    _liveRefreshTimer = Timer.periodic(const Duration(seconds: 35), (_) {
      _handleRealtimeFinanceUpdate();
    });
  }

  Future<void> _handleRealtimeFinanceUpdate() async {
    if (!mounted || accessDenied || _autoRefreshing) return;

    final now = DateTime.now();
    if (_lastLiveRefreshAt != null &&
        now.difference(_lastLiveRefreshAt!) < const Duration(seconds: 1)) {
      return;
    }
    _lastLiveRefreshAt = now;
    await _loadData(preferCache: false);
  }

  Future<void> _handleOnlineRefresh() async {
    if (accessDenied) return;
    if (_autoRefreshing) return;
    _autoRefreshing = true;
    try {
      await apiService.processQueue();
      await _loadData(preferCache: false);
      await _loadPreloadStatus();
    } finally {
      _autoRefreshing = false;
    }
  }

  Future<void> _forceRefreshFromServer() async {
    if (_isForceRefreshing || accessDenied) return;
    setState(() {
      _isForceRefreshing = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final teamId = prefs.getInt('team_id');
      if (teamId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Missing team id. Please login again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final ts = DateTime.now().millisecondsSinceEpoch;
      final response =
          await apiService.get('finance/team-financial-summary/$teamId?ts=$ts');
      if (response is Map<String, dynamic> && response['success'] == true) {
        final cacheKey = 'cache_team_summary_$teamId';
        await apiService.upsertCache(cacheKey, response);
        final normalized = Map<String, dynamic>.from(response);
        normalized['_cached'] = false;
        normalized['_cache_updated_at'] = DateTime.now().toIso8601String();
        _processData(normalized);
        await _loadQueueStats();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pulled latest data from server.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (response is Map<String, dynamic> && response['message'] != null)
                  ? response['message'].toString()
                  : 'Failed to pull latest server data.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Refresh failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isForceRefreshing = false;
        });
      }
    }
  }

  Future<void> _loadData({bool preferCache = true}) async {
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
    final hasExistingData = players.isNotEmpty;

    // 2. Try to load from cache immediately (Stale-while-revalidate)
    if (preferCache) {
      final cachedData = await apiService.getFromCacheOnly(cacheKey);
      if (cachedData != null && mounted) {
        _processData(cachedData);
        setState(() {
          isLoading = false;
          _isRefreshingData = true;
        });
      } else {
        setState(() {
          isLoading = !hasExistingData;
          _isRefreshingData = hasExistingData;
        });
      }
    } else {
      setState(() {
        isLoading = !hasExistingData;
        _isRefreshingData = hasExistingData;
      });
    }

    // 3. Update from Network (background)
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final response = await apiService.getWithCache(
          'finance/team-financial-summary/$teamId?ts=$ts',
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
      if (mounted) {
        setState(() {
          isLoading = false;
          _isRefreshingData = false;
        });
      }
    }
    _loadQueueStats();
  }

  void _processData(Map<String, dynamic> response) {
    setState(() {
      players = response['summary'] ?? [];
      defaultCost = response['defaultGameCost'] ?? 0;
      fromCache = response['_cached'] == true;
      _lastServerRefreshAt = response['_cache_updated_at'] as String?;
      _applySorting();
      _recalculateTotals();
    });
  }

  String _roleOf(Map<String, dynamic> player) {
    final role = (player['role'] ?? 'player').toString().toLowerCase();
    if (role == 'manager' || role == 'guest') return role;
    return 'player';
  }

  bool _isVisibleByRole(Map<String, dynamic> player) {
    final username = (player['username'] ?? '').toString();
    if (_manuallyHiddenPlayers.contains(username)) return false;
    final role = _roleOf(player);
    switch (_roleFilter) {
      case RoleVisibilityFilter.hideGuests:
        return role != 'guest';
      case RoleVisibilityFilter.guestsOnly:
        return role == 'guest';
      case RoleVisibilityFilter.all:
        return true;
    }
  }

  List<Map<String, dynamic>> _visiblePlayers() {
    return players
        .map((p) => Map<String, dynamic>.from(p as Map))
        .where(_isVisibleByRole)
        .toList();
  }

  void _recalculateTotals() {
    totalDebt = 0;
    totalPaid = 0;
    totalBalance = 0;
    for (final p in _visiblePlayers()) {
      totalDebt += (p['debt'] as int? ?? 0);
      totalPaid += (p['paid'] as int? ?? 0);
      totalBalance += (p['balance'] as int? ?? 0);
    }
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
    _recalculateTotals();
  }

  Future<void> _openPlayerFinancials(String username) async {
    showDialog(
      context: context,
      builder: (context) =>
          PlayerFinancialDialog(username: username, apiService: apiService),
    ).then((_) {
      // Refresh data after dialog closes
      _loadData(preferCache: false);
    });
  }

  Widget _buildSortChip(String label, String field) {
    final bool active = _sortBy == field;
    final String dirSuffix = active ? (_sortAscending ? ' ↑' : ' ↓') : '';
    return ChoiceChip(
      label: Text('$label$dirSuffix'),
      selected: active,
      onSelected: (_) {
        setState(() {
          if (_sortBy == field) {
            _sortAscending = !_sortAscending;
          } else {
            _sortBy = field;
            _sortAscending = true;
          }
          _applySorting();
        });
      },
    );
  }

  void _hidePlayerFromSummary(String username) {
    setState(() {
      _manuallyHiddenPlayers.add(username);
      _recalculateTotals();
    });
  }

  void _restoreHiddenPlayers() {
    setState(() {
      _manuallyHiddenPlayers.clear();
      _recalculateTotals();
    });
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

  String _formatMaybeIsoDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final d = parsed.toLocal();
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  Map<String, int> _computeGamesAndRemainder(Map<String, dynamic> player) {
    final balance = player['balance'] as int? ?? 0;
    final customCost = player['custom_game_cost'] as int?;
    final playerCost = customCost ?? defaultCost;

    final int games;
    final int remainder;
    if (playerCost > 0) {
      if (balance >= 0) {
        games = balance ~/ playerCost;
      } else {
        final debtAbs = -balance;
        final debtGames = (debtAbs + playerCost - 1) ~/ playerCost;
        games = -debtGames;
      }
      remainder = balance - (games * playerCost);
    } else {
      games = 0;
      remainder = balance;
    }

    return {'games': games, 'remainder': remainder};
  }

  String _formatGamesValue(int games) {
    final prefix = games >= 0 ? (games > 0 ? '+' : '') : '';
    return '$prefix$games games';
  }

  String _formatRemainderValue(int remainder) {
    final prefix = remainder > 0 ? '+' : '';
    return '$prefix$remainder₪';
  }

  String _buildDebtStatusText() {
    final snapshot = _visiblePlayers();

    final lines = <String>[
      '🏀 סטטוס תשלומים לקבוצה',
      'עודכן: ${_fmtDateTime(DateTime.now())}',
      '',
    ];

    for (final p in snapshot) {
      final username = (p['username'] ?? '').toString();
      final breakdown = _computeGamesAndRemainder(p);
      final games = breakdown['games'] ?? 0;
      final remainder = breakdown['remainder'] ?? 0;
      final paid = p['paid'] as int? ?? 0;
      final debt = p['debt'] as int? ?? 0;
      final gamesText = _formatGamesValue(games);
      final remainderText =
          remainder == 0 ? '' : ' | ${_formatRemainderValue(remainder)}';
      lines.add(
          '• $username: $gamesText$remainderText | שולם ${paid}₪ | חיוב ${debt}₪');
    }

    lines.add('');
    lines.add('סה"כ חוב: ${totalDebt}₪ | סה"כ שולם: ${totalPaid}₪');
    return lines.join('\n');
  }

  Future<void> _copyDebtStatus() async {
    final text = _buildDebtStatusText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Debt status copied. Ready to paste to WhatsApp.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<Uint8List?> _captureCardPng(GlobalKey boundaryKey) async {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;
    final image = await renderObject.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return byteData?.buffer.asUint8List();
  }

  Future<bool> _copyImageToClipboard(
      Uint8List pngBytes, String fallbackText) async {
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) return false;
      final item = DataWriterItem();
      item.add(Formats.png(pngBytes));
      item.add(Formats.plainText(fallbackText));
      await clipboard.write([item]);
      return true;
    } catch (_) {
      return false;
    }
  }

  Widget _buildSharePlayerCard(Map<String, dynamic> p) {
    final username = (p['username'] ?? '').toString();
    final balance = p['balance'] as int? ?? 0;
    final breakdown = _computeGamesAndRemainder(p);
    final games = breakdown['games'] ?? 0;
    final remainder = breakdown['remainder'] ?? 0;
    final lastPaymentAmount = p['last_payment_amount'] as int?;
    final lastPaymentDate = p['last_payment_date']?.toString();

    final bool isDebt = balance < 0;
    final Color tone = isDebt ? Colors.red : Colors.green;
    final String gamesText = _formatGamesValue(games);
    final String lastPaymentText = (lastPaymentAmount == null ||
            lastPaymentDate == null ||
            lastPaymentDate.isEmpty)
        ? 'תשלום אחרון: אין'
        : 'תשלום אחרון: ${lastPaymentAmount}₪ • ${_formatMaybeIsoDate(lastPaymentDate)}';

    return Container(
      width: 154,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.35), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: isDebt
                      ? Colors.red.withValues(alpha: 0.08)
                      : Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  gamesText,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: isDebt ? Colors.red.shade800 : Colors.green.shade800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (remainder != 0)
                Text(
                  _formatRemainderValue(remainder),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            lastPaymentText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShareBoard() {
    final visibleInCurrentOrder = _visiblePlayers();
    return Container(
      width: 1060,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade50, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.outlineSoft),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: visibleInCurrentOrder.map(_buildSharePlayerCard).toList(),
      ),
    );
  }

  Future<void> _showShareImageDialog() async {
    final boardKey = GlobalKey();
    final fallbackText = _buildDebtStatusText();

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        title: const Text('שיתוף יתרות וחובות'),
        content: SizedBox(
          width: 1120,
          child: SingleChildScrollView(
            child: RepaintBoundary(
              key: boardKey,
              child: _buildShareBoard(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('סגור'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final pngBytes = await _captureCardPng(boardKey);
              final imageCopied = pngBytes != null
                  ? await _copyImageToClipboard(pngBytes, fallbackText)
                  : false;

              if (!imageCopied) {
                await Clipboard.setData(ClipboardData(text: fallbackText));
              }
              if (!mounted) return;
              if (Navigator.of(dialogContext).canPop()) {
                Navigator.pop(dialogContext);
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    imageCopied
                        ? 'הכרטיס הועתק כתמונה. אפשר להדביק בוואטסאפ.'
                        : 'לא נתמכה העתקת תמונה בדפדפן זה. הועתק טקסט כגיבוי.',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('העתק כתמונה'),
          ),
        ],
      ),
    );
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
    final updatedAt = _preloadUpdatedAt != null
        ? DateTime.tryParse(_preloadUpdatedAt!)
        : null;
    final suffix =
        updatedAt != null ? ' (${_fmtDateTime(updatedAt.toLocal())})' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color),
          SizedBox(width: 6),
          Text('$text$suffix', style: TextStyle(fontSize: 12, color: color)),
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
    _liveRefreshTimer?.cancel();
    if (_teamId != null) {
      _socket?.emit('leaveTeam', {'team_id': _teamId});
    }
    _socket?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (accessDenied) {
      return Scaffold(
        body: Center(
          child: Text('Access Denied',
              style:
                  TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        ),
      );
    }

    if (errorMessage != null && players.isEmpty) {
      return Scaffold(
        body: Center(
          child: Text(
            'Offline/no cache yet. Connect once to load data.',
            style: TextStyle(color: Colors.orange[700]),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () => _loadData(preferCache: false),
            child: _buildContent(),
          ),
          if (isLoading && players.isEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final visiblePlayers = _visiblePlayers();
    String roleFilterLabel;
    switch (_roleFilter) {
      case RoleVisibilityFilter.hideGuests:
        roleFilterLabel = 'Hide Guests';
        break;
      case RoleVisibilityFilter.guestsOnly:
        roleFilterLabel = 'Guests Only';
        break;
      case RoleVisibilityFilter.all:
        roleFilterLabel = 'All Roles';
    }

    return Column(
      children: [
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
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade50, Colors.white],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            border: Border(
              bottom: BorderSide(color: AppTheme.outlineSoft),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.insights, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Financial Summary',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    '${visiblePlayers.length}/${players.length} players',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_isRefreshingData) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: const [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Updating...',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildSummaryCard(
                      'Debt', totalDebt, Colors.red, Icons.remove),
                  const SizedBox(width: 8),
                  _buildSummaryCard(
                      'Paid', totalPaid, Colors.green, Icons.add_circle),
                  const SizedBox(width: 8),
                  _buildSummaryCard(
                    'Balance',
                    totalBalance,
                    totalBalance >= 0 ? Colors.green : Colors.red,
                    Icons.account_balance_wallet,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.outlineSoft),
                    ),
                    child: Text(
                      'Game cost: $defaultCost₪',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _copyDebtStatus,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy Text'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _showShareImageDialog,
                    icon: const Icon(Icons.image_outlined, size: 16),
                    label: const Text('Copy Image'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed:
                        _isForceRefreshing ? null : _forceRefreshFromServer,
                    icon: _isForceRefreshing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_download_outlined, size: 16),
                    label: Text(
                        _isForceRefreshing ? 'Refreshing...' : 'Pull From DB'),
                  ),
                ],
              ),
            ],
          ),
        ),
        _buildQueueInfo(),
        _buildPreloadStatus(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              _buildSortChip('Name', 'name'),
              const SizedBox(width: 8),
              _buildSortChip('Balance', 'balance'),
              const SizedBox(width: 8),
              PopupMenuButton<RoleVisibilityFilter>(
                onSelected: (value) {
                  setState(() {
                    _roleFilter = value;
                    _recalculateTotals();
                  });
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: RoleVisibilityFilter.all,
                    child: Text('All Roles'),
                  ),
                  PopupMenuItem(
                    value: RoleVisibilityFilter.hideGuests,
                    child: Text('Hide Guests'),
                  ),
                  PopupMenuItem(
                    value: RoleVisibilityFilter.guestsOnly,
                    child: Text('Guests Only'),
                  ),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.outlineSoft),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.filter_alt_outlined, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        roleFilterLabel,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _manuallyHiddenPlayers.isEmpty
                    ? null
                    : _restoreHiddenPlayers,
                icon: const Icon(Icons.visibility, size: 16),
                label: Text(
                  _manuallyHiddenPlayers.isEmpty
                      ? 'Hidden 0'
                      : 'Show Hidden (${_manuallyHiddenPlayers.length})',
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width >= 1600
                  ? 7
                  : width >= 1300
                      ? 6
                      : width >= 1050
                          ? 5
                          : width >= 760
                              ? 4
                              : 3;
              final childAspectRatio = width >= 1200
                  ? 2.75
                  : width >= 760
                      ? 2.25
                      : 1.9;

              return GridView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: childAspectRatio,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: visiblePlayers.length,
                itemBuilder: (context, index) {
                  final player = visiblePlayers[index];
                  final balance = player['balance'] as int? ?? 0;
                  final breakdown = _computeGamesAndRemainder(player);
                  final games = breakdown['games'] ?? 0;
                  final remainder = breakdown['remainder'] ?? 0;
                  final bool isPositive = balance >= 0;
                  final role = _roleOf(player);
                  final lastPaymentAmount =
                      player['last_payment_amount'] as int?;
                  final lastPaymentDate =
                      player['last_payment_date']?.toString();
                  final lastPaymentText = (lastPaymentAmount == null ||
                          lastPaymentDate == null ||
                          lastPaymentDate.isEmpty)
                      ? 'תשלום אחרון: אין'
                      : 'תשלום אחרון: ${lastPaymentAmount}₪ • ${_formatMaybeIsoDate(lastPaymentDate)}';

                  return InkWell(
                    onTap: () => _openPlayerFinancials(player['username']),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: fromCache ? Colors.orange[50] : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isPositive
                              ? Colors.green.withValues(alpha: 0.2)
                              : Colors.red.withValues(alpha: 0.2),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x10000000),
                            blurRadius: 6,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isPositive
                                    ? Icons.arrow_circle_up
                                    : Icons.arrow_circle_down,
                                size: 14,
                                color: isPositive
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  (player['username'] ?? '').toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (role == 'guest') ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.blueGrey.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Guest',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 2),
                              Tooltip(
                                message: 'Hide from summary',
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => _hidePlayerFromSummary(
                                    (player['username'] ?? '').toString(),
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.all(2),
                                    child: Icon(
                                      Icons.visibility_off_outlined,
                                      size: 16,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isPositive
                                      ? Colors.green.withValues(alpha: 0.08)
                                      : Colors.red.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _formatGamesValue(games),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: isPositive
                                        ? Colors.green.shade800
                                        : Colors.red.shade800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 3),
                              if (remainder != 0)
                                Text(
                                  _formatRemainderValue(remainder),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lastPaymentText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
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

  Widget _buildSummaryCard(
      String label, int value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x11000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                  const SizedBox(height: 2),
                  Text('$value ₪',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
