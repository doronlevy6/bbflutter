import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';

// Import the pages
import 'pages/login_page.dart';
import 'pages/manager_page.dart';
import 'pages/grade_page.dart';
// import 'pages/get_score_page.dart';
import 'pages/playgound_page.dart';
import 'pages/home_page.dart';
import 'pages/welcome_page.dart';

Future<void> main() async {
  // Ensure that widget binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from the .env file
  await dotenv.load(fileName: "assets/.env");

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final kColorScheme = ColorScheme.fromSeed(
    seedColor: Colors.green, // RGB values for light green
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BB App',
      theme: ThemeData(
        colorScheme: kColorScheme,
        textTheme: GoogleFonts.poppinsTextTheme(
          Theme.of(context).textTheme,
        ),
        scaffoldBackgroundColor: Colors.grey[50],
        appBarTheme: AppBarTheme(
          backgroundColor: kColorScheme.primary,
          elevation: 0,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kColorScheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey[200],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: AuthCheck(),
      routes: {
        '/login': (context) => LoginPage(),
        '/manager': (context) => ManagementPage(),
        '/grade': (context) => GradePage(),
        '/welcome': (context) => WelcomePage(),
        // '/get_score': (context) => GetScorePage(),
        '/teams': (context) => PlayGround(),
        '/home': (context) => HomePage(),
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
