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

  // Fallback only. Workspace tasks pass APP_ENV explicitly at runtime.
  Environment _currentEnvironment = Environment.PROD;
  // Getter for the effective environment currently in use.
  // Priority:
  // 1) APP_ENV build define
  // 2) Web release fallback (PROD)
  // 3) Runtime in-app selection fallback
  Environment get currentEnvironment {
    final definedEnv = _environmentFromBuildDefine();
    if (definedEnv != null) return definedEnv;

    if (kIsWeb && kReleaseMode) {
      return Environment.PROD;
    }

    return _currentEnvironment;
  }

  // Setter to change the environment
  void setEnvironment(Environment environment) {
    _currentEnvironment = environment;
  }

  Environment? _environmentFromBuildDefine() {
    const appEnv = String.fromEnvironment('APP_ENV', defaultValue: '');
    switch (appEnv.toUpperCase()) {
      case 'LOCAL':
        return Environment.LOCAL;
      case 'DEVICE_LOCAL':
        return Environment.DEVICE_LOCAL;
      case 'PROD':
        return Environment.PROD;
      default:
        return null;
    }
  }

  String _urlForEnvironment(Environment environment) {
    switch (environment) {
      case Environment.LOCAL:
        return dotenv.env['LOCAL_API_URL'] ?? 'http://localhost:9090';
      case Environment.DEVICE_LOCAL:
        return dotenv.env['DEVICE_LOCAL_API_URL'] ?? 'http://192.168.1.12:9090';
      case Environment.PROD:
        const prodBuildTime = String.fromEnvironment('PROD_API_URL');
        if (prodBuildTime.isNotEmpty) return prodBuildTime;
        return dotenv.env['PROD_API_URL'] ??
            'https://renderbbserver.onrender.com';
    }
  }

  // Method to get the current API URL based on the environment.
  // Priority:
  // 1) API_BASE_URL dart-define direct override
  // 2) APP_ENV dart-define (LOCAL / DEVICE_LOCAL / PROD)
  // 3) Existing runtime behavior fallback
  String get apiUrl {
    const directOverride = String.fromEnvironment('API_BASE_URL');
    if (directOverride.isNotEmpty) {
      return directOverride;
    }

    // In release web builds we still allow PROD_API_URL override for CI/deploy pipelines.
    if (kIsWeb && kReleaseMode && currentEnvironment == Environment.PROD) {
      const buildTimeUrl = String.fromEnvironment('PROD_API_URL');
      if (buildTimeUrl.isNotEmpty) {
        return buildTimeUrl;
      }
    }

    return _urlForEnvironment(currentEnvironment);
  }
}
