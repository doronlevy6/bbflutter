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
  // Controllers for input fields
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  // Controllers for Create Team dialog inputs
  final TextEditingController _teamNameController = TextEditingController();
  final TextEditingController _teamPasswordController = TextEditingController();
  final TextEditingController _teamTypeController = TextEditingController();

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
    _teamNameController.dispose();
    _teamPasswordController.dispose();
    _teamTypeController.dispose();
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
        await RankingsService.fetchAndCachePlayerRankingsForUser(username);
        await RankingsService.fetchAndCacheOverallPlayerRankings();

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

  // Handle Create Team Request
  Future<void> _handleCreateTeam() async {
    // Validate if fields are not empty
    if (_teamNameController.text.isEmpty ||
        _teamPasswordController.text.isEmpty ||
        _teamTypeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please fill in all team details.')),
      );
      return;
    }

    // Close the dialog first
    Navigator.of(context).pop();

    // Optionally, show a loading indicator
    setState(() {
      _isLoading = true;
    });
    try {
      final data = await _apiService.post('create-team', {
        'team_name': _teamNameController.text,
        'team_password': _teamPasswordController.text,
        'team_type': _teamTypeController.text,
      });

      if (data['success']) {
        // Notify user of successful team creation
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
      // Clear the team text fields
      _teamNameController.clear();
      _teamPasswordController.clear();
      _teamTypeController.clear();
    }
  }

  // Opens the Create Team dialog
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
                  controller: _teamNameController,
                  decoration: InputDecoration(
                    labelText: 'Team Name',
                    icon: Icon(Icons.group),
                  ),
                ),
                SizedBox(height: 10),
                TextField(
                  controller: _teamPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Team Password',
                    icon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                ),
                SizedBox(height: 10),
                TextField(
                  controller: _teamTypeController,
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
                // Close the dialog without doing anything
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
                // Optional App Logo or Image
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
                        // Username Field
                        TextField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person),
                          ),
                        ),
                        SizedBox(height: 16),
                        // Password Field
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock),
                          ),
                        ),
                        SizedBox(height: 16),
                        // Email Field (only for Registration)
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
                        // Submit Button (Login/Register)
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
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
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
                        // Toggle Button for switching between Login and Register
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
                              color: Colors.green,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        SizedBox(height: 16),
                        // New button to open Create Team dialog
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _openCreateTeamDialog,
                            icon: Icon(Icons.add_circle_outline, color: Colors.green),
                            label: Text(
                              'Create New Team',
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
