// lib/home_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'welcome_page.dart';
import 'login_page.dart'; // Import your other pages
import 'manager_page.dart';
import 'grade_page.dart';
import 'get_score_page.dart';
import 'teams_page.dart';
import 'package:google_fonts/google_fonts.dart';


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
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 30,
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _appBarTitle,
          style: GoogleFonts.akayaKanadaka( // Replace with the correct method if different
            fontSize: 24,
            fontWeight: FontWeight.w400,
            color: Colors.white,
          ),

        ),

        backgroundColor: Colors.green[700], // Base green color
      ),
      drawer: Drawer(
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
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  accountEmail: Text(email),
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
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: GridView.count(
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      children: [
                        _buildDrawerIcon(
                          context,
                          icon: Icons.home,
                          color: Colors.green[300],
                          tooltip: 'Home',
                          page: WelcomePage(),
                          title: 'Teams and Averages',
                        ),
                        _buildDrawerIcon(
                          context,
                          icon: Icons.login,
                          color: Colors.blue[300],
                          tooltip: 'Login/Register',
                          page: LoginPage(),
                          title: 'Login Page',
                        ),
                        _buildDrawerIcon(
                          context,
                          icon: Icons.admin_panel_settings,
                          color: Colors.red[300],
                          tooltip: 'Manager Page',
                          page: ManagementPage(),
                          title: 'Manager Page',
                        ),
                        _buildDrawerIcon(
                          context,
                          icon: Icons.grade,
                          color: Colors.orange[300],
                          tooltip: 'Grade Page',
                          page: GradePage(),
                          title: 'Grade Page',
                        ),
                        _buildDrawerIcon(
                          context,
                          icon: Icons.score,
                          color: Colors.purple[300],
                          tooltip: 'Get Score Page',
                          page: GetScorePage(),
                          title: 'Get Score Page',
                        ),
                        _buildDrawerIcon(
                          context,
                          icon: Icons.group,
                          color: Colors.teal[300],
                          tooltip: 'Teams Page',
                          page: TeamsPage(),
                          title: 'Teams Page',
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(),
                ListTile(
                  leading: Icon(Icons.logout, color: Colors.red),
                  title: Text('Logout'),
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
  }
}
