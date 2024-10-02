// lib/main.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Import the pages
import 'login_page.dart';
import 'manager_page.dart';
import 'grade_page.dart';
import 'get_score_page.dart';
import 'teams_page.dart';
import 'home_page.dart'; // Add this import
import 'welcome_page.dart';

Future<void> main() async {
  // Ensure that widget binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from the .env file
  await dotenv.load(fileName: "assets/.env");

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // Root of the application
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BB App',
      theme: ThemeData(
        primarySwatch: Colors.lightGreen,
      ),
      home: AuthCheck(), // Set AuthCheck as the initial screen
      routes: {
        '/login': (context) => LoginPage(),
        '/manager': (context) => ManagementPage(),
        '/grade': (context) => GradePage(),
        '/welcome': (context) => WelcomePage(),
        '/get_score': (context) => GetScorePage(),
        '/teams': (context) => TeamsPage(),
        '/home': (context) => HomePage(), // Add HomePage route
      },
      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (context) => LoginPage(),
      ),
    );
  }
}

class AuthCheck extends StatefulWidget {
  @override
  _AuthCheckState createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> {
  Future<bool> _checkLoginStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    return token != null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _checkLoginStatus(),
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Show loading indicator while checking
          return Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        } else {
          if (snapshot.hasError) {
            // Handle error, possibly navigate to login
            return Scaffold(
              body: Center(
                child: Text('Error: ${snapshot.error}'),
              ),
            );
          } else {
            bool isLoggedIn = snapshot.data ?? false;
            if (isLoggedIn) {
              return HomePage();
            } else {
              return LoginPage();
            }
          }
        }
      },
    );
  }
}
