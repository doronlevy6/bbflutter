// lib/login_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'dart:convert';
import '../services/rankings_service.dart';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // בקרי טקסט לשדות המשתמש (לכניסה ורישום)
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  // בקרי טקסט עבור פרטי הקבוצה בתהליך הרישום
  // שינינו את _teamIdController ל _teamNameController עבור הכנסת שם הקבוצה
  final TextEditingController _teamNameController = TextEditingController();
  final TextEditingController _teamPasswordController = TextEditingController();

  // בקרי טקסט עבור דיאלוג יצירת קבוצה (Create Team dialog)
  final TextEditingController _createTeamNameController = TextEditingController();
  final TextEditingController _createTeamPasswordController = TextEditingController();
  final TextEditingController _createTeamTypeController = TextEditingController();

  // משתני סטייט
  bool _isRegister = false;
  String _errorMessage = "";
  bool _isLoading = false;
  final ApiService _apiService = ApiService();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    _teamNameController.dispose();
    _teamPasswordController.dispose();
    _createTeamNameController.dispose();
    _createTeamPasswordController.dispose();
    _createTeamTypeController.dispose();
    super.dispose();
  }

  // בדיקת תקינות הקלט - גם בהתחברות וגם ברישום
  bool _validateInputs() {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty ||
        (_isRegister && _emailController.text.isEmpty)) {
      setState(() {
        _errorMessage = "Please fill in all required fields.";
      });
      return false;
    }
    // במצב רישום, יש לבדוק גם את שדות הקבוצה (שם הקבוצה וסיסמת הקבוצה)
    if (_isRegister &&
        (_teamNameController.text.isEmpty || _teamPasswordController.text.isEmpty)) {
      setState(() {
        _errorMessage = "Please fill in team credentials (Team Name & Team Password).";
      });
      return false;
    }
    return true;
  }

  // טיפול ברישום משתמש
  // שליחת הנתונים לאנדפוינט /register עם השדות: username, password, email, teamName ו-teamPassword
  Future<void> _handleRegister() async {
    if (!_validateInputs()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });
    try {
      final data = await _apiService.post('register', {
        'username': _usernameController.text,
        'password': _passwordController.text,
        'email': _emailController.text,
        // במקום teamId כעת נשלח teamName
        'teamName': _teamNameController.text,
        'teamPassword': _teamPasswordController.text,
      });

      if (data['success']) {
        // במקרה של רישום מוצלח, ניתן לבצע התחברות אוטומטית
        await _handleLogin();
      } else {
        setState(() {
          _errorMessage = data['message'] ?? 'Registration failed';
        });
      }
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // טיפול בהתחברות משתמש (כפי שהיה)
  Future<void> _handleLogin() async {
    if (!_validateInputs()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });
    try {
      final data = await _apiService.post('login', {
        'username': _usernameController.text,
        'password': _passwordController.text,
      });

      if (data['success']) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
        await prefs.setString('user', data['user']['username']);

        // שליפת דירוגי שחקנים לאחר התחברות מוצלחת
        String username = data['user']['username'];
        await RankingsService.fetchAndCachePlayerRankingsForUser(username);
        await RankingsService.fetchAndCacheOverallPlayerRankings();
        await RankingsService.getEnlisted();

        // מעבר לדף הבית
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        setState(() {
          _errorMessage = data['message'] ?? 'Login failed';
        });
      }
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // טיפול בדיאלוג יצירת קבוצה
  Future<void> _handleCreateTeam() async {
    if (_createTeamNameController.text.isEmpty ||
        _createTeamPasswordController.text.isEmpty ||
        _createTeamTypeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please fill in all team details.')),
      );
      return;
    }

    Navigator.of(context).pop();
    setState(() {
      _isLoading = true;
    });
    try {
      final data = await _apiService.post('create-team', {
        'team_name': _createTeamNameController.text,
        'team_password': _createTeamPasswordController.text,
        'team_type': _createTeamTypeController.text,
      });

      if (data['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Team created successfully!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Team creation failed')),
        );
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
      _createTeamNameController.clear();
      _createTeamPasswordController.clear();
      _createTeamTypeController.clear();
    }
  }

  // מתודה לפתיחת דיאלוג יצירת קבוצה
  void _openCreateTeamDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Create New Team'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: _createTeamNameController,
                  decoration: InputDecoration(
                    labelText: 'Team Name',
                    icon: Icon(Icons.group),
                  ),
                ),
                SizedBox(height: 10),
                TextField(
                  controller: _createTeamPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Team Password',
                    icon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                ),
                SizedBox(height: 10),
                TextField(
                  controller: _createTeamTypeController,
                  decoration: InputDecoration(
                    labelText: 'Team Type',
                    icon: Icon(Icons.category),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: _handleCreateTeam,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
              child: Text('Create'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/bb3d.png'),
            fit: BoxFit.cover,
          ),
        ),
        width: double.infinity,
        height: double.infinity,
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // כותרת (Login או Register)
                Text(
                  _isRegister ? 'Register' : 'Login',
                  style: TextStyle(
                    fontSize: 28,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 20),
                // כרטיס טופס (Form Card)
                Card(
                  color: Colors.white.withOpacity(0.8),
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  margin: EdgeInsets.symmetric(horizontal: 8),
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // שדה קלט: שם משתמש
                        TextField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person),
                          ),
                        ),
                        SizedBox(height: 16),
                        // שדה קלט: סיסמה
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock),
                          ),
                        ),
                        SizedBox(height: 16),
                        // שדות רישום נוספים שיופיעו במצב Register בלבד
                        if (_isRegister) ...[
                          // שדה קלט: אימייל
                          TextField(
                            controller: _emailController,
                            decoration: InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email),
                            ),
                          ),
                          SizedBox(height: 16),
                          // שדה קלט: שם קבוצה (במקום מזהה קבוצה)
                          TextField(
                            controller: _teamNameController,
                            decoration: InputDecoration(
                              labelText: 'Team Name',
                              prefixIcon: Icon(Icons.info_outline),
                            ),
                          ),
                          SizedBox(height: 16),
                          // שדה קלט: סיסמת קבוצה
                          TextField(
                            controller: _teamPasswordController,
                            decoration: InputDecoration(
                              labelText: 'Team Password',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                            obscureText: true,
                          ),
                          SizedBox(height: 16),
                        ],
                        // הצגת הודעת שגיאה אם קיימת
                        if (_errorMessage.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              _errorMessage,
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        // כפתור לשליחת הטופס (Login או Register)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading
                                ? null
                                : _isRegister
                                ? _handleRegister
                                : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 16.0),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            child: _isLoading
                                ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                strokeWidth: 2.0,
                              ),
                            )
                                : Text(
                              _isRegister ? 'Register' : 'Login',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 8),
                        // כפתור להחלפה בין מצב Login ל- Register
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isRegister = !_isRegister;
                              _errorMessage = "";
                              _usernameController.clear();
                              _passwordController.clear();
                              _emailController.clear();
                              _teamNameController.clear();
                              _teamPasswordController.clear();
                            });
                          },
                          child: Text(
                            _isRegister
                                ? 'Already have an account? Login'
                                : 'Don\'t have an account? Register',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        // כפתור לפתיחת דיאלוג יצירת קבוצה – מופיע תמיד
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _openCreateTeamDialog,
                            icon: Icon(Icons.add_circle_outline, color: Colors.green),
                            label: Text(
                              'Create Team',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
