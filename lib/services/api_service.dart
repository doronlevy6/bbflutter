// lib/services/api_service.dart

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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

  bool _isAuthEndpoint(String endpoint) {
    return endpoint == 'login' ||
        endpoint == 'register' ||
        endpoint == 'create-team' ||
        endpoint == 'teams' ||
        endpoint == 'refresh-token' ||
        endpoint == 'logout';
  }

  Future<Map<String, dynamic>> _dispatchRaw(
    String method,
    String endpoint,
    Map<String, dynamic>? body, {
    bool includeAuth = true,
  }) async {
    final isPaymentEndpoint =
        endpoint.contains('add-payment') || endpoint.contains('delete-payment');
    if (isPaymentEndpoint) {
      debugPrint(
          '[api:$method] -> $endpoint body=$body includeAuth=$includeAuth');
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');
    final headers = {
      'Content-Type': 'application/json',
      if (includeAuth && token != null) 'Authorization': 'Bearer $token',
    };

    final uri = Uri.parse('$apiUrl/$endpoint');
    http.Response response;
    switch (method.toUpperCase()) {
      case 'PUT':
        response =
            await http.put(uri, headers: headers, body: jsonEncode(body ?? {}));
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: headers);
        break;
      case 'POST':
        response = await http.post(uri,
            headers: headers, body: jsonEncode(body ?? {}));
        break;
      default:
        response = await http.get(uri, headers: headers);
    }

    final decoded = response.body.isNotEmpty ? jsonDecode(response.body) : {};
    if (isPaymentEndpoint) {
      debugPrint(
        '[api:$method] <- $endpoint status=${response.statusCode} body=$decoded',
      );
    }
    return {'statusCode': response.statusCode, 'data': decoded};
  }

  Future<bool> _tryRefreshSession() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refresh_token');
      if (refreshToken == null || refreshToken.isEmpty) {
        return false;
      }

      final refreshRes = await _dispatchRaw(
        'POST',
        'refresh-token',
        {'refresh_token': refreshToken},
        includeAuth: false,
      );

      final status = refreshRes['statusCode'] as int? ?? 500;
      final data = refreshRes['data'];
      if (status != 200 || data is! Map<String, dynamic>) {
        return false;
      }
      if (data['success'] != true || data['token'] == null) {
        return false;
      }

      await prefs.setString('token', data['token'] as String);
      if (data['token_expires_in'] is String) {
        await prefs.setString('token_expires_in', data['token_expires_in']);
      }
      final newRefreshToken = data['refresh_token'];
      if (newRefreshToken is String && newRefreshToken.isNotEmpty) {
        await prefs.setString('refresh_token', newRefreshToken);
      }
      if (data['refresh_token_expires_in'] is String) {
        await prefs.setString(
            'refresh_token_expires_in', data['refresh_token_expires_in']);
      }

      final user = data['user'];
      if (user is Map<String, dynamic>) {
        if (user['username'] is String) {
          await prefs.setString('user', user['username']);
        }
        if (user['email'] is String) {
          await prefs.setString('email', user['email']);
        }
        if (user['team_id'] is int) {
          await prefs.setInt('team_id', user['team_id']);
        }
        if (user['team_type'] is String) {
          await prefs.setString('team_type', user['team_type']);
        }
      }
      if (data['is_admin'] is bool) {
        await prefs.setBool('is_admin', data['is_admin']);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _dispatch(
    String method,
    String endpoint,
    Map<String, dynamic>? body,
  ) async {
    final firstTry = await _dispatchRaw(method, endpoint, body);
    final status = firstTry['statusCode'] as int? ?? 500;
    if (status == 401 && !_isAuthEndpoint(endpoint)) {
      final refreshed = await _tryRefreshSession();
      if (refreshed) {
        return _dispatchRaw(method, endpoint, body);
      }
    }
    return firstTry;
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
          'message': (responseData is Map<String, dynamic>)
              ? (responseData['message'] ?? 'Unknown error occurred')
              : 'Unknown error occurred',
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
          'message': (responseData is Map<String, dynamic>)
              ? (responseData['message'] ?? 'Unknown error occurred')
              : 'Unknown error occurred',
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
          'message': (responseData is Map<String, dynamic>)
              ? (responseData['message'] ?? 'Unknown error occurred')
              : 'Unknown error occurred',
        };
      }
    } catch (error) {
      throw Exception('DELETE request error: $error');
    }
  }

  /// GET with offline cache fallback
  Future<Map<String, dynamic>> getWithCache(String endpoint,
      {required String cacheKey}) async {
    return _offline.getWithCache(
      endpoint: endpoint,
      cacheKey: cacheKey,
      dispatcher: _dispatch,
    );
  }

  Future<Map<String, dynamic>?> getFromCacheOnly(String cacheKey) async {
    return _offline.getFromCacheOnly(cacheKey);
  }

  Future<void> upsertCache(String cacheKey, Map<String, dynamic> data) async {
    await _offline.manuallyCache(cacheKey, data);
  }

  Future<void> clearCache(String cacheKey) async {
    await _offline.removeCache(cacheKey);
  }

  /// Offline-capable write operations
  Future<Map<String, dynamic>> postQueued(
      String endpoint, Map<String, dynamic> data) async {
    return _offline.sendOrQueue(
        method: 'POST', endpoint: endpoint, body: data, dispatcher: _dispatch);
  }

  Future<Map<String, dynamic>> putQueued(
      String endpoint, Map<String, dynamic> data) async {
    return _offline.sendOrQueue(
        method: 'PUT', endpoint: endpoint, body: data, dispatcher: _dispatch);
  }

  Future<Map<String, dynamic>> deleteQueued(String endpoint) async {
    return _offline.sendOrQueue(
        method: 'DELETE', endpoint: endpoint, dispatcher: _dispatch);
  }

  Future<void> processQueue() async {
    await _offline.processQueue(_dispatch);
  }

  Future<Map<String, dynamic>> getQueueStats() async {
    return _offline.getQueueStats();
  }

  Future<List<Map<String, dynamic>>> getQueueItems() async {
    return _offline.getQueueItems();
  }

  Future<List<Map<String, dynamic>>> getFailedQueueItems() async {
    return _offline.getFailedQueueItems();
  }

  Future<void> removeFromQueue(String id) async {
    await _offline.removeFromQueue(id);
  }

  Future<void> clearQueue() async {
    await _offline.clearQueue();
  }

  Future<void> clearFailedQueue() async {
    await _offline.clearFailedQueue();
  }

  Future<void> clearUserScopedLocalState() async {
    await _offline.clearUserScopedState();
  }

  Future<bool> ensureSession() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null && token.isNotEmpty) return true;
    return _tryRefreshSession();
  }

  Future<void> logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refresh_token');
    if (refreshToken == null || refreshToken.isEmpty) return;

    try {
      await _dispatchRaw(
        'POST',
        'logout',
        {'refresh_token': refreshToken},
        includeAuth: false,
      );
    } catch (_) {
      // Best effort only.
    }
  }

  Future<Map<String, dynamic>> updateMyEmail(String email) async {
    try {
      final response = await put('update-my-email', {'email': email.trim()});
      final parsed = response is Map<String, dynamic>
          ? response
          : <String, dynamic>{
              'success': false,
              'message': 'Unexpected response'
            };

      if (parsed['success'] == true) {
        final user = parsed['user'];
        final updatedEmail = user is Map<String, dynamic>
            ? (user['email']?.toString() ?? email.trim())
            : email.trim();
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('email', updatedEmail);
      }

      return parsed;
    } catch (error) {
      return {
        'success': false,
        'message': 'Failed to update email: $error',
      };
    }
  }

  Future<void> _setPreloadStatus(String status) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preloadStatusKey, status);
    await prefs.setString(
        _preloadUpdatedAtKey, DateTime.now().toIso8601String());
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

  Future<bool> _safePreloadStep(Future<void> Function() step) async {
    try {
      await step();
      return true;
    } catch (e) {
      print('Preload step failed: $e');
      return false;
    }
  }

  /// Preload data for offline use (non-blocking from caller).
  /// - Players: preload their own finance data.
  /// - Admins: preload team summary and all players history in bulk.
  Future<void> preloadAll({
    required String username,
    int? teamId,
    bool isAdmin = false,
  }) async {
    await _setPreloadStatus('in_progress');
    int successSteps = 0;

    if (isAdmin && teamId != null) {
      final loadedTeamSummary = await _safePreloadStep(() async {
        await getWithCache(
          'finance/team-financial-summary/$teamId',
          cacheKey: 'cache_team_summary_$teamId',
        );
      });
      if (loadedTeamSummary) successSteps += 1;

      final loadedTeamHistory = await _safePreloadStep(() async {
        final bulkData = await get('finance/all-players-history/$teamId');
        if (bulkData != null &&
            bulkData['success'] == true &&
            bulkData['allPlayersData'] is Map) {
          final allMap = Map<String, dynamic>.from(
            bulkData['allPlayersData'] as Map,
          );
          for (final pName in allMap.keys) {
            final pData = allMap[pName];
            if (pData is Map<String, dynamic>) {
              await _offline.manuallyCache(
                  'cache_player_financials_$pName', pData);
            } else if (pData is Map) {
              await _offline.manuallyCache(
                'cache_player_financials_$pName',
                Map<String, dynamic>.from(pData),
              );
            }
          }
        }
      });
      if (loadedTeamHistory) successSteps += 1;
    }

    final loadedPlayers = await _safePreloadStep(() async {
      final playersCacheKey =
          teamId == null ? 'cache_players' : 'cache_players_team_$teamId';
      await getWithCache('players', cacheKey: playersCacheKey);
    });
    if (loadedPlayers) successSteps += 1;

    final loadedBalance = await _safePreloadStep(() async {
      await getWithCache(
        'finance/player-balance/$username',
        cacheKey: 'cache_player_balance_$username',
      );
    });
    if (loadedBalance) successSteps += 1;

    final loadedPersonalFinancials = await _safePreloadStep(() async {
      await getWithCache(
        'finance/player-financials/$username',
        cacheKey: 'cache_player_financials_$username',
      );
    });
    if (loadedPersonalFinancials) successSteps += 1;

    if (successSteps > 0) {
      await _setPreloadStatus('ready');
    } else {
      await _setPreloadStatus('failed');
    }
  }

  /// Preload frequently used financial data in the background (after login).
  Future<void> preloadFinancialData({
    required String username,
    int? teamId,
    bool isAdmin = false,
  }) async {
    await preloadAll(username: username, teamId: teamId, isAdmin: isAdmin);
  }
}
