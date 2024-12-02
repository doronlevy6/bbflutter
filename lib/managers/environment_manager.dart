// lib/managers/environment_manager.dart

import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../enums/environment.dart';

class EnvironmentManager {
  // Singleton pattern
  static final EnvironmentManager _instance = EnvironmentManager._internal();

  factory EnvironmentManager() {
    return _instance;
  }

  EnvironmentManager._internal();

  Environment _currentEnvironment = Environment.PROD;

  // Getter for the current environment
  Environment get currentEnvironment => _currentEnvironment;

  // Setter to change the environment
  void setEnvironment(Environment environment) {
    _currentEnvironment = environment;
  }

  // Method to get the current API URL based on the environment
  String get apiUrl {
    String url;
    switch (_currentEnvironment) {
      case Environment.LOCAL:
        return dotenv.env['LOCAL_API_URL'] ?? 'http://localhost:9090';
      case Environment.DEVICE_LOCAL:
        return dotenv.env['DEVICE_LOCAL_API_URL'] ?? 'http://192.168.1.10:9090';
      case Environment.PROD:
      default:
        return dotenv.env['PROD_API_URL'] ?? 'https://renderbbserver.onrender.com';
    }
  }
}
