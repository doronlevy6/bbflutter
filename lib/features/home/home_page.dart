import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../pages/welcome_page.dart';
import '../../pages/login_page.dart';
import '../../pages/player_management_page.dart';
import '../../pages/grade_page.dart';
import '../../pages/settings.dart';
import '../../pages/playground_page.dart';
import '../../pages/interactive_playground_page.dart';
import '../../pages/financial_summary_page.dart';
import '../../pages/wallet_page.dart';
import '../../pages/scoreboard_page.dart';
import '../../pages/draw_page.dart';
import '../../pages/coach_board_page.dart';
import '../../services/api_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:responsive_builder/responsive_builder.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Default page and title in English
  Widget _currentPage = WelcomePage();
  String _currentUsername = 'Guest';
  String _appBarTitle = 'Teams and Averages';
  bool _isHebrew = false;
  bool _isAdmin = false;
  final ApiService _apiService = ApiService();
  static const String _lastPageKeyPref = 'home_last_page_key_v1';
  // Fallback only. Workspace tasks and GitHub Pages deploy pass APP_ENV explicitly.
  static const String _appEnv =
      String.fromEnvironment('APP_ENV', defaultValue: 'PROD');
  static const String _deploymentTarget =
      String.fromEnvironment('DEPLOY_TARGET', defaultValue: 'local');
  bool get _showEnvBadge => _deploymentTarget != 'github_pages';

  @override
  void initState() {
    super.initState();
    _initializeHomeState();
  }

  Future<void> _initializeHomeState() async {
    final prefs = await SharedPreferences.getInstance();
    final isHebrew = prefs.getBool('isHebrew') ?? false;
    final isAdmin = prefs.getBool('is_admin') ?? false;
    final username = prefs.getString('user') ?? 'Guest';
    final savedPage = prefs.getString(_lastPageKeyPref) ?? 'welcome';

    if (!mounted) return;
    setState(() {
      _isHebrew = isHebrew;
      _isAdmin = isAdmin;
      _currentUsername = username;
    });
    await _setPage(savedPage, persist: false);
  }

  String _normalizePageKey(String pageKey) {
    const adminOnlyPages = <String>{
      'player_management',
      'financial_summary',
      'settings',
    };
    if (!_isAdmin && adminOnlyPages.contains(pageKey)) {
      return 'welcome';
    }
    return pageKey;
  }

  Widget _pageForKey(String pageKey) {
    switch (pageKey) {
      case 'login':
        return LoginPage();
      case 'grade':
        return GradePage();
      case 'wallet':
        return MyWalletPage();
      case 'playground':
        return PlayGround();
      case 'interactive_builder':
        return InteractivePlaygroundPage();
      case 'scoreboard':
        return ScoreboardPage();
      case 'player_management':
        return PlayerManagementPage();
      case 'financial_summary':
        return FinancialSummaryPage();
      case 'settings':
        return SettingsPage();
      case 'coach_board':
        return CoachBoardPage();
      case 'draw':
        return DrawPage();
      case 'welcome':
      default:
        return WelcomePage();
    }
  }

  String _titleForPageKey(String pageKey) {
    switch (pageKey) {
      case 'login':
        return _isHebrew ? 'התחברות/רישום' : 'Login';
      case 'grade':
        return _isHebrew
            ? 'ציוני  $_currentUsername '
            : "$_currentUsername's Grades";
      case 'wallet':
        return _isHebrew ? 'הארנק שלי' : 'My Wallet';
      case 'playground':
        return _isHebrew ? 'מגרש משחקים' : 'Playground';
      case 'interactive_builder':
        return _isHebrew ? 'בנייה אינטראקטיבית' : 'Interactive Builder';
      case 'scoreboard':
        return _isHebrew ? 'סקורבורד' : 'Scoreboard';
      case 'player_management':
        return _isHebrew ? 'ניהול שחקנים' : 'Player Management';
      case 'financial_summary':
        return _isHebrew ? 'סיכום פיננסי' : 'Financial Summary';
      case 'settings':
        return _isHebrew ? 'הגדרות' : 'Settings';
      case 'coach_board':
        return _isHebrew ? 'לוח מאמן' : 'Coach Board';
      case 'draw':
        return _isHebrew ? 'הגרלה' : 'Draw';
      case 'welcome':
      default:
        return _isHebrew ? 'רשימת נרשמים' : 'enlisted playres';
    }
  }

  Future<void> _setPage(String pageKey, {bool persist = true}) async {
    final normalized = _normalizePageKey(pageKey);
    if (!mounted) return;
    setState(() {
      _currentPage = _pageForKey(normalized);
      _appBarTitle = _titleForPageKey(normalized);
    });
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastPageKeyPref, normalized);
    }
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

  bool _isValidEmail(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    final basicEmailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return basicEmailRegex.hasMatch(trimmed);
  }

  Future<void> _showEditEmailDialog(String currentEmail) async {
    final controller = TextEditingController(text: currentEmail);
    bool isSaving = false;
    String? localError;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            return AlertDialog(
              title: Text(_isHebrew ? 'עדכון אימייל' : 'Update Email'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: _isHebrew ? 'אימייל' : 'Email',
                      border: OutlineInputBorder(),
                      errorText: localError,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(ctx),
                  child: Text(_isHebrew ? 'ביטול' : 'Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final nextEmail = controller.text.trim();
                          if (!_isValidEmail(nextEmail)) {
                            setLocalState(() {
                              localError = _isHebrew
                                  ? 'כתובת אימייל לא תקינה'
                                  : 'Invalid email address';
                            });
                            return;
                          }

                          setLocalState(() {
                            isSaving = true;
                            localError = null;
                          });

                          final response =
                              await _apiService.updateMyEmail(nextEmail);
                          if (!mounted) return;

                          if (response['success'] == true) {
                            if (Navigator.of(ctx).canPop()) {
                              Navigator.of(ctx).pop();
                            }
                            setState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _isHebrew
                                      ? 'האימייל עודכן בהצלחה'
                                      : 'Email updated successfully',
                                ),
                                backgroundColor: Colors.green[700],
                              ),
                            );
                            return;
                          }

                          setLocalState(() {
                            isSaving = false;
                            localError = (response['message']?.toString() ??
                                (_isHebrew ? 'עדכון נכשל' : 'Update failed'));
                          });
                        },
                  child: isSaving
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isHebrew ? 'שמור' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _clearSessionPrefs() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    // Regular logout: clear sensitive session only.
    await prefs.remove('token');
    await prefs.remove('refresh_token');
    await prefs.remove('token_expires_in');
    await prefs.remove('refresh_token_expires_in');
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

    await _apiService.logout();
    await _apiService.clearFailedQueue();
    await _apiService.clearUserScopedLocalState();
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
    required String pageKey,
    required String title,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          Navigator.pop(context); // Close the drawer
          _setPage(pageKey);
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
                  final walletTitle = _isHebrew ? 'הארנק שלי' : 'My Wallet';
                  final walletTooltip =
                      _isHebrew ? 'ארנק אישי' : 'Personal Wallet';
                  final playgroundTitle =
                      _isHebrew ? 'מגרש משחקים' : 'Playground';
                  final settingsTitle = _isHebrew ? 'הגדרות' : 'Settings';
                  final drawTitle = _isHebrew ? 'הגרלה' : 'Draw';
                  final drawTooltip =
                      _isHebrew ? 'הגרלת כדורסל' : 'Basketball Draw';
                  final coachBoardTitle =
                      _isHebrew ? 'לוח מאמן' : 'Coach Board';
                  final coachBoardTooltip =
                      _isHebrew ? 'לוח טקטי לתרגילים' : 'Tactical Coach Board';
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
                        accountEmail: Row(
                          children: [
                            Expanded(
                              child: Text(
                                email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip:
                                  _isHebrew ? 'עריכת אימייל' : 'Edit email',
                              icon: Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: Colors.white70,
                              ),
                              onPressed: () => _showEditEmailDialog(email),
                              splashRadius: 18,
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                            ),
                          ],
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
                              pageKey: 'login',
                              title: loginTitle,
                            ),
                            _buildDrawerIcon(
                              context,
                              icon: Icons.home,
                              color: Colors.green[300],
                              tooltip: homeTitle,
                              pageKey: 'welcome',
                              title: homeTitle,
                            ),
                            _buildDrawerIcon(
                              context,
                              icon: Icons.grade,
                              color: Colors.orange[300],
                              tooltip: gradeTooltip,
                              pageKey: 'grade',
                              title: gradeTitle,
                            ),
                            _buildDrawerIcon(
                              context,
                              icon: Icons.account_balance_wallet,
                              color: Colors.teal[400],
                              tooltip: walletTooltip,
                              pageKey: 'wallet',
                              title: walletTitle,
                            ),
                            _buildDrawerIcon(
                              context,
                              icon: Icons.group,
                              color: Colors.teal[300],
                              tooltip: playgroundTitle,
                              pageKey: 'playground',
                              title: playgroundTitle,
                            ),
                            _buildDrawerIcon(
                              context,
                              icon: Icons.drag_indicator,
                              color: Colors.indigo[300],
                              tooltip: _isHebrew
                                  ? 'בנייה אינטראקטיבית'
                                  : 'Interactive Builder',
                              pageKey: 'interactive_builder',
                              title: _isHebrew
                                  ? 'בנייה אינטראקטיבית'
                                  : 'Interactive Builder',
                            ),
                            _buildDrawerIcon(
                              context,
                              icon: Icons.sports_basketball,
                              color: Colors.orange[400],
                              tooltip: _isHebrew ? 'סקורבורד' : 'Scoreboard',
                              pageKey: 'scoreboard',
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
                                pageKey: 'player_management',
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
                                pageKey: 'financial_summary',
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
                                pageKey: 'settings',
                                title: settingsTitle,
                              ),
                            _buildDrawerIcon(
                              context,
                              icon: Icons.co_present,
                              color: Colors.blueGrey[500],
                              tooltip: coachBoardTooltip,
                              pageKey: 'coach_board',
                              title: coachBoardTitle,
                            ),
                            _buildDrawerIcon(
                              context,
                              icon: Icons.casino,
                              color: Colors.amber[700],
                              tooltip: drawTooltip,
                              pageKey: 'draw',
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
