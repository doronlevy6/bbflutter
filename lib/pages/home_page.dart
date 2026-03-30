import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'welcome_page.dart';
import 'login_page.dart';
import 'player_management_page.dart';
import 'grade_page.dart';
import 'settings.dart';
import 'playground_page.dart';
import 'interactive_playground_page.dart';
import 'financial_summary_page.dart';
import 'scoreboard_page.dart';
import 'draw_page.dart';
import '../services/api_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:responsive_builder/responsive_builder.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Default page and title in English
  Widget _currentPage = WelcomePage();
  String _appBarTitle = 'Teams and Averages';
  bool _isHebrew = false;
  bool _isAdmin = false;
  final ApiService _apiService = ApiService();
  // Fallback only. Workspace tasks and GitHub Pages deploy pass APP_ENV explicitly.
  static const String _appEnv =
      String.fromEnvironment('APP_ENV', defaultValue: 'PROD');
  static const String _deploymentTarget =
      String.fromEnvironment('DEPLOY_TARGET', defaultValue: 'local');
  bool get _showEnvBadge => _deploymentTarget != 'github_pages';

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    _loadAdminStatus();
  }

  // Load the language setting from SharedPreferences using key 'isHebrew'
  void _loadLanguage() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isHebrew = prefs.getBool('isHebrew') ?? false;
    setState(() {
      _isHebrew = isHebrew;
      // Update AppBar title based on the language
      _appBarTitle = _isHebrew ? 'רשימת נרשמים' : 'enlisted playres';
    });
  }

  // Load admin status from SharedPreferences
  void _loadAdminStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isAdmin = prefs.getBool('is_admin') ?? false;
    setState(() {
      _isAdmin = isAdmin;
    });
  }

  // Get user information (username and email) from SharedPreferences
  Future<Map<String, String>> _getUserInfo() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? username = prefs.getString('user');
    String? email = prefs.getString('email');
    return {
      'username': username ?? 'Guest',
      'email': email ?? 'doron@gmail.com', //?
    };
  }

  Future<void> _clearSessionPrefs() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    // Regular logout: clear sensitive session only.
    await prefs.remove('token');
    await prefs.remove('user');
    await prefs.remove('email');
    await prefs.remove('team_id');
    await prefs.remove('is_admin');
  }

  Future<void> _clearAllLocalAppData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  Future<void> _handleDebugReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset all local data?'),
        content: Text(
          'This clears token, cache, and all offline pending data on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _clearAllLocalAppData();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/login',
      (Route<dynamic> route) => false,
    );
  }

  Future<void> _handleLogout() async {
    final stats = await _apiService.getQueueStats();
    final pending = stats['pending'] ?? 0;

    if (pending > 0 && mounted) {
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Pending offline updates'),
          content: Text(
            'You have $pending pending actions not synced yet.\n\n'
            'Sync before logout to avoid losing updates.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: Text(
                'Discard & Logout',
                style: TextStyle(color: Colors.red),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'sync'),
              child: Text('Sync & Logout'),
            ),
          ],
        ),
      );

      if (action == null || action == 'cancel') {
        return;
      }

      if (action == 'sync') {
        await _apiService.processQueue();
        final updatedStats = await _apiService.getQueueStats();
        final stillPending = updatedStats['pending'] ?? 0;
        if (stillPending > 0 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$stillPending items are still pending. Try again with connection or discard.',
              ),
            ),
          );
          return;
        }
      } else if (action == 'discard') {
        await _apiService.clearQueue();
      }
    }

    await _apiService.clearFailedQueue();
    await _clearSessionPrefs();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/login',
      (Route<dynamic> route) => false,
    );
  }

  // Build a drawer icon item with tooltip and navigation functionality
  Widget _buildDrawerIcon(
    BuildContext context, {
    required IconData icon,
    required Color? color,
    required String tooltip,
    required Widget page,
    required String title,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          Navigator.pop(context); // Close the drawer
          setState(() {
            _currentPage = page;
            _appBarTitle = title;
          });
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
          child: Row(
            children: [
              Icon(
                icon,
                color: color,
                size: 24,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      builder: (context, sizingInformation) {
        // Determine device type and set drawer width accordingly
        var deviceType = sizingInformation.deviceScreenType;
        double drawerWidth;
        switch (deviceType) {
          case DeviceScreenType.desktop:
            drawerWidth = 300;
            break;
          case DeviceScreenType.tablet:
            drawerWidth = 250;
            break;
          case DeviceScreenType.watch:
            drawerWidth = 200;
            break;
          default:
            drawerWidth = MediaQuery.of(context).size.width * 0.75;
        }

        // Set AppBar title font size based on device type
        double appBarFontSize;
        switch (deviceType) {
          case DeviceScreenType.desktop:
            appBarFontSize = 28;
            break;
          case DeviceScreenType.tablet:
            appBarFontSize = 24;
            break;
          case DeviceScreenType.watch:
            appBarFontSize = 16;
            break;
          default:
            appBarFontSize = 20;
        }

        return Directionality(
          textDirection: _isHebrew ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            appBar: AppBar(
              title: Text(
                _appBarTitle,
                style: GoogleFonts.akayaKanadaka(
                  fontSize: appBarFontSize,
                  fontWeight: FontWeight.w400,
                  color: Colors.white,
                ),
              ),
              actions: [
                if (_showEnvBadge)
                  Tooltip(
                    message: 'API: ${_apiService.apiUrl}',
                    child: Container(
                      margin:
                          EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _appEnv.toUpperCase() == 'LOCAL'
                            ? Colors.green[900]
                            : Colors.blueGrey[800],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          'FE: ${_appEnv.toUpperCase()}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
              backgroundColor: Colors.green[700],
            ),
            drawer: Drawer(
              width: drawerWidth,
              child: FutureBuilder<Map<String, String>>(
                future: _getUserInfo(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }
                  String username = snapshot.data?['username'] ?? 'Guest';
                  String email = snapshot.data?['email'] ?? 'doron@gmail.com';

                  // Define localized text based on _isHebrew flag
                  final loginTitle = _isHebrew ? 'התחברות/רישום' : 'Login';
                  final loginTooltip =
                      _isHebrew ? 'התחברות/רישום' : 'Login/Register';
                  final homeTitle =
                      _isHebrew ? 'רשימת נרשמים' : 'enlisted playres';
                  final gradeTitle =
                      _isHebrew ? 'ציוני  $username ' : "$username's Grades";
                  final gradeTooltip = _isHebrew ? 'ציונים' : 'Grade Page';
                  final playgroundTitle =
                      _isHebrew ? 'מגרש משחקים' : 'Playground';
                  final settingsTitle = _isHebrew ? 'הגדרות' : 'Settings';
                  final drawTitle = _isHebrew ? 'הגרלה' : 'Draw';
                  final drawTooltip =
                      _isHebrew ? 'הגרלת כדורסל' : 'Basketball Draw';
                  final logoutTitle = _isHebrew ? 'התנתק' : 'Logout';
                  final resetTitle = _isHebrew
                      ? 'איפוס נתונים מקומיים (דיבוג)'
                      : 'Reset Local Data (Debug)';

                  return Column(
                    children: [
                      UserAccountsDrawerHeader(
                        accountName: Text(
                          username,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        accountEmail: Text(
                          email,
                          style: TextStyle(
                            fontSize: 14,
                          ),
                        ),
                        currentAccountPicture: CircleAvatar(
                          backgroundColor: Colors.white,
                          child: Icon(
                            Icons.person,
                            size: 40,
                            color: Colors.green[700],
                          ),
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green[600],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            _buildDrawerIcon(
                              context,
                              icon: Icons.login,
                              color: Colors.blue[300],
                              tooltip: loginTooltip,
                              page: LoginPage(),
                              title: loginTitle,
                            ),
                            _buildDrawerIcon(
                              context,
                              icon: Icons.home,
                              color: Colors.green[300],
                              tooltip: homeTitle,
                              page: WelcomePage(),
                              title: homeTitle,
                            ),
                            _buildDrawerIcon(
                              context,
                              icon: Icons.grade,
                              color: Colors.orange[300],
                              tooltip: gradeTooltip,
                              page: GradePage(),
                              title: gradeTitle,
                            ),
                            _buildDrawerIcon(
                              context,
                              icon: Icons.group,
                              color: Colors.teal[300],
                              tooltip: playgroundTitle,
                              page: PlayGround(),
                              title: playgroundTitle,
                            ),
                            _buildDrawerIcon(
                              context,
                              icon: Icons.drag_indicator,
                              color: Colors.indigo[300],
                              tooltip: _isHebrew
                                  ? 'בנייה אינטראקטיבית'
                                  : 'Interactive Builder',
                              page: InteractivePlaygroundPage(),
                              title: _isHebrew
                                  ? 'בנייה אינטראקטיבית'
                                  : 'Interactive Builder',
                            ),
                            _buildDrawerIcon(
                              context,
                              icon: Icons.sports_basketball,
                              color: Colors.orange[400],
                              tooltip: _isHebrew ? 'סקורבורד' : 'Scoreboard',
                              page: ScoreboardPage(),
                              title: _isHebrew ? 'סקורבורד' : 'Scoreboard',
                            ),
                            // ADMIN SECTION - at the bottom
                            if (_isAdmin) Divider(height: 20),
                            if (_isAdmin)
                              _buildDrawerIcon(
                                context,
                                icon: Icons.manage_accounts,
                                color: Colors.purple[300],
                                tooltip: _isHebrew
                                    ? 'ניהול שחקנים'
                                    : 'Player Management',
                                page: PlayerManagementPage(),
                                title: _isHebrew
                                    ? 'ניהול שחקנים'
                                    : 'Player Management',
                              ),
                            if (_isAdmin)
                              _buildDrawerIcon(
                                context,
                                icon: Icons.account_balance_wallet,
                                color: Colors.teal[400],
                                tooltip: _isHebrew
                                    ? 'סיכום פיננסי'
                                    : 'Financial Summary',
                                page: FinancialSummaryPage(),
                                title: _isHebrew
                                    ? 'סיכום פיננסי'
                                    : 'Financial Summary',
                              ),
                            if (_isAdmin)
                              _buildDrawerIcon(
                                context,
                                icon: Icons.settings,
                                color: Colors.grey[600],
                                tooltip: settingsTitle,
                                page: SettingsPage(),
                                title: settingsTitle,
                              ),
                            _buildDrawerIcon(
                              context,
                              icon: Icons.casino,
                              color: Colors.amber[700],
                              tooltip: drawTooltip,
                              page: DrawPage(),
                              title: drawTitle,
                            ),
                          ],
                        ),
                      ),
                      Divider(),
                      if (_showEnvBadge)
                        ListTile(
                          leading: Icon(Icons.cleaning_services,
                              color: Colors.orange[700]),
                          title: Text(
                            resetTitle,
                            style: TextStyle(
                              fontSize: 14,
                            ),
                          ),
                          onTap: () async {
                            await _handleDebugReset();
                          },
                        ),
                      ListTile(
                        leading: Icon(Icons.logout, color: Colors.red),
                        title: Text(
                          logoutTitle,
                          style: TextStyle(
                            fontSize: 16,
                          ),
                        ),
                        onTap: () async {
                          await _handleLogout();
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
            body: _currentPage,
          ),
        );
      },
    );
  }
}
