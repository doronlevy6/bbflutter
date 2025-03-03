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
  // משתנה לבחירת שפה: true - עברית, false - אנגלית
  bool _isHebrew = false;

  // בקרי טקסט לשדות המשתמש (כניסה ורישום)
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  // בקרי טקסט עבור פרטי הקבוצה בתהליך הרישום
  final TextEditingController _teamPasswordController = TextEditingController();

  // בקרי טקסט עבור דיאלוג יצירת קבוצה (ללא controller לסוג קבוצה)
  final TextEditingController _createTeamNameController = TextEditingController();
  final TextEditingController _createTeamPasswordController = TextEditingController();
  // הסרנו: final TextEditingController _createTeamTypeController = TextEditingController();

  // משתנה לבחירת סוג קבוצה: "fb" עבור כדורגל, "bb" עבור כדורסל
  String? _selectedTeamType;

  // משתני סטייט נוספים
  bool _isRegister = false;
  String _errorMessage = "";
  bool _isLoading = false;
  final ApiService _apiService = ApiService();

  // מפה של טקסטים בהתאם לשפה
  Map<String, String> get texts => _isHebrew
      ? {
    'titleLogin': 'כניסה',
    'titleRegister': 'רישום',
    'username': 'שם משתמש',
    'password': 'סיסמה',
    'email': 'אימייל',
    'teamName': 'שם קבוצה',
    'teamPassword': 'סיסמת קבוצה',
    'createNewTeam': 'צור קבוצה חדשה',
    'cancel': 'ביטול',
    'create': 'צור',
    'alreadyHaveAccount': 'כבר יש לך חשבון? התחבר',
    'dontHaveAccount': 'אין לך חשבון? הירשם',
    'fillAllFields': 'אנא מלא את כל השדות הנדרשים.',
    'fillTeamCredentials': 'אנא מלא את פרטי הקבוצה (שם קבוצה וסיסמה).',
    'fillTeamType': 'אנא בחר סוג קבוצה.',
    'teamCreatedSuccessfully': 'הקבוצה נוצרה בהצלחה!',
    'teamCreationFailed': 'יצירת הקבוצה נכשלה',
  }
      : {
    'titleLogin': 'Login',
    'titleRegister': 'Register',
    'username': 'Username',
    'password': 'Password',
    'email': 'Email',
    'teamName': 'Team Name',
    'teamPassword': 'Team Password',
    'createNewTeam': 'Create New Team',
    'cancel': 'Cancel',
    'create': 'Create',
    'alreadyHaveAccount': 'Already have an account? Login',
    'dontHaveAccount': 'Don\'t have an account? Register',
    'fillAllFields': 'Please fill in all required fields.',
    'fillTeamCredentials': 'Please fill in team credentials (Team Name & Team Password).',
    'fillTeamType': 'Please select a team type.',
    'teamCreatedSuccessfully': 'Team created successfully!',
    'teamCreationFailed': 'Team creation failed',
  };
  List<String> _teams = [];
  String? _selectedTeam;

  Future<void> _fetchTeams() async {
    try {
      final data = await _apiService.get('teams');
      if (data['success']) {
        setState(() {
          _teams = List<String>.from(data['teams'].map((team) => team['team_name']));
          _teams.sort((a, b) => a.compareTo(b));
          if (_teams.isNotEmpty) {
            _selectedTeam = _teams[0];
          }
        });
      }
    } catch (error) {
      print('Error fetching teams: $error');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadLanguagePreference();
    _fetchTeams();
  }

  // קריאה לבחירת השפה ששמרנו ב-shared preferences
  Future<void> _loadLanguagePreference() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _isHebrew = prefs.getBool('isHebrew') ?? false;
    });
  }

  // עדכון הבחירה ב-shared preferences בעת שינוי
  Future<void> _updateLanguagePreference(bool isHebrew) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isHebrew', isHebrew);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    _teamPasswordController.dispose();
    _createTeamNameController.dispose();
    _createTeamPasswordController.dispose();
    // הסרנו: _createTeamTypeController.dispose();
    super.dispose();
  }

  // בדיקת תקינות הקלט (לכניסה ולרישום)
  bool _validateInputs() {
    if (_usernameController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        (_isRegister && _emailController.text.isEmpty)) {
      setState(() {
        _errorMessage = texts['fillAllFields']!;
      });
      return false;
    }
    if (_isRegister &&
        (_selectedTeam == null ||
            _selectedTeam!.isEmpty ||
            _teamPasswordController.text.isEmpty)) {
      setState(() {
        _errorMessage = texts['fillTeamCredentials']!;
      });
      return false;
    }
    return true;
  }

  // טיפול ברישום משתמש
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
        'teamName': _selectedTeam,
        'teamPassword': _teamPasswordController.text,
      });

      if (data['success']) {
        await _handleLogin();
      } else {
        setState(() {
          _errorMessage = data['message'] ?? texts['teamCreationFailed']!;
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

  // טיפול בהתחברות משתמש
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

        String username = data['user']['username'];
        await RankingsService.fetchAndCachePlayerRankingsForUser(username);
        await RankingsService.fetchAndCacheOverallPlayerRankings();
        await RankingsService.getEnlisted();

        Navigator.pushReplacementNamed(context, '/home');
      } else {
        setState(() {
          _errorMessage = data['message'] ?? texts['teamCreationFailed']!;
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

  // טיפול בדיאלוג יצירת קבוצה עם בחירת סוג קבוצה באמצעות כפתורים
  Future<void> _handleCreateTeam() async {
    if (_createTeamNameController.text.isEmpty ||
        _createTeamPasswordController.text.isEmpty ||
        _selectedTeamType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(texts['fillAllFields']!)),
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
        'team_type': _selectedTeamType, // "fb" עבור כדורגל, "bb" עבור כדורסל
      });

      if (data['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(texts['teamCreatedSuccessfully']!)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? texts['teamCreationFailed']!)),
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
      _selectedTeamType = null;
    }
  }

  // מתודה לפתיחת דיאלוג יצירת קבוצה עם בחירת סוג קבוצה באמצעות כפתורים
  void _openCreateTeamDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        // עטיפת הדיאלוג ב-StatefulBuilder כדי לאפשר עדכון מיידי של הבחירה בתוך הדיאלוג
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Center(
                child: Text(
                  texts['createNewTeam']!,
                  textAlign: TextAlign.center,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: _createTeamNameController,
                      decoration: InputDecoration(
                        labelText: texts['teamName'],
                        icon: Icon(Icons.group),
                      ),
                    ),
                    SizedBox(height: 10),
                    TextField(
                      controller: _createTeamPasswordController,
                      decoration: InputDecoration(
                        labelText: texts['teamPassword'],
                        icon: Icon(Icons.lock),
                      ),
                      obscureText: true,
                    ),
                    SizedBox(height: 10),
                    Text(
                      _isHebrew ? ":בחר סוג קבוצה" : "Select Team Type:",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center, // מרכז את הכפתורים
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            setStateDialog(() {
                              _selectedTeamType = "fb";
                            });
                          },
                          child: Text(
                            _isHebrew ? "⚽ כדורגל" : "Soccer ⚽",
                            style: TextStyle(fontSize: 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                            backgroundColor: _selectedTeamType == "fb" ? Colors.green : Colors.grey,
                          ),
                        ),
                        SizedBox(width: 5),
                        ElevatedButton(
                          onPressed: () {
                            setStateDialog(() {
                              _selectedTeamType = "bb";
                            });
                          },
                          child: Text(
                            _isHebrew ? "🏀 כדורסל" : "Basketball 🏀",
                            style: TextStyle(fontSize: 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                            backgroundColor: _selectedTeamType == "bb" ? Colors.green : Colors.grey,
                          ),
                        ),
                      ],
                    )
,
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(texts['cancel']!, style: TextStyle(color: Colors.red)),
                ),
                ElevatedButton(
                  onPressed: _handleCreateTeam,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: Text(texts['create']!),
                ),
              ],
            );
          },
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
                // כותרת (Login או Register) בהתאם לשפה ובמצב הרישום
                Text(
                  _isRegister ? texts['titleRegister']! : texts['titleLogin']!,
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
                        TextField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: texts['username'],
                            prefixIcon: Icon(Icons.person),
                          ),
                        ),
                        SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: texts['password'],
                            prefixIcon: Icon(Icons.lock),
                          ),
                        ),
                        SizedBox(height: 16),
                        if (_isRegister) ...[
                          TextField(
                            controller: _emailController,
                            decoration: InputDecoration(
                              labelText: texts['email'],
                              prefixIcon: Icon(Icons.email),
                            ),
                          ),
                          SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            value: _selectedTeam,
                            decoration: InputDecoration(
                              labelText: texts['teamName'],
                              prefixIcon: Icon(Icons.info_outline),
                            ),
                            items: _teams.map((team) {
                              return DropdownMenuItem(
                                value: team,
                                child: Text(team),
                              );
                            }).toList(),
                            onChanged: (newValue) {
                              setState(() {
                                _selectedTeam = newValue;
                              });
                            },
                          ),
                          SizedBox(height: 16),
                          TextField(
                            controller: _teamPasswordController,
                            decoration: InputDecoration(
                              labelText: texts['teamPassword'],
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                            obscureText: true,
                          ),
                          SizedBox(height: 16),
                        ],
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
                              _isRegister ? texts['titleRegister']! : texts['titleLogin']!,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isRegister = !_isRegister;
                              _errorMessage = "";
                              _usernameController.clear();
                              _passwordController.clear();
                              _emailController.clear();
                              _selectedTeam = _teams.isNotEmpty ? _teams[0] : null;
                              _teamPasswordController.clear();
                            });
                          },
                          child: Text(
                            _isRegister
                                ? texts['alreadyHaveAccount']!
                                : texts['dontHaveAccount']!,
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text('English',
                                    style: TextStyle(
                                        color: Colors.green, fontWeight: FontWeight.bold)),
                                Switch(
                                  value: _isHebrew,
                                  onChanged: (value) {
                                    setState(() {
                                      _isHebrew = value;
                                    });
                                    _updateLanguagePreference(value);
                                  },
                                  activeColor: Colors.green,
                                ),
                                Text('עברית',
                                    style: TextStyle(
                                        color: Colors.green, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            TextButton.icon(
                              onPressed: _openCreateTeamDialog,
                              icon: Icon(Icons.add_circle_outline, color: Colors.green),
                              label: Text(
                                texts['createNewTeam']!,
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
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
