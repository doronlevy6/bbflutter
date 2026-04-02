import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import '../../config/theme.dart';
import '../../services/api_service.dart';

class MyWalletPage extends StatefulWidget {
  @override
  State<MyWalletPage> createState() => _MyWalletPageState();
}

class _MyWalletPageState extends State<MyWalletPage> {
  final ApiService _apiService = ApiService();

  bool _loading = true;
  bool _refreshing = false;
  bool _fromCache = false;
  bool _isHebrew = false;
  String _filter = 'all';
  String? _errorMessage;
  String? _username;
  int? _teamId;
  String? _lastServerRefreshAt;
  Map<String, dynamic>? _data;

  IO.Socket? _socket;
  Timer? _timer;
  DateTime? _lastLiveRefreshAt;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('user');
    final isHebrew = prefs.getBool('isHebrew') ?? false;
    final teamId = prefs.getInt('team_id');

    if (!mounted) return;
    setState(() {
      _username = username;
      _isHebrew = isHebrew;
      _teamId = teamId;
    });

    await _loadData();
    _startRealtimeUpdates();
  }

  void _startRealtimeUpdates() {
    final teamId = _teamId;
    if (teamId == null) return;

    _socket?.dispose();
    final socket = IO.io(_apiService.apiUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    _socket = socket;

    socket.on('connect', (_) {
      socket.emit('joinTeam', {'team_id': teamId});
    });

    socket.on('financeSummaryUpdated', (payload) {
      if (!_belongsToCurrentTeam(payload)) return;
      _refreshLive();
    });

    socket.connect();

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 40), (_) {
      _refreshLive();
    });
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

  Future<void> _refreshLive() async {
    final now = DateTime.now();
    if (_lastLiveRefreshAt != null &&
        now.difference(_lastLiveRefreshAt!) < const Duration(seconds: 1)) {
      return;
    }
    _lastLiveRefreshAt = now;
    await _loadData(preferCache: false);
  }

  Future<void> _loadData({bool preferCache = true}) async {
    if (_username == null || _username!.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _errorMessage = _isHebrew
            ? 'לא נמצא משתמש. התחבר מחדש.'
            : 'Missing user. Please login again.';
      });
      return;
    }

    final cacheKey = 'cache_my_wallet_${_username!}';
    final hasData = _data != null;

    if (preferCache) {
      final cached = await _apiService.getFromCacheOnly(cacheKey);
      if (cached != null && cached['success'] == true && mounted) {
        setState(() {
          _data = cached;
          _fromCache = true;
          _lastServerRefreshAt = cached['_cache_updated_at'] as String?;
          _loading = false;
          _refreshing = true;
          _errorMessage = null;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _loading = !hasData;
          _refreshing = hasData;
        });
      }
    } else {
      if (!mounted) return;
      setState(() {
        _loading = !hasData;
        _refreshing = hasData;
      });
    }

    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      Map<String, dynamic> response = await _apiService.getWithCache(
        'finance/my-financials?ts=$ts',
        cacheKey: cacheKey,
      );
      if (response['success'] != true) {
        // Backward compatibility when backend is not deployed yet.
        response = await _apiService.getWithCache(
          'finance/player-financials/${_username!}?ts=$ts',
          cacheKey: cacheKey,
        );
      }
      if (!mounted) return;
      if (response['success'] == true) {
        setState(() {
          _data = response;
          _fromCache = response['_cached'] == true;
          _lastServerRefreshAt = response['_cache_updated_at'] as String?;
          _errorMessage = null;
        });
      } else if (_data == null) {
        setState(() {
          _errorMessage = response['message']?.toString() ?? 'Failed to load';
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (_data == null) {
        setState(() {
          _errorMessage = _isHebrew
              ? 'אין נתונים מקומיים כרגע. התחבר עם אינטרנט לפחות פעם אחת.'
              : 'No cached data yet. Open once with internet connection.';
        });
      }
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  String _fmtDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final d = parsed.toLocal();
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  String _fmtDateOnly(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final d = parsed.toLocal();
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  Widget _summaryCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_teamId != null) {
      _socket?.emit('leaveTeam', {'team_id': _teamId});
    }
    _timer?.cancel();
    _socket?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null && _data == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.orange.shade700, fontSize: 14),
            ),
          ),
        ),
      );
    }

    final payload = _data ?? <String, dynamic>{};
    final balance = payload['balance'] as int? ?? 0;
    final totalPaid = payload['totalPaid'] as int? ?? 0;
    final totalCost = payload['totalCost'] as int? ?? 0;
    final gamesPlayed = payload['gamesPlayed'] as int? ?? 0;
    final gamesEquivalent = payload['gamesEquivalent'] as int? ?? 0;
    final remainder = payload['remainder'] as int? ?? 0;
    final lastPaymentAmount = payload['lastPaymentAmount'] as int?;
    final lastPaymentDate = payload['lastPaymentDate']?.toString();
    final history = payload['history'] as Map<String, dynamic>? ?? {};
    final games = history['games'] as List<dynamic>? ?? [];
    final payments = history['payments'] as List<dynamic>? ?? [];

    final entries = <Map<String, dynamic>>[];
    if (_filter == 'all' || _filter == 'games') {
      for (final g in games) {
        entries.add({
          'type': 'game',
          'date': g['date'],
          'amount': -1 * ((g['applied_cost'] as num?) ?? 0),
          'desc': _isHebrew ? 'משחק' : 'Game',
        });
      }
    }
    if (_filter == 'all' || _filter == 'payments') {
      for (final p in payments) {
        entries.add({
          'type': 'payment',
          'date': p['date'],
          'amount': p['amount'],
          'desc':
              _isHebrew ? 'תשלום (${p['method']})' : 'Payment (${p['method']})',
        });
      }
    }
    entries.sort((a, b) =>
        DateTime.parse(b['date']).compareTo(DateTime.parse(a['date'])));

    final gamesText =
        '${gamesEquivalent >= 0 ? '+' : ''}$gamesEquivalent games';
    final remainderText =
        remainder == 0 ? '' : ' | ${remainder > 0 ? '+' : ''}$remainder₪';
    final lastPaymentText = (lastPaymentAmount == null ||
            lastPaymentDate == null ||
            lastPaymentDate.isEmpty)
        ? (_isHebrew ? 'תשלום אחרון: אין' : 'Last payment: none')
        : (_isHebrew
            ? 'תשלום אחרון: $lastPaymentAmount₪ • ${_fmtDateOnly(lastPaymentDate)}'
            : 'Last payment: $lastPaymentAmount₪ • ${_fmtDateOnly(lastPaymentDate)}');

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _loadData(preferCache: false),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade50, Colors.white],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.outlineSoft),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_balance_wallet, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isHebrew ? 'הארנק שלי' : 'My Wallet',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (_refreshing)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _username ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _summaryCard(
                        _isHebrew ? 'יתרה' : 'Balance',
                        '${balance >= 0 ? '+' : ''}$balance₪',
                        balance >= 0 ? Colors.green : Colors.red,
                        Icons.account_balance,
                      ),
                      const SizedBox(width: 8),
                      _summaryCard(
                        _isHebrew ? 'שולם' : 'Paid',
                        '$totalPaid₪',
                        Colors.green,
                        Icons.add_circle_outline,
                      ),
                      const SizedBox(width: 8),
                      _summaryCard(
                        _isHebrew ? 'חיובים' : 'Charged',
                        '$totalCost₪',
                        Colors.red,
                        Icons.remove_circle_outline,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _summaryCard(
                        _isHebrew ? 'משחקים ששוחקו' : 'Games played',
                        '$gamesPlayed',
                        Colors.indigo,
                        Icons.sports_basketball,
                      ),
                      const SizedBox(width: 8),
                      _summaryCard(
                        _isHebrew ? 'מצב משחקים' : 'Games state',
                        '$gamesText$remainderText',
                        balance >= 0 ? Colors.green : Colors.red,
                        Icons.insights,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    lastPaymentText,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_lastServerRefreshAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _isHebrew
                          ? 'עודכן: ${_fmtDate(_lastServerRefreshAt!)}'
                          : 'Updated: ${_fmtDate(_lastServerRefreshAt!)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                  if (_fromCache) ...[
                    const SizedBox(height: 4),
                    Text(
                      _isHebrew
                          ? 'מוצג מהקאש המקומי'
                          : 'Showing local cached data',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ChoiceChip(
                  label: Text(_isHebrew ? 'הכל' : 'All'),
                  selected: _filter == 'all',
                  onSelected: (_) => setState(() => _filter = 'all'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(_isHebrew ? 'משחקים' : 'Games'),
                  selected: _filter == 'games',
                  onSelected: (_) => setState(() => _filter = 'games'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(_isHebrew ? 'תשלומים' : 'Payments'),
                  selected: _filter == 'payments',
                  onSelected: (_) => setState(() => _filter = 'payments'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (entries.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                child: Text(
                  _isHebrew ? 'אין היסטוריה להצגה' : 'No history found',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            else
              ...entries.map((item) {
                final amount = (item['amount'] as num?)?.toInt() ?? 0;
                final isPlus = amount >= 0;
                final isPayment = item['type'] == 'payment';
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      isPayment ? Icons.payment : Icons.sports_basketball,
                      color: isPayment ? Colors.blue : Colors.orange,
                    ),
                    title: Text(item['desc']?.toString() ?? ''),
                    subtitle: Text(_fmtDate(item['date']?.toString() ?? '')),
                    trailing: Text(
                      '${isPlus ? '+' : ''}$amount₪',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: isPlus ? Colors.green : Colors.red,
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
