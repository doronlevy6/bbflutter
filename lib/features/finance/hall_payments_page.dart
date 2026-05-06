import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class HallPaymentsPage extends StatefulWidget {
  @override
  State<HallPaymentsPage> createState() => _HallPaymentsPageState();
}

class _HallPaymentsPageState extends State<HallPaymentsPage> {
  final ApiService _apiService = ApiService();
  final TextEditingController _defaultCostController =
      TextEditingController(text: '200');
  final TextEditingController _trackingStartController =
      TextEditingController(text: '2025-10-05');
  final TextEditingController _openingNoteController = TextEditingController();
  final TextEditingController _paymentAmountController = TextEditingController();
  final TextEditingController _paymentDateController = TextEditingController();
  final TextEditingController _paymentNotesController = TextEditingController();
  final TextEditingController _importDatesController = TextEditingController();
  final TextEditingController _importNotesController =
      TextEditingController(text: 'Manual import');

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  Map<String, dynamic> _summary = {};
  Map<String, dynamic> _settings = {};
  List<dynamic> _games = [];
  List<dynamic> _payments = [];

  @override
  void initState() {
    super.initState();
    _paymentDateController.text = _dateOnly(DateTime.now().toIso8601String());
    _loadSummary();
  }

  @override
  void dispose() {
    _defaultCostController.dispose();
    _trackingStartController.dispose();
    _openingNoteController.dispose();
    _paymentAmountController.dispose();
    _paymentDateController.dispose();
    _paymentNotesController.dispose();
    _importDatesController.dispose();
    _importNotesController.dispose();
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
        final settings = Map<String, dynamic>.from(response['settings'] ?? {});
        setState(() {
          _settings = settings;
          _summary = Map<String, dynamic>.from(response['summary'] ?? {});
          _games = List<dynamic>.from(response['games'] ?? []);
          _payments = List<dynamic>.from(response['payments'] ?? []);
          _defaultCostController.text =
              (settings['default_game_cost'] ?? 200).toString();
          _trackingStartController.text =
              _dateOnly(settings['tracking_start_date']?.toString());
          _openingNoteController.text =
              settings['opening_note']?.toString() ?? '';
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

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final response = await _apiService.putQueued('finance/hall/settings', {
        'default_game_cost':
            int.tryParse(_defaultCostController.text.trim()) ?? 200,
        'tracking_start_date': _trackingStartController.text.trim(),
        'opening_note': _openingNoteController.text.trim(),
      });
      if (response['success'] == true) {
        _showSnack(response['queued'] == true
            ? 'Saved offline. Will sync later.'
            : 'Hall settings saved');
        if (response['queued'] != true) await _loadSummary();
      } else {
        _showSnack(response['message']?.toString() ?? 'Save failed',
            error: true);
      }
    } catch (e) {
      _showSnack('Error saving settings: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _syncSavedGames() async {
    setState(() => _isSaving = true);
    try {
      final response =
          await _apiService.postQueued('finance/hall/sync-games', {});
      if (response['success'] == true) {
        final inserted = response['inserted'] ?? 0;
        _showSnack(response['queued'] == true
            ? 'Sync queued for later'
            : 'Synced $inserted saved games');
        if (response['queued'] != true) await _loadSummary();
      } else {
        _showSnack(response['message']?.toString() ?? 'Sync failed',
            error: true);
      }
    } catch (e) {
      _showSnack('Error syncing games: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  List<String> _parseImportDates(String raw) {
    final tokens = raw
        .split(RegExp(r'[\s,;]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final dates = <String>[];

    for (final token in tokens) {
      final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(token);
      if (iso != null) {
        dates.add('${iso.group(1)}-${iso.group(2)}-${iso.group(3)}');
        continue;
      }

      final dotted = RegExp(r'^(\d{1,2})\.(\d{1,2})(?:\.(\d{2,4}))?$')
          .firstMatch(token);
      if (dotted != null) {
        final day = dotted.group(1)!.padLeft(2, '0');
        final monthNumber = int.parse(dotted.group(2)!);
        final month = monthNumber.toString().padLeft(2, '0');
        var year = dotted.group(3);
        if (year == null) {
          year = monthNumber >= 10 ? '2025' : '2026';
        } else if (year.length == 2) {
          year = '20$year';
        }
        dates.add('$year-$month-$day');
      }
    }

    return dates.toSet().toList();
  }

  Future<void> _importDates() async {
    final dates = _parseImportDates(_importDatesController.text);
    if (dates.isEmpty) {
      _showSnack('No valid dates found', error: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final response = await _apiService.postQueued('finance/hall/import-dates',
          {'dates': dates, 'notes': _importNotesController.text.trim()});
      if (response['success'] == true) {
        _showSnack(response['queued'] == true
            ? 'Import queued for later'
            : 'Imported ${response['inserted']} dates, skipped ${response['skipped']}');
        if (response['queued'] != true) {
          _importDatesController.clear();
          await _loadSummary();
        }
      } else {
        _showSnack(response['message']?.toString() ?? 'Import failed',
            error: true);
      }
    } catch (e) {
      _showSnack('Error importing dates: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
            ? 'Payment queued for later'
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

  Future<void> _editGameCost(Map<String, dynamic> game) async {
    final costController =
        TextEditingController(text: game['cost']?.toString() ?? '0');
    final notesController =
        TextEditingController(text: game['notes']?.toString() ?? '');

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Hall Game'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_dateOnly(game['game_date']?.toString())),
            SizedBox(height: 12),
            TextField(
              controller: costController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Cost',
                prefixText: '₪',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: notesController,
              decoration: InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Save'),
          ),
        ],
      ),
    );

    if (shouldSave != true) return;

    setState(() => _isSaving = true);
    try {
      final response = await _apiService.putQueued(
        'finance/hall/games/${game['hall_game_id']}',
        {
          'cost': int.tryParse(costController.text.trim()) ?? 0,
          'notes': notesController.text.trim(),
        },
      );
      if (response['success'] == true) {
        _showSnack(response['queued'] == true
            ? 'Game update queued for later'
            : 'Hall game updated');
        if (response['queued'] != true) await _loadSummary();
      } else {
        _showSnack(response['message']?.toString() ?? 'Update failed',
            error: true);
      }
    } catch (e) {
      _showSnack('Error updating game: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            SizedBox(height: 8),
            Text(title, style: TextStyle(color: Colors.grey[700])),
            SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final balance = int.tryParse(_summary['balance']?.toString() ?? '0') ?? 0;
    final balanceColor = balance >= 0 ? Colors.green[700]! : Colors.red[700]!;
    final remaining = _summary['gamesRemaining'] ?? 0;
    final owed = _summary['gamesOwed'] ?? 0;
    final coverageText = balance >= 0
        ? '$remaining games left'
        : '$owed games owed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _summaryCard(
              title: 'Balance',
              value: _money(balance),
              icon: balance >= 0 ? Icons.savings : Icons.warning_amber,
              color: balanceColor,
            ),
            SizedBox(width: 12),
            _summaryCard(
              title: 'Coverage',
              value: coverageText,
              icon: Icons.event_available,
              color: Colors.blue[700]!,
            ),
            SizedBox(width: 12),
            _summaryCard(
              title: 'Hall Games',
              value: '${_summary['gameCount'] ?? 0}',
              icon: Icons.sports_basketball,
              color: Colors.orange[800]!,
            ),
          ],
        ),
        SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(Icons.timeline, color: Colors.indigo),
            title: Text(
              'Paid ${_money(_summary['totalPaid'])} • Cost ${_money(_summary['totalGameCost'])}',
            ),
            subtitle: Text(
              'Covered through: ${_dateOnly(_summary['coveredThroughDate']?.toString()).isEmpty ? 'none yet' : _dateOnly(_summary['coveredThroughDate']?.toString())}'
              ' • Next uncovered: ${_dateOnly(_summary['nextUncoveredGameDate']?.toString()).isEmpty ? 'none' : _dateOnly(_summary['nextUncoveredGameDate']?.toString())}',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettings() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _defaultCostController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Default cost per game',
                      prefixText: '₪',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _trackingStartController,
                    decoration: InputDecoration(
                      labelText: 'Track from date',
                      hintText: '2025-10-05',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            TextField(
              controller: _openingNoteController,
              decoration: InputDecoration(
                labelText: 'Opening note',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveSettings,
              icon: Icon(Icons.save),
              label: Text('Save Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Actions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _syncSavedGames,
                  icon: Icon(Icons.sync),
                  label: Text('Sync from saved games'),
                ),
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _loadSummary,
                  icon: Icon(Icons.refresh),
                  label: Text('Refresh'),
                ),
              ],
            ),
          ],
        ),
      ),
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
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _paymentAmountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixText: '₪',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _paymentDateController,
                    decoration: InputDecoration(
                      labelText: 'Payment date',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            TextField(
              controller: _paymentNotesController,
              decoration: InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _addPayment,
              icon: Icon(Icons.payment),
              label: Text('Submit Payment'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportDates() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Import Past Dates',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text(
              'Paste dates like 7.10, 11.10, 3.1 or ISO dates. Oct-Dec default to 2025, Jan-Mar default to 2026.',
              style: TextStyle(color: Colors.grey[700]),
            ),
            SizedBox(height: 12),
            TextField(
              controller: _importDatesController,
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: 'Dates',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: _importNotesController,
              decoration: InputDecoration(
                labelText: 'Import notes',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _importDates,
              icon: Icon(Icons.upload_file),
              label: Text('Import Dates'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGamesTable() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hall Games',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            if (_games.isEmpty)
              Text('No hall games yet')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Cost')),
                    DataColumn(label: Text('Source')),
                    DataColumn(label: Text('Game ID')),
                    DataColumn(label: Text('Notes')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: _games.map((raw) {
                    final game = Map<String, dynamic>.from(raw as Map);
                    return DataRow(cells: [
                      DataCell(Text(_dateOnly(game['game_date']?.toString()))),
                      DataCell(Text(_money(game['cost']))),
                      DataCell(Text(game['source']?.toString() ?? '')),
                      DataCell(Text(game['game_id']?.toString() ?? '-')),
                      DataCell(Text(game['notes']?.toString() ?? '')),
                      DataCell(
                        IconButton(
                          tooltip: 'Edit cost',
                          icon: Icon(Icons.edit),
                          onPressed: _isSaving ? null : () => _editGameCost(game),
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

  Widget _buildPaymentsTable() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hall Payments',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            if (_payments.isEmpty)
              Text('No hall payments yet')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Amount')),
                    DataColumn(label: Text('Notes')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: _payments.map((raw) {
                    final payment = Map<String, dynamic>.from(raw as Map);
                    return DataRow(cells: [
                      DataCell(Text(_dateOnly(payment['date']?.toString()))),
                      DataCell(Text(_money(payment['amount']))),
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
            _settings['opening_note']?.toString() ?? '',
            style: TextStyle(color: Colors.grey[700]),
          ),
          SizedBox(height: 16),
          _buildSummary(),
          SizedBox(height: 12),
          _buildActions(),
          _buildSettings(),
          _buildAddPayment(),
          _buildImportDates(),
          _buildGamesTable(),
          _buildPaymentsTable(),
        ],
      ),
    );
  }
}
