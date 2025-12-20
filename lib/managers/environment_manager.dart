// lib/managers/environment_manager.dart

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import '../enums/environment.dart';

class EnvironmentManager {
  // Singleton pattern
  static final EnvironmentManager _instance = EnvironmentManager._internal();

  factory EnvironmentManager() {
    return _instance;
  }

  EnvironmentManager._internal();

  Environment _currentEnvironment = Environment.LOCAL

  ;
  // Getter for the current environment
  Environment get currentEnvironment => _currentEnvironment;

  // Setter to change the environment
  void setEnvironment(Environment environment) {
    _currentEnvironment = environment;
  }

  // Method to get the current API URL based on the environment
  String get apiUrl {
    // If running on web, always use the production URL or a specific web URL
    if (kIsWeb && kReleaseMode) {
      // Check for build-time injected environment variable first (Vercel/CI support)
      // Usage: flutter build web --dart-define=PROD_API_URL=https://...
      const buildTimeUrl = String.fromEnvironment('PROD_API_URL');
      if (buildTimeUrl.isNotEmpty) {
        return buildTimeUrl;
      }
      
      // In release (deployed) web builds we always use the remote server.
      return dotenv.env['PROD_API_URL'] ?? 'https://renderbbserver.onrender.com';
    }

    switch (_currentEnvironment) {
      case Environment.LOCAL:
        return dotenv.env['LOCAL_API_URL'] ?? 'http://localhost:9090';

      case Environment.DEVICE_LOCAL:
        return dotenv.env['DEVICE_LOCAL_API_URL'] ?? 'http://192.168.1.12:9090';
      case Environment.PROD:
      default:
        // Also check build-time variable for non-web PROD builds if needed
        const buildTimeUrl = String.fromEnvironment('PROD_API_URL');
        if (buildTimeUrl.isNotEmpty) {
          return buildTimeUrl;
        }
        return dotenv.env['PROD_API_URL'] ?? 'https://renderbbserver.onrender.com';
    }
  }
}
