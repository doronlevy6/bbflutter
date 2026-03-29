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
  static const String _failedQueueKey = 'failed_api_actions_v1';
  static const String _metricsKey = 'pending_api_metrics_v1';
  static const int _maxAttempts = 8;

  /// Start periodic retry for queued actions (no-op if already started).
  void ensureBackgroundSync(
      Future<Map<String, dynamic>> Function(
              String, String, Map<String, dynamic>?)
          dispatcher) {
    _retryTimer ??= Timer.periodic(
        const Duration(seconds: 25), (_) => processQueue(dispatcher));
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
    required Future<Map<String, dynamic>> Function(
            String, String, Map<String, dynamic>?)
        dispatcher,
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
    required Future<Map<String, dynamic>> Function(
            String, String, Map<String, dynamic>?)
        dispatcher,
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
      if (_isRetryableException(e)) {
        await _enqueue(method: method, endpoint: endpoint, body: body);
        return {
          'success': true,
          'queued': true,
          'message': 'Saved offline, will sync when online'
        };
      }
      return {
        'success': false,
        'queued': false,
        'message': _humanError(e),
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
    final existing = await getQueueStats();
    final metrics = {
      'pending': queue.length,
      'failed': existing['failed'] ?? 0,
      'last_synced_count': lastSynced,
      'last_synced_at': lastSynced > 0
          ? DateTime.now().toIso8601String()
          : existing['last_synced_at'],
    };
    await prefs.setString(_metricsKey, jsonEncode(metrics));
  }

  Future<List<dynamic>> _loadFailedQueue() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_failedQueueKey);
    return raw != null ? jsonDecode(raw) as List<dynamic> : <dynamic>[];
  }

  Future<void> _saveFailedQueue(List<dynamic> queue) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_failedQueueKey, jsonEncode(queue));
    final metrics = await getQueueStats();
    await prefs.setString(_metricsKey, jsonEncode(metrics));
  }

  Future<void> _moveToFailed(Map<String, dynamic> item,
      {required String reason}) async {
    final failed = await _loadFailedQueue();
    final failedItem = Map<String, dynamic>.from(item);
    failedItem['failed_at'] = DateTime.now().toIso8601String();
    failedItem['failed_reason'] = reason;
    failed.add(failedItem);
    await _saveFailedQueue(failed);
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
  Future<void> processQueue(
      Future<Map<String, dynamic>> Function(
              String, String, Map<String, dynamic>?)
          dispatcher) async {
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
        final bodyRaw = item['body'];
        final body = bodyRaw is Map<String, dynamic>
            ? bodyRaw
            : bodyRaw is Map
                ? Map<String, dynamic>.from(bodyRaw)
                : null;
        final attempts = (item['attempts'] as num?)?.toInt() ?? 0;

        try {
          final result = await dispatcher(method, endpoint, body);
          final status = result['statusCode'] as int? ?? 500;
          final data = result['data'];
          if (_isTerminalSuccess(
            method: method,
            endpoint: endpoint,
            statusCode: status,
            data: data,
          )) {
            synced += 1;
            continue;
          }
          final nextAttempts = attempts + 1;
          item['attempts'] = nextAttempts;

          if (_isRetryableStatus(status) && nextAttempts < _maxAttempts) {
            remaining.add(item);
          } else {
            await _moveToFailed(
              Map<String, dynamic>.from(item as Map),
              reason: 'HTTP $status',
            );
          }
        } catch (e) {
          final nextAttempts = attempts + 1;
          item['attempts'] = nextAttempts;

          if (_isRetryableException(e) && nextAttempts < _maxAttempts) {
            remaining.add(item);
          } else {
            await _moveToFailed(
              Map<String, dynamic>.from(item as Map),
              reason: _humanError(e),
            );
          }
        }
      }

      await _saveQueue(remaining, lastSynced: synced);
    } finally {
      _setSyncing(false); // Notify end
    }
  }

  /// Helper dispatcher used by offline service when invoked directly.
  Future<Map<String, dynamic>> directDispatch(String method, String endpoint,
      {Map<String, dynamic>? body}) async {
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
      'failed': 0,
      'last_synced_count': 0,
      'last_synced_at': null,
    };
    if (raw != null) {
      try {
        metrics = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    final queue = await _loadQueue();
    final failedQueue = await _loadFailedQueue();
    metrics['pending'] = queue.length;
    metrics['failed'] = failedQueue.length;
    return metrics;
  }

  /// Get all pending queue items for display
  Future<List<Map<String, dynamic>>> getQueueItems() async {
    final queue = await _loadQueue();
    return queue.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> getFailedQueueItems() async {
    final queue = await _loadFailedQueue();
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

  Future<void> clearFailedQueue() async {
    await _saveFailedQueue([]);
  }

  bool _isRetryableStatus(int statusCode) {
    return statusCode == 408 ||
        statusCode == 425 ||
        statusCode == 429 ||
        statusCode >= 500;
  }

  bool _isRetryableException(Object error) {
    if (error is TimeoutException) return true;
    if (error is http.ClientException) return true;
    final message = error.toString().toLowerCase();
    return message.contains('socketexception') ||
        message.contains('connection') ||
        message.contains('network') ||
        message.contains('timed out');
  }

  bool _isTerminalSuccess({
    required String method,
    required String endpoint,
    required int statusCode,
    required dynamic data,
  }) {
    if (statusCode >= 200 && statusCode < 300) return true;

    // Replayed deletes or idempotent conflicts should not stay queued forever.
    final upperMethod = method.toUpperCase();
    if (upperMethod == 'DELETE' && statusCode == 404) {
      if (endpoint.contains('delete-payment') ||
          endpoint.contains('delete-attendance')) {
        return true;
      }
      if (data is Map<String, dynamic> && data['alreadyDeleted'] == true) {
        return true;
      }
    }

    if (statusCode == 409 &&
        data is Map<String, dynamic> &&
        data['duplicate'] == true) {
      return true;
    }

    return false;
  }

  String _humanError(Object error) {
    final message = error.toString();
    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length);
    }
    return message;
  }

  // New Sync Stream
  final _syncStatusController = StreamController<bool>.broadcast();
  Stream<bool> get isSyncing => _syncStatusController.stream;

  void _setSyncing(bool isSyncing) {
    _syncInProgress = isSyncing;
    _syncStatusController.add(isSyncing);
  }
} // End class
