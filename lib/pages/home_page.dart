import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'welcome_page.dart';
import 'login_page.dart';
import 'manager_page.dart';
import 'grade_page.dart';
import 'settings.dart';
import 'playgound_page.dart';
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

  @override
  void initState() {
    super.initState();
    _loadLanguage();
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

  // Get user information (username and email) from SharedPreferences
  Future<Map<String, String>> _getUserInfo() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? username = prefs.getString('user');
    String? email = prefs.getString('email');
    return {
      'username': username ?? 'Guest',
      'email': email ?? 'doron@gmail.com',//?
    };
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
                  final loginTooltip = _isHebrew ? 'התחברות/רישום' : 'Login/Register';
                  final homeTitle = _isHebrew ? 'רשימת נרשמים' : 'enlisted playres';
                  final gradeTitle = _isHebrew ? 'ציוני  $username ' : "$username's Grades";
                  final gradeTooltip = _isHebrew ? 'ציונים' : 'Grade Page';
                  final managementTitle = _isHebrew ? 'ניהול' : 'Management';
                  final playgroundTitle = _isHebrew ? 'מגרש משחקים' : 'Playground';
                  final settingsTitle = _isHebrew ? 'הגדרות' : 'Settings';
                  final logoutTitle = _isHebrew ? 'התנתק' : 'Logout';

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
                            // Conditionally display management option for user 'doron'
                            if (username.toLowerCase() == 'doron' || username.toLowerCase() == 'dor')
                              _buildDrawerIcon(
                                context,
                                icon: Icons.admin_panel_settings,
                                color: Colors.red[300],
                                tooltip: managementTitle,
                                page: ManagementPage(),
                                title: managementTitle,
                              ),
                            _buildDrawerIcon(
                              context,
                              icon: Icons.group,
                              color: Colors.teal[300],
                              tooltip: playgroundTitle,
                              page: PlayGround(),
                              title: playgroundTitle,
                            ),
                            if (username.toLowerCase() == 'doron')
                            _buildDrawerIcon(
                              context,
                              icon: Icons.settings,
                              color: Colors.grey[300],
                              tooltip: settingsTitle,
                              page: SettingsPage(),
                              title: settingsTitle,
                            ),
                          ],
                        ),
                      ),
                      Divider(),
                      ListTile(
                        leading: Icon(Icons.logout, color: Colors.red),
                        title: Text(
                          logoutTitle,
                          style: TextStyle(
                            fontSize: 16,
                          ),
                        ),
                        onTap: () async {
                          SharedPreferences prefs = await SharedPreferences.getInstance();
                          await prefs.clear();
                          Navigator.pushNamedAndRemoveUntil(
                              context, '/login', (Route<dynamic> route) => false);
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
