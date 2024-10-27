// lib/login_page.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/api_service.dart';
import 'dart:convert';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // Controllers for input fields
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  // State variables
  bool _isRegister = false;
  String _errorMessage = "";
  bool _isLoading = false;
  final ApiService _apiService = ApiService();

  // Cache key for player rankings
  final String _cacheKey = 'playersRankings';

  // Dispose controllers when not needed
  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // Input validation
  bool _validateInputs() {
    if (_usernameController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        (_isRegister && _emailController.text.isEmpty)) {
      setState(() {
        _errorMessage = "Please fill in all required fields.";
      });
      return false;
    }
    // Add more specific validation if needed
    return true;
  }

  // Handle Registration
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
      });

      if (data['success']) {
        // Automatically login after registration
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

  // Handle Login
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

        // Fetch and cache player rankings after successful login
        String username = data['user']['username'];
        await fetchAndCachePlayerRankingsForUser(username);
        await fetchAndCacheOverallPlayerRankings();

        // Navigate to home page
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

  Future<void> fetchAndCachePlayerRankingsForUser(String username) async {
    try {
      // Fetch data from the API
      final data = await _apiService.get('players-rankings/$username');

      if (data['success'] == true) {
        String jsonString = jsonEncode(data['playersRankings']);
        SharedPreferences prefs = await SharedPreferences.getInstance();
        bool isSet = await prefs.setString('playersRankings_$username', jsonString);

        if (isSet) {
          print("Player rankings for $username successfully cached.");
        } else {
          setState(() {
            _errorMessage = 'Failed to cache player rankings for $username.';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Failed to load player rankings for $username.';
        });
      }
    } catch (error) {
      setState(() {
        _errorMessage = 'Error fetching rankings for $username: $error';
      });
    }
  }


  Future<void> fetchAndCacheOverallPlayerRankings() async {
    try {
      // Fetch data from the API
      final data = await _apiService.get('players-rankings');

      if (data['success'] == true) {
        String jsonString = jsonEncode(data['playersRankings']);
        SharedPreferences prefs = await SharedPreferences.getInstance();
        bool isSet = await prefs.setString('overallPlayersRankings', jsonString);

        if (isSet) {
          print("Overall player rankings successfully cached.");
        } else {
          setState(() {
            _errorMessage = 'Failed to cache overall player rankings.';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Failed to load overall player rankings.';
        });
      }
    } catch (error) {
      setState(() {
        _errorMessage = 'Error fetching overall rankings: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/bb3d.png'),
            fit: BoxFit.cover, // Adjust this property as needed (cover, contain, etc.)
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
                // App Logo or Image (Optional)
                // Uncomment and ensure the image exists if you want to display a logo
                // Image.asset(
                //   'assets/images/blogo.png', // Ensure this image exists
                //   height: 100,
                // ),
                SizedBox(height: 20),
                // Title
                Text(
                  _isRegister ? 'Register' : 'Login',
                  style: TextStyle(
                    fontSize: 28,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 20),
                // Form Card
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
                        // Username
                        TextField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person),
                          ),
                        ),
                        SizedBox(height: 16),
                        // Password
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock),
                          ),
                        ),
                        SizedBox(height: 16),
                        // Email (only for registration)
                        if (_isRegister)
                          Column(
                            children: [
                              TextField(
                                controller: _emailController,
                                decoration: InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: Icon(Icons.email),
                                ),
                              ),
                              SizedBox(height: 16),
                            ],
                          ),
                        // Error Message
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
                        // Submit Button
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
                              backgroundColor: Colors.green, // Button background color
                              foregroundColor: Colors.white, // Button text color
                            ),
                            child: _isLoading
                                ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
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
                        // Toggle Button
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isRegister = !_isRegister;
                              _errorMessage = "";
                              _usernameController.clear();
                              _passwordController.clear();
                              _emailController.clear();
                            });
                          },
                          child: Text(
                            _isRegister
                                ? 'Already have an account? Login'
                                : 'Don\'t have an account? Register',
                            style: TextStyle(
                              color: Colors.green, // Adjust color as needed
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
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
