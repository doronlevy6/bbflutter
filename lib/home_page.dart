// lib/home_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'welcome_page.dart';
import 'login_page.dart'; // Import your other pages
import 'manager_page.dart';
import 'grade_page.dart';
import 'get_score_page.dart';
import 'playgound_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:responsive_builder/responsive_builder.dart'; // Import responsive_builder

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Define the default page and title
  Widget _currentPage = WelcomePage();
  String _appBarTitle = 'Teams and Averages';

  // Method to build each icon in the Drawer
  Widget _buildDrawerIcon(BuildContext context,
      {required IconData icon,
        required Color? color,
        required String tooltip,
        required Widget page,
        required String title}) {
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
          padding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0), // Adjust padding
          child: Row(
            children: [
              Icon(
                icon,
                color: color,
                size: 24, // Reduced size for better responsiveness
              ),
              SizedBox(width: 12),
              // Use Expanded to allow text to take available space
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16, // Adjusted font size
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis, // Handle overflow
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Method to get user info from SharedPreferences
  Future<Map<String, String>> _getUserInfo() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? username = prefs.getString('user');
    String? email = prefs.getString('email');
    return {
      'username': username ?? 'Guest',
      'email': email ?? 'guest@example.com',
    };
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      builder: (context, sizingInformation) {
        // Determine device type
        var deviceType = sizingInformation.deviceScreenType;

        // Set Drawer width based on device type
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
          // Mobile
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
          // Mobile
            appBarFontSize = 20;
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(
              _appBarTitle,
              style: GoogleFonts.akayaKanadaka(
                fontSize: appBarFontSize,
                fontWeight: FontWeight.w400,
                color: Colors.white,
              ),
            ),
            backgroundColor: Colors.green[700], // Base green color
          ),
          drawer: Drawer(
            width: drawerWidth, // Set adaptive width
            child: FutureBuilder<Map<String, String>>(
              future: _getUserInfo(),
              builder: (context, snapshot) {
                String username = snapshot.data?['username'] ?? 'Guest';
                String email = snapshot.data?['email'] ?? 'guest@example.com';
                return Column(
                  children: [
                    UserAccountsDrawerHeader(
                      accountName: Text(
                        username,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16, // Adjust font size
                        ),
                      ),
                      accountEmail: Text(
                        email,
                        style: TextStyle(
                          fontSize: 14, // Adjust font size
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
                        padding: EdgeInsets.zero, // Remove default padding
                        children: [
                          // Adding the Drawer links in the specified order
                          _buildDrawerIcon(
                            context,
                            icon: Icons.login,
                            color: Colors.blue[300],
                            tooltip: 'Login/Register',
                            page: LoginPage(),
                            title: 'Login',
                          ),
                          _buildDrawerIcon(
                            context,
                            icon: Icons.home,
                            color: Colors.green[300],
                            tooltip: 'Home',
                            page: WelcomePage(),
                            title: 'Home',
                          ),
                          _buildDrawerIcon(
                            context,
                            icon: Icons.grade,
                            color: Colors.orange[300],
                            tooltip: 'Grade Page',
                            page: GradePage(),
                            title: '${username}`s Grades',
                          ),
                          _buildDrawerIcon(
                            context,
                            icon: Icons.score,
                            color: Colors.purple[300],
                            tooltip: 'Get Score Page',
                            page: GetScorePage(),
                            title: 'Get Score',
                          ),
                          _buildDrawerIcon(
                            context,
                            icon: Icons.group,
                            color: Colors.teal[300],
                            tooltip: 'Teams Page',
                            page: PlayGround(),
                            title: 'Playground',
                          ),
                          _buildDrawerIcon(
                            context,
                            icon: Icons.admin_panel_settings,
                            color: Colors.red[300],
                            tooltip: 'Manager Page',
                            page: ManagementPage(),
                            title: 'Management',
                          ),
                        ],
                      ),
                    ),
                    Divider(),
                    ListTile(
                      leading: Icon(Icons.logout, color: Colors.red),
                      title: Text(
                        'Logout',
                        style: TextStyle(
                          fontSize: 16, // Adjust font size
                        ),
                      ),
                      onTap: () async {
                        SharedPreferences prefs =
                        await SharedPreferences.getInstance();
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
        );
      },
    );
  }
}
