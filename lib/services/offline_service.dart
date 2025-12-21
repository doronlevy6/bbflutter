import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../managers/environment_manager.dart';

/// Lightweight offline helper:
/// - Caches GET responses locally (SharedPreferences as JSON string)
/// - Queues write operations (POST/PUT/DELETE) when network fails and retries in background
class OfflineService {
  OfflineService._internal();
  static final OfflineService _instance = OfflineService._internal();
  factory OfflineService() => _instance;

  final EnvironmentManager _envManager = EnvironmentManager();
  Timer? _retryTimer;
  bool _syncInProgress = false;

  static const String _queueKey = 'pending_api_actions_v1';
  static const String _metricsKey = 'pending_api_metrics_v1';

  /// Start periodic retry for queued actions (no-op if already started).
  void ensureBackgroundSync(Future<Map<String, dynamic>> Function(String, String, Map<String, dynamic>?) dispatcher) {
    _retryTimer ??= Timer.periodic(const Duration(seconds: 25), (_) => processQueue(dispatcher));
    // Kick off an immediate attempt
    processQueue(dispatcher);
  }

  /// Get directly from cache (no network). Returns null if not found.
  Future<Map<String, dynamic>?> getFromCacheOnly(String cacheKey) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final cachedString = prefs.getString(cacheKey);
    if (cachedString != null) {
      try {
        final data = jsonDecode(cachedString) as Map<String, dynamic>;
        return {...data, '_cached': true};
      } catch (_) {}
    }
    return null;
  }

  /// GET with cache fallback. Returns the server payload; adds `_cached: true` when falling back.
  Future<Map<String, dynamic>> getWithCache({
    required String endpoint,
    required String cacheKey,
    required Future<Map<String, dynamic>> Function(String, String, Map<String, dynamic>?) dispatcher,
  }) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    Map<String, dynamic>? cached;
    final cachedString = prefs.getString(cacheKey);
    if (cachedString != null) {
      try {
        cached = jsonDecode(cachedString) as Map<String, dynamic>;
      } catch (_) {}
    }

    try {
      final result = await dispatcher('GET', endpoint, null);
      final status = result['statusCode'] as int? ?? 500;
      final data = result['data'];
      if (status >= 200 && status < 300 && data is Map<String, dynamic>) {
        await prefs.setString(cacheKey, jsonEncode(data));
        return {...data, '_cached': false};
      }
      // Non-200: surface payload
      if (data is Map<String, dynamic>) return data;
      return {'success': false, 'message': 'Failed to fetch ($status)'};
    } catch (e) {
      if (cached != null) {
        return {...cached, '_cached': true, '_cache_error': e.toString()};
      }
      rethrow;
    }
  }

  /// Manually inject data into the cache (used for bulk loading).
  Future<void> manuallyCache(String cacheKey, Map<String, dynamic> data) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(cacheKey, jsonEncode(data));
  }

  /// Send write action, queue on connectivity issues. Returns payload; when queued adds `queued: true`.
  Future<Map<String, dynamic>> sendOrQueue({
    required String method,
    required String endpoint,
    Map<String, dynamic>? body,
    required Future<Map<String, dynamic>> Function(String, String, Map<String, dynamic>?) dispatcher,
  }) async {
    try {
      final result = await dispatcher(method, endpoint, body);
      final status = result['statusCode'] as int? ?? 500;
      final data = result['data'];
      if (status >= 200 && status < 300) {
        if (data is Map<String, dynamic>) return data;
        return {'success': true};
      }
      // Server-side error: return as-is (do not queue)
      if (data is Map<String, dynamic>) return data;
      return {'success': false, 'message': 'Request failed ($status)'};
    } catch (e) {
      await _enqueue(method: method, endpoint: endpoint, body: body);
      return {
        'success': true,
        'queued': true,
        'message': 'Saved offline, will sync when online'
      };
    }
  }

  Future<List<dynamic>> _loadQueue() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    return raw != null ? jsonDecode(raw) as List<dynamic> : <dynamic>[];
  }

  Future<void> _saveQueue(List<dynamic> queue, {int lastSynced = 0}) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_queueKey, jsonEncode(queue));
    final metrics = {
      'pending': queue.length,
      'last_synced_count': lastSynced,
      'last_synced_at': lastSynced > 0 ? DateTime.now().toIso8601String() : prefs.getString(_metricsKey) != null ? (jsonDecode(prefs.getString(_metricsKey)!) as Map<String, dynamic>)['last_synced_at'] : null,
    };
    await prefs.setString(_metricsKey, jsonEncode(metrics));
  }

  Future<void> _enqueue({
    required String method,
    required String endpoint,
    Map<String, dynamic>? body,
  }) async {
    final queue = await _loadQueue();
    queue.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'method': method,
      'endpoint': endpoint,
      'body': body,
      'created_at': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
    await _saveQueue(queue);
  }

  /// Try to flush queued actions using the provided dispatcher.
  Future<void> processQueue(Future<Map<String, dynamic>> Function(String, String, Map<String, dynamic>?) dispatcher) async {
    if (_syncInProgress) return;
    _setSyncing(true); // Notify start
    try {
      List<dynamic> queue = await _loadQueue();
      if (queue.isEmpty) return;

      final List<dynamic> remaining = [];
      int synced = 0;

      for (final item in queue) {
        final method = item['method'] as String? ?? 'POST';
        final endpoint = item['endpoint'] as String? ?? '';
        final body = item['body'] as Map<String, dynamic>?;
        try {
          final result = await dispatcher(method, endpoint, body);
          final status = result['statusCode'] as int? ?? 500;
          if (status >= 200 && status < 300) {
            synced += 1;
            continue; // success
          }
          item['attempts'] = (item['attempts'] ?? 0) + 1;
          remaining.add(item);
        } catch (_) {
          item['attempts'] = (item['attempts'] ?? 0) + 1;
          remaining.add(item);
        }
      }

      await _saveQueue(remaining, lastSynced: synced);
    } finally {
      _setSyncing(false); // Notify end
    }
  }

  /// Helper dispatcher used by offline service when invoked directly.
  Future<Map<String, dynamic>> directDispatch(String method, String endpoint, {Map<String, dynamic>? body}) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final uri = Uri.parse('${_envManager.apiUrl}/$endpoint');
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

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
    return {
      'statusCode': response.statusCode,
      'data': decoded,
    };
  }

  /// Expose queue metrics: pending count and last sync info.
  Future<Map<String, dynamic>> getQueueStats() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_metricsKey);
    Map<String, dynamic> metrics = {
      'pending': 0,
      'last_synced_count': 0,
      'last_synced_at': null,
    };
    if (raw != null) {
      try {
        metrics = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    final queue = await _loadQueue();
    metrics['pending'] = queue.length;
    return metrics;
  }
  
  /// Get all pending queue items for display
  Future<List<Map<String, dynamic>>> getQueueItems() async {
    final queue = await _loadQueue();
    return queue.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }
  
  /// Clear a specific item from queue by ID
  Future<void> removeFromQueue(String id) async {
    final queue = await _loadQueue();
    queue.removeWhere((item) => item['id'] == id);
    await _saveQueue(queue);
  }
  
  /// Clear all pending queue items
  Future<void> clearQueue() async {
    await _saveQueue([]);
  }
  
  // New Sync Stream
  final _syncStatusController = StreamController<bool>.broadcast();
  Stream<bool> get isSyncing => _syncStatusController.stream;

  void _setSyncing(bool isSyncing) {
    _syncInProgress = isSyncing;
    _syncStatusController.add(isSyncing);
  }
} // End class

