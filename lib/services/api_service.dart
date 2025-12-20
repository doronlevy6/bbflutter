// lib/services/api_service.dart

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../managers/environment_manager.dart';
import 'offline_service.dart';

class ApiService {
  // Reference to the EnvironmentManager
  final EnvironmentManager _envManager = EnvironmentManager();
  final OfflineService _offline = OfflineService();

  // Getter for the current API URL
  String get apiUrl => _envManager.apiUrl;
  
  // Expose sync status
  Stream<bool> get isSyncing => _offline.isSyncing;

  ApiService() {
    // Start background sync for any pending queued actions
    _offline.ensureBackgroundSync(_dispatch);
  }

  // Cache preload status keys
  static const String _preloadStatusKey = 'cache_preload_status_v1';
  static const String _preloadUpdatedAtKey = 'cache_preload_updated_at_v1';

  Future<Map<String, dynamic>> _dispatch(String method, String endpoint, Map<String, dynamic>? body) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final uri = Uri.parse('$apiUrl/$endpoint');
    http.Response response;
    switch (method.toUpperCase()) {
      case 'PUT':
        response = await http.put(uri, headers: headers, body: jsonEncode(body ?? {}));
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: headers);
        break;
      case 'POST':
        response = await http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
        break;
      default:
        response = await http.get(uri, headers: headers);
    }

    final decoded = response.body.isNotEmpty ? jsonDecode(response.body) : {};
    return {'statusCode': response.statusCode, 'data': decoded};
  }

  // Generic GET request
  Future<dynamic> get(String endpoint) async {
    try {
      final res = await _dispatch('GET', endpoint, null);
      if (res['statusCode'] == 200) {
        return res['data'];
      }
      throw Exception('Failed to fetch data: ${res['statusCode']}');
    } catch (error) {
      throw Exception('GET request error: $error');
    }
  }

  // Generic POST request
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    try {
      final res = await _dispatch('POST', endpoint, data);
      final responseData = res['data'];
      final status = res['statusCode'] as int? ?? 500;

      if (status == 200 || status == 201) {
        return responseData;
      } else {
        return {
          'success': false,
          'message': (responseData is Map<String, dynamic>) ? (responseData['message'] ?? 'Unknown error occurred') : 'Unknown error occurred',
        };
      }
    } catch (error) {
      throw Exception('POST request error: $error');
    }
  }

  // Generic PUT request
  Future<dynamic> put(String endpoint, Map<String, dynamic> data) async {
    try {
      final res = await _dispatch('PUT', endpoint, data);
      final responseData = res['data'];
      final status = res['statusCode'] as int? ?? 500;

      if (status == 200) {
        return responseData;
      } else {
        return {
          'success': false,
          'message': (responseData is Map<String, dynamic>) ? (responseData['message'] ?? 'Unknown error occurred') : 'Unknown error occurred',
        };
      }
    } catch (error) {
      throw Exception('PUT request error: $error');
    }
  }

  // Generic DELETE request
  Future<dynamic> delete(String endpoint) async {
    try {
      final res = await _dispatch('DELETE', endpoint, null);
      final responseData = res['data'];
      final status = res['statusCode'] as int? ?? 500;

      if (status == 200) {
        return responseData;
      } else {
        return {
          'success': false,
          'message': (responseData is Map<String, dynamic>) ? (responseData['message'] ?? 'Unknown error occurred') : 'Unknown error occurred',
        };
      }
    } catch (error) {
      throw Exception('DELETE request error: $error');
    }
  }

  /// GET with offline cache fallback
  Future<Map<String, dynamic>> getWithCache(String endpoint, {required String cacheKey}) async {
    return _offline.getWithCache(
      endpoint: endpoint,
      cacheKey: cacheKey,
      dispatcher: _dispatch,
    );
  }

  /// Offline-capable write operations
  Future<Map<String, dynamic>> postQueued(String endpoint, Map<String, dynamic> data) async {
    return _offline.sendOrQueue(method: 'POST', endpoint: endpoint, body: data, dispatcher: _dispatch);
  }

  Future<Map<String, dynamic>> putQueued(String endpoint, Map<String, dynamic> data) async {
    return _offline.sendOrQueue(method: 'PUT', endpoint: endpoint, body: data, dispatcher: _dispatch);
  }

  Future<Map<String, dynamic>> deleteQueued(String endpoint) async {
    return _offline.sendOrQueue(method: 'DELETE', endpoint: endpoint, dispatcher: _dispatch);
  }

  Future<void> processQueue() async {
    await _offline.processQueue(_dispatch);
  }

  Future<Map<String, dynamic>> getQueueStats() async {
    return _offline.getQueueStats();
  }

  Future<void> _setPreloadStatus(String status) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preloadStatusKey, status);
    await prefs.setString(_preloadUpdatedAtKey, DateTime.now().toIso8601String());
  }

  Future<Map<String, dynamic>> getPreloadStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final status = prefs.getString(_preloadStatusKey) ?? 'idle';
    final updatedAt = prefs.getString(_preloadUpdatedAtKey);
    return {
      'status': status,
      'updatedAt': updatedAt,
    };
  }

  /// Preload everything we need for offline use (non-blocking).
  Future<void> preloadAll({required String username, required int teamId}) async {
    await _setPreloadStatus('in_progress');
    try {
      // 1. Fetch Team Summary (includes list of all players)
      await getWithCache('finance/team-financial-summary/$teamId', cacheKey: 'cache_team_summary_$teamId');
      
      // 2. NEW: Fetch FULL History for ALL players in ONE request
      // This is the "Heavy" lift, but done once.
      try {
        final bulkData = await get('finance/all-players-history/$teamId');
        if (bulkData != null && bulkData['success'] == true && bulkData['allPlayersData'] is Map) {
          final Map<String, dynamic> allMap = bulkData['allPlayersData'];
          // Cache each player's data individually so the UI can find it later
          for (final pName in allMap.keys) {
            final pData = allMap[pName];
            if (pData != null) {
              await _offline.manuallyCache('cache_player_financials_$pName', pData);
            }
          }
        }
      } catch (e) {
        print('Bulk preload failed: $e');
        // Fallback or just ignore (partial cache is better than none)
      }

      await getWithCache('players', cacheKey: 'cache_players');
      await getWithCache('finance/player-balance/$username', cacheKey: 'cache_player_balance_$username');

      await _setPreloadStatus('ready');
    } catch (_) {
      await _setPreloadStatus('failed');
    }
  }

  /// Preload frequently used financial data in the background (after login).
  Future<void> preloadFinancialData({required String username, required int teamId}) async {
      await preloadAll(username: username, teamId: teamId);
  }
}
