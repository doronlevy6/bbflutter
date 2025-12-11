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
        
        // PLAYER LIST - COMPACT
        Expanded(
          child: ListView.builder(
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
              
              bool isPositive = balance >= 0;
              
              return Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey[200]!, width: 0.5)),
                ),
                child: Row(
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
                    
                    // Name
                    Expanded(
                      child: Text(
                        player['username'],
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    
                    // Games count + remainder
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${games >= 0 ? (games > 0 ? '+' : '') : ''}$games',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isPositive ? Colors.green[700] : Colors.red[700],
                              ),
                            ),
                            SizedBox(width: 2),
                            Icon(Icons.sports_basketball, size: 14, color: Colors.grey),
                          ],
                        ),
                        if (remainder != 0)
                          Text(
                            '${remainder >= 0 ? '+' : ''}$remainder₪',
                            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                          ),
                      ],
                    ),
                  ],
                ),
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
