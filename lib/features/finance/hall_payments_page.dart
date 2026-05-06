import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'dart:ui' as ui;

import '../../services/api_service.dart';

class HallPaymentsPage extends StatefulWidget {
  @override
  State<HallPaymentsPage> createState() => _HallPaymentsPageState();
}

class _HallPaymentsPageState extends State<HallPaymentsPage> {
  final ApiService _apiService = ApiService();
  final TextEditingController _paymentAmountController =
      TextEditingController();
  final TextEditingController _paymentDateController = TextEditingController();
  final TextEditingController _paymentNotesController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  Map<String, dynamic> _summary = {};
  Map<String, dynamic> _settings = {};
  List<dynamic> _games = [];
  List<dynamic> _payments = [];
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  @override
  void initState() {
    super.initState();
    _paymentDateController.text = _dateOnly(DateTime.now().toIso8601String());
    _loadSummary();
  }

  @override
  void dispose() {
    _paymentAmountController.dispose();
    _paymentDateController.dispose();
    _paymentNotesController.dispose();
    super.dispose();
  }

  String _dateOnly(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw.length >= 10 ? raw.substring(0, 10) : raw;
    }
    final local = parsed.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  String _money(dynamic value) {
    final amount = int.tryParse(value?.toString() ?? '0') ?? 0;
    return '$amount₪';
  }

  DateTime? _parseDateOnly(String? raw) {
    final date = _dateOnly(raw);
    if (date.isEmpty) return null;
    return DateTime.tryParse(date);
  }

  bool get _hasDateRange => _rangeStart != null || _rangeEnd != null;

  bool _isInSelectedRange(Map<String, dynamic> game) {
    final date = _parseDateOnly(game['game_date']?.toString());
    if (date == null) return false;
    if (_rangeStart != null && date.isBefore(_rangeStart!)) return false;
    if (_rangeEnd != null && date.isAfter(_rangeEnd!)) return false;
    return true;
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red[700] : Colors.green[700],
      ),
    );
  }

  Future<void> _loadSummary() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _apiService.get('finance/hall/summary');
      if (response['success'] == true) {
        setState(() {
          _settings = Map<String, dynamic>.from(response['settings'] ?? {});
          _summary = Map<String, dynamic>.from(response['summary'] ?? {});
          _games = List<dynamic>.from(response['games'] ?? []);
          _payments = List<dynamic>.from(response['payments'] ?? []);
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response['message']?.toString() ?? 'Failed to load';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading Hall Payments: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _addPayment() async {
    final amount = int.tryParse(_paymentAmountController.text.trim()) ?? 0;
    if (amount <= 0) {
      _showSnack('Payment amount must be positive', error: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final response = await _apiService.postQueued('finance/hall/payments', {
        'amount': amount,
        'date': _paymentDateController.text.trim(),
        'notes': _paymentNotesController.text.trim(),
      });
      if (response['success'] == true) {
        _showSnack(response['queued'] == true
            ? 'Saved offline. Will sync later.'
            : 'Hall payment added');
        if (response['queued'] != true) {
          _paymentAmountController.clear();
          _paymentNotesController.clear();
          await _loadSummary();
        }
      } else {
        _showSnack(response['message']?.toString() ?? 'Payment failed',
            error: true);
      }
    } catch (e) {
      _showSnack('Error adding payment: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deletePayment(dynamic paymentId) async {
    setState(() => _isSaving = true);
    try {
      final response =
          await _apiService.deleteQueued('finance/hall/payments/$paymentId');
      if (response['success'] == true) {
        _showSnack(response['queued'] == true
            ? 'Delete queued for later'
            : 'Payment deleted');
        if (response['queued'] != true) await _loadSummary();
      } else {
        _showSnack(response['message']?.toString() ?? 'Delete failed',
            error: true);
      }
    } catch (e) {
      _showSnack('Error deleting payment: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  int _intValue(dynamic value) {
    return int.tryParse(value?.toString() ?? '0') ?? 0;
  }

  List<Map<String, dynamic>> _unpaidGames() {
    return _gamesWithPaymentStatus()
        .where((game) => game['_is_paid'] != true)
        .toList();
  }

  List<Map<String, dynamic>> _gamesWithPaymentStatus() {
    var remainingPaid = _intValue(_summary['totalPaid']);
    final games = <Map<String, dynamic>>[];

    for (final raw in _games) {
      final game = Map<String, dynamic>.from(raw as Map);
      final cost = _intValue(game['cost']);
      final isPaid = remainingPaid >= cost;
      if (isPaid) remainingPaid -= cost;
      game['_is_paid'] = isPaid;
      games.add(game);
    }

    return games;
  }

  List<Map<String, dynamic>> _visibleGamesForRange() {
    final games = _hasDateRange
        ? _gamesWithPaymentStatus().where(_isInSelectedRange).toList()
        : _unpaidGames();
    return games;
  }

  String _selectedRangeText() {
    if (!_hasDateRange) return 'All open unpaid games';
    final start = _rangeStart == null
        ? 'Start'
        : _dateOnly(_rangeStart!.toIso8601String());
    final end =
        _rangeEnd == null ? 'Today' : _dateOnly(_rangeEnd!.toIso8601String());
    return '$start - $end';
  }

  Future<void> _pickRangeDate({required bool isStart}) async {
    final now = DateTime.now();
    final current = isStart ? _rangeStart : _rangeEnd;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;

    setState(() {
      if (isStart) {
        _rangeStart = DateTime(picked.year, picked.month, picked.day);
        if (_rangeEnd != null && _rangeEnd!.isBefore(_rangeStart!)) {
          _rangeEnd = _rangeStart;
        }
      } else {
        _rangeEnd = DateTime(picked.year, picked.month, picked.day);
        if (_rangeStart != null && _rangeStart!.isAfter(_rangeEnd!)) {
          _rangeStart = _rangeEnd;
        }
      }
    });
  }

  void _clearDateRange() {
    setState(() {
      _rangeStart = null;
      _rangeEnd = null;
    });
  }

  List<Map<String, dynamic>> _paymentsWithCoverage() {
    final gameCosts = _games
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .map((game) => {
              ...game,
              '_remaining_cost': _intValue(game['cost']),
            })
        .toList();
    var gameIndex = 0;
    final payments = <Map<String, dynamic>>[];

    for (final raw in _payments) {
      final payment = Map<String, dynamic>.from(raw as Map);
      var amountLeft = _intValue(payment['amount']);
      String? startsFromDate;
      var coveredGames = 0;

      while (gameIndex < gameCosts.length &&
          _intValue(gameCosts[gameIndex]['_remaining_cost']) <= 0) {
        gameIndex += 1;
      }

      if (gameIndex < gameCosts.length && amountLeft > 0) {
        startsFromDate =
            _dateOnly(gameCosts[gameIndex]['game_date']?.toString());
      }

      while (gameIndex < gameCosts.length && amountLeft > 0) {
        final remainingCost =
            _intValue(gameCosts[gameIndex]['_remaining_cost']);
        final paidNow =
            amountLeft >= remainingCost ? remainingCost : amountLeft;
        amountLeft -= paidNow;
        gameCosts[gameIndex]['_remaining_cost'] = remainingCost - paidNow;

        if (_intValue(gameCosts[gameIndex]['_remaining_cost']) == 0) {
          coveredGames += 1;
          gameIndex += 1;
        }
      }

      payment['_starts_from_date'] = startsFromDate;
      payment['_covered_games'] = coveredGames;
      payment['_prepaid_amount'] = amountLeft;
      payments.add(payment);
    }

    return payments;
  }

  String _buildUnpaidDatesText() {
    final visibleGames = _visibleGamesForRange();
    final unpaidGames =
        visibleGames.where((game) => game['_is_paid'] != true).toList();
    final balance = _intValue(_summary['balance']);
    final gamesRemaining = _intValue(_summary['gamesRemaining']);
    final title = _hasDateRange
        ? 'משחקי אולם בטווח ${_selectedRangeText()}'
        : 'משחקים שלא שולמו לאולם';

    if (visibleGames.isEmpty) {
      return [
        title,
        '',
        _hasDateRange
            ? 'לא נמצאו משחקים בטווח הזה.'
            : balance > 0
                ? 'אין משחקים שלא שולמו. יש תשלום מראש לעוד $gamesRemaining משחקים.'
                : 'אין משחקים שלא שולמו.',
        'יתרה: ${_money(balance)}',
      ].join('\n');
    }

    final lines = <String>[
      title,
      '',
      ...visibleGames.map((game) {
        final date = _dateOnly(game['game_date']?.toString());
        final cost = _money(game['cost']);
        final status = game['_is_paid'] == true ? 'שולם' : 'לא שולם';
        return '• $date - $cost - $status';
      }),
      '',
      'סה"כ משחקים בטבלה: ${visibleGames.length}',
      'לא שולמו: ${unpaidGames.length}',
      _hasDateRange ? '' : 'סה"כ חוב: ${_money(balance.abs())}',
    ];

    return lines.join('\n');
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

  Widget _buildUnpaidShareBoard() {
    final visibleGames = _visibleGamesForRange();
    final unpaidGames =
        visibleGames.where((game) => game['_is_paid'] != true).toList();
    final balance = _intValue(_summary['balance']);
    final gamesRemaining = _intValue(_summary['gamesRemaining']);
    final defaultCost = _summary['defaultGameCost'] ?? 200;
    final title = _hasDateRange
        ? 'משחקי אולם בטווח'
        : visibleGames.isEmpty
            ? 'אין משחקים שלא שולמו'
            : 'משחקים שלא שולמו לאולם';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: 520,
        padding: EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFFF7ED), Colors.white],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Color(0xFFF2C08B)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x16000000),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: balance < 0 ? Colors.red[700] : Colors.green[700],
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.home_work, color: Colors.white),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF3D2B1F),
                        ),
                      ),
                      Text(
                        _hasDateRange
                            ? _selectedRangeText()
                            : 'מחיר ברירת מחדל: $defaultCost₪ למשחק',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.brown[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 18),
            if (visibleGames.isEmpty)
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  _hasDateRange
                      ? 'לא נמצאו משחקים בטווח הזה.'
                      : balance > 0
                          ? 'הכול שולם. יש תשלום מראש לעוד $gamesRemaining משחקים.'
                          : 'הכול שולם עד עכשיו.',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.green[800],
                  ),
                ),
              )
            else
              Column(
                children: visibleGames.map((game) {
                  final index = visibleGames.indexOf(game) + 1;
                  final isPaid = game['_is_paid'] == true;
                  return Container(
                    margin: EdgeInsets.only(bottom: 8),
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Color(0xFFE8D7C5)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isPaid ? Colors.green[700] : Colors.red[700],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$index',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _dateOnly(game['game_date']?.toString()),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isPaid
                                ? Colors.green.withValues(alpha: 0.10)
                                : Colors.red.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isPaid ? 'שולם' : 'לא שולם',
                            style: TextStyle(
                              color:
                                  isPaid ? Colors.green[800] : Colors.red[800],
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          _money(game['cost']),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isPaid ? Colors.green[700] : Colors.red[700],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            SizedBox(height: 10),
            Divider(color: Color(0xFFE8D7C5)),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'סה"כ משחקים',
                    style: TextStyle(color: Colors.brown[700]),
                  ),
                ),
                Text(
                  '${visibleGames.length}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            SizedBox(height: 6),
            if (_hasDateRange)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'מתוכם לא שולמו',
                      style: TextStyle(color: Colors.brown[700]),
                    ),
                  ),
                  Text(
                    '${unpaidGames.length}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
            if (_hasDateRange) SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    balance < 0 ? 'סה"כ חוב' : 'יתרה',
                    style: TextStyle(color: Colors.brown[700]),
                  ),
                ),
                Text(
                  _money(balance.abs()),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: balance < 0 ? Colors.red[700] : Colors.green[700],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showShareUnpaidDialog() async {
    final boardKey = GlobalKey();
    final fallbackText = _buildUnpaidDatesText();

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        title: Text('Share unpaid games'),
        content: SingleChildScrollView(
          child: RepaintBoundary(
            key: boardKey,
            child: _buildUnpaidShareBoard(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Close'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: fallbackText));
              if (!mounted) return;
              Navigator.pop(dialogContext);
              _showSnack('Dates copied as text. Ready for WhatsApp.');
            },
            icon: Icon(Icons.text_snippet),
            label: Text('Copy Text'),
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
              _showSnack(
                imageCopied
                    ? 'Image copied. Paste it in WhatsApp.'
                    : 'Image copy is not supported here. Text copied instead.',
              );
            },
            icon: Icon(Icons.copy),
            label: Text('Copy Image'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal[700],
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 26),
            SizedBox(height: 10),
            Text(title, style: TextStyle(color: Colors.grey[700])),
            SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final balance = int.tryParse(_summary['balance']?.toString() ?? '0') ?? 0;
    final balanceColor = balance >= 0 ? Colors.green[700]! : Colors.red[700]!;
    final defaultCost = _summary['defaultGameCost'] ?? 200;
    final coveredThrough = _dateOnly(
      _summary['coveredThroughDate']?.toString(),
    );
    final nextUncovered = _dateOnly(
      _summary['nextUncoveredGameDate']?.toString(),
    );
    final coverageValue = balance >= 0
        ? '${_summary['gamesRemaining'] ?? 0}'
        : '${_summary['gamesOwed'] ?? 0}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 760;
          final cards = [
            _metricCard(
              title: balance >= 0 ? 'Balance' : 'Debt',
              value: _money(balance.abs()),
              subtitle: balance >= 0 ? 'Paid ahead' : 'Need to pay',
              icon: balance >= 0 ? Icons.savings : Icons.warning_amber,
              color: balanceColor,
            ),
            _metricCard(
              title: balance >= 0 ? 'Games Covered' : 'Games Owed',
              value: coverageValue,
              subtitle: 'Default $defaultCost₪ per game',
              icon: Icons.event_available,
              color: Colors.blue[700]!,
            ),
          ];

          if (isNarrow) {
            return Column(
              children: cards
                  .map(
                    (card) => Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Row(children: [card]),
                    ),
                  )
                  .toList(),
            );
          }

          return Row(
            children: [
              cards[0],
              SizedBox(width: 12),
              cards[1],
            ],
          );
        }),
        SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(Icons.timeline, color: Colors.indigo),
            title: Text(
              'Paid ${_money(_summary['totalPaid'])} • Games cost ${_money(_summary['totalGameCost'])}',
            ),
            subtitle: Text(
              'Covered through: ${coveredThrough.isEmpty ? 'none yet' : coveredThrough}'
              ' • Next unpaid game: ${nextUncovered.isEmpty ? 'none' : nextUncovered}',
            ),
            trailing: IconButton(
              tooltip: 'Refresh',
              onPressed: _isSaving ? null : _loadSummary,
              icon: Icon(Icons.refresh),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddPayment() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add Hall Payment',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text(
              'Record only money you paid to the hall. Games are counted automatically when you save them.',
              style: TextStyle(color: Colors.grey[700]),
            ),
            SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 620;
              final amountField = TextField(
                controller: _paymentAmountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₪',
                  border: OutlineInputBorder(),
                ),
              );
              final dateField = TextField(
                controller: _paymentDateController,
                decoration: InputDecoration(
                  labelText: 'Payment date',
                  border: OutlineInputBorder(),
                ),
              );

              if (isNarrow) {
                return Column(
                  children: [
                    amountField,
                    SizedBox(height: 12),
                    dateField,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: amountField),
                  SizedBox(width: 12),
                  Expanded(child: dateField),
                ],
              );
            }),
            SizedBox(height: 12),
            TextField(
              controller: _paymentNotesController,
              decoration: InputDecoration(
                labelText: 'Notes',
                hintText: 'Example: transfer for next month',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _addPayment,
              icon: Icon(Icons.payment),
              label: Text('Save Payment'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal[700],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnpaidGamesCard() {
    final visibleGames = _visibleGamesForRange();
    final unpaidGames =
        visibleGames.where((game) => game['_is_paid'] != true).toList();
    final balance = _intValue(_summary['balance']);
    final gamesRemaining = _intValue(_summary['gamesRemaining']);

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _hasDateRange
                        ? 'Games in Selected Range'
                        : unpaidGames.isEmpty
                            ? 'No Unpaid Games'
                            : 'Unpaid Games',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _showShareUnpaidDialog,
                  icon: Icon(Icons.copy),
                  label: Text('Copy for WhatsApp'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal[700],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              _hasDateRange
                  ? 'Showing played dates in this range and whether each one is paid.'
                  : unpaidGames.isEmpty
                      ? (balance > 0
                          ? 'Everything is paid. You are prepaid for $gamesRemaining more games.'
                          : 'Everything is paid exactly for now.')
                      : 'Payments cover the oldest games first. This list is what remains unpaid.',
              style: TextStyle(color: Colors.grey[700]),
            ),
            SizedBox(height: 12),
            _buildDateRangePicker(),
            SizedBox(height: 12),
            if (visibleGames.isEmpty)
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  _hasDateRange
                      ? 'No games in this range'
                      : balance > 0
                          ? 'Prepaid balance: ${_money(balance)}'
                          : 'No open hall debt',
                  style: TextStyle(
                    color: Colors.green[800],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              Column(
                children: visibleGames.map((game) {
                  final isPaid = game['_is_paid'] == true;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isPaid ? Icons.check_circle : Icons.event_busy,
                      color: isPaid ? Colors.green[700] : Colors.red[700],
                    ),
                    title: Text(_dateOnly(game['game_date']?.toString())),
                    subtitle: Text(
                      game['source'] == 'saved_game'
                          ? 'Saved game'
                          : 'Past game',
                    ),
                    trailing: Text(
                      '${_money(game['cost'])} • ${isPaid ? 'Paid' : 'Unpaid'}',
                      style: TextStyle(
                        color: isPaid ? Colors.green[700] : Colors.red[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangePicker() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: () => _pickRangeDate(isStart: true),
          icon: Icon(Icons.calendar_today),
          label: Text(
            _rangeStart == null
                ? 'From date'
                : _dateOnly(_rangeStart!.toIso8601String()),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _pickRangeDate(isStart: false),
          icon: Icon(Icons.event),
          label: Text(
            _rangeEnd == null
                ? 'To date'
                : _dateOnly(_rangeEnd!.toIso8601String()),
          ),
        ),
        if (_hasDateRange)
          TextButton.icon(
            onPressed: _clearDateRange,
            icon: Icon(Icons.clear),
            label: Text('Clear range'),
          ),
      ],
    );
  }

  Widget _buildPaymentsTable() {
    final payments = _paymentsWithCoverage();

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payment History',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            if (payments.isEmpty)
              Text('No hall payments yet')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Amount')),
                    DataColumn(label: Text('Covers From')),
                    DataColumn(label: Text('Games')),
                    DataColumn(label: Text('Notes')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: payments.map((payment) {
                    final startsFrom =
                        payment['_starts_from_date']?.toString() ?? '';
                    final coveredGames = _intValue(payment['_covered_games']);
                    final prepaidAmount = _intValue(payment['_prepaid_amount']);
                    return DataRow(cells: [
                      DataCell(Text(_dateOnly(payment['date']?.toString()))),
                      DataCell(Text(_money(payment['amount']))),
                      DataCell(Text(startsFrom.isEmpty ? '-' : startsFrom)),
                      DataCell(Text(
                        prepaidAmount > 0
                            ? '$coveredGames + prepaid ${_money(prepaidAmount)}'
                            : '$coveredGames',
                      )),
                      DataCell(Text(payment['notes']?.toString() ?? '')),
                      DataCell(
                        IconButton(
                          tooltip: 'Delete payment',
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: _isSaving
                              ? null
                              : () => _deletePayment(
                                    payment['hall_payment_id'],
                                  ),
                        ),
                      ),
                    ]);
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!, style: TextStyle(color: Colors.red)),
            SizedBox(height: 12),
            ElevatedButton(onPressed: _loadSummary, child: Text('Retry')),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hall Payments',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 4),
          Text(
            'Simple flow: save games as usual, add hall payments here, and watch the balance.',
            style: TextStyle(color: Colors.grey[700]),
          ),
          if ((_settings['opening_note']?.toString() ?? '').isNotEmpty) ...[
            SizedBox(height: 6),
            Text(
              _settings['opening_note'].toString(),
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
          SizedBox(height: 16),
          _buildSummary(),
          SizedBox(height: 12),
          _buildUnpaidGamesCard(),
          SizedBox(height: 12),
          _buildAddPayment(),
          SizedBox(height: 12),
          _buildPaymentsTable(),
        ],
      ),
    );
  }
}
