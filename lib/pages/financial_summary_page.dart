import 'package:flutter/material.dart';
import '../services/api_service.dart';

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

  // Summary stats
  int totalDebt = 0;
  int totalPaid = 0;
  int totalBalance = 0;

  // Sorting state
  String _sortBy = 'name'; // 'name' or 'balance'
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final response = await apiService.get('finance/team-financial-summary/1');
      if (response['success']) {
        setState(() {
          players = response['summary'] ?? [];
          defaultCost = response['defaultGameCost'] ?? 0;
          
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
        errorMessage = e.toString();
        isLoading = false;
      });
    }
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
      final res = await apiService.get('finance/player-financials/$username');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(child: Text('Error: $errorMessage', style: TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: _buildContent(),
                ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        // SUMMARY CARDS - more compact
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: Colors.teal[50],
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
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
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
