// lib/home_page.dart

import 'package:bb22/welcome_page.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatelessWidget {
  // Home page with Drawer for navigation
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Player Ranking App'),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              child: Text('Navigation',
                  style: TextStyle(color: Colors.white, fontSize: 24)),
              decoration: BoxDecoration(
                color: Colors.lightGreen,
              ),
            ),
            ListTile(
              leading: Icon(Icons.login),
              title: Text('Login/Register'),
              onTap: () {
                Navigator.pushNamed(context, '/login');
              },
            ),
            ListTile(
              leading: Icon(Icons.home),
              title: Text('Welcome Page'),
              onTap: () {
                Navigator.pushNamed(context, '/welcome');
              },
            )
,
            ListTile(
              leading: Icon(Icons.admin_panel_settings),
              title: Text('Manager Page'),
              onTap: () {
                Navigator.pushNamed(context, '/manager');
              },
            ),
            ListTile(
              leading: Icon(Icons.grade),
              title: Text('Grade Page'),
              onTap: () {
                Navigator.pushNamed(context, '/grade');
              },
            ),
            ListTile(
              leading: Icon(Icons.score),
              title: Text('Get Score Page'),
              onTap: () {
                Navigator.pushNamed(context, '/get_score');
              },
            ),
            ListTile(
              leading: Icon(Icons.group),
              title: Text('Teams Page'),
              onTap: () {
                Navigator.pushNamed(context, '/teams');
              },
            ),
            ListTile(
              leading: Icon(Icons.logout),
              title: Text('Logout'),
              onTap: () async {
                SharedPreferences prefs = await SharedPreferences.getInstance();
                await prefs.remove('token');
                await prefs.remove('user');
                await prefs.remove('playersRankings');
                Navigator.pushNamedAndRemoveUntil(
                    context, '/login', (Route<dynamic> route) => false);
              },
            ),
          ],
        ),
      ),
      body: WelcomePage(),
    );
  }
}
