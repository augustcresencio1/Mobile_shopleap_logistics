import 'dart:async';
import 'dart:convert';
import 'api_config.dart';
import 'delivery_upload_diagnostics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'api_exception.dart';

class _CachedResponse {
  final dynamic data;
  final DateTime expiresAt;
  _CachedResponse(this.data, Duration lifetime)
    : expiresAt = DateTime.now().add(lifetime);
}

class _ProgressMultipartRequest extends http.MultipartRequest {
  final void Function(int sent, int total)? onProgress;
  _ProgressMultipartRequest(super.method, super.url, this.onProgress);

  @override
  http.ByteStream finalize() {
    final total = contentLength;
    var sent = 0;
    return http.ByteStream(
      super.finalize().map((chunk) {
        sent += chunk.length;
        onProgress?.call(sent, total);
        return chunk;
      }),
    );
  }
}

/// Iisang pintuan ng lahat ng tawag sa Laravel API.
class ApiClient {
  ApiClient._();

  // Includes /api; service paths start with /courier, /hubs, etc.
  static final baseUrl = ApiConfig.baseUrl;

  // PANSAMANTALA: 60s dahil mabagal pa ang server. Ibaba kapag naayos.
  static const timeout = Duration(seconds: 60);

  // Require a fresh login when moving between deployed and local backends.
  static final _tokenKey = 'auth_token:$baseUrl';
  static const _legacyTokenKey = 'auth_token';
  static const _storage = FlutterSecureStorage();
  static final Map<String, _CachedResponse> _cache = {};
  static final Map<String, Future<dynamic>> _pending = {};
  static String? _knownToken;
  static int _revision = 0;
  static DateTime? _retryAt;
  static final ValueNotifier<int> sessionChanged = ValueNotifier<int>(0);
  static bool get hasSession => _knownToken != null;

  static void _setSession(String? token) {
    if (_knownToken == token) return;
    _knownToken = token;
    _retryAt = null;
    sessionChanged.value++;
  }

  static int get revision => _revision;

  /// Old requests cannot repopulate the cache after a mutation or logout.
  static void invalidateCache({bool keepPending = false}) {
    _revision++;
    _cache.clear();
    if (!keepPending) _pending.clear();
  }

  static String _cacheKey(String path, Map<String, String>? query, bool auth) =>
      '${auth ? _knownToken : 'public'}|${_uri(path, query)}';

  static dynamic cachedGet(String path, {Map<String, String>? query}) {
    if (_knownToken == null) return null;
    return _cache[_cacheKey(path, query, true)]?.data;
  }

  /// Tumataas ang value tuwing 401 (na-clear na ang token).
  /// Pakikinggan ng MainShell para bumalik sa login.
  static final ValueNotifier<int> sessionExpired = ValueNotifier<int>(0);

  // ---------- Token ----------
  static Future<String?> getToken() async {
    final token = await _storage.read(key: _tokenKey);
    if (token != _knownToken) {
      invalidateCache();
      _setSession(token);
    }
    return token;
  }

  static Future<void> saveToken(String token) async {
    invalidateCache();
    await _storage.delete(key: _legacyTokenKey);
    await _storage.write(key: _tokenKey, value: token);
    _setSession(token);
  }

  static Future<void> clearToken() async {
    invalidateCache();
    _setSession(null);
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _legacyTokenKey);
  }

  // ---------- Public methods ----------
  /// Receipts are fetched in memory only. Never follow an authenticated redirect.
  static Future<String> getHtml(String path) async {
    await getToken();
    final session = sessionChanged.value;
    final result = await _send(true, () async {
      final request = http.Request('GET', _uri(path))
        ..followRedirects = false
        ..headers.addAll(await _headers())
        // Laravel should return JSON auth/validation errors; success is HTML.
        ..headers['Accept'] = 'application/json, text/html'
        ..headers['Cache-Control'] = 'no-store';
      final client = http.Client();
      try {
        return await http.Response.fromStream(await client.send(request));
      } finally {
        client.close();
      }
    }, html: true);
    if (session != sessionChanged.value) {
      throw ApiException('Your account changed. Open the receipt again.');
    }
    return result as String;
  }

  static Future<dynamic> get(
    String path, {
    Map<String, String>? query,
    bool auth = true,
    Duration cacheFor = const Duration(seconds: 3),
    bool forceRefresh = false,
  }) async {
    if (auth) await getToken();
    final key = _cacheKey(path, query, auth);
    final cached = _cache[key];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().isBefore(cached.expiresAt)) {
      return cached.data;
    }
    final pending = _pending[key];
    if (pending != null) return pending;
    final revision = _revision;
    final request = _read(
      auth,
      () async => http.get(
        _uri(path, query),
        headers: await _headers(auth: auth, json: true),
      ),
    );
    _pending[key] = request;
    try {
      final data = await request;
      if (_revision == revision && cacheFor > Duration.zero) {
        _cache[key] = _CachedResponse(data, cacheFor);
      }
      return data;
    } finally {
      if (identical(_pending[key], request)) _pending.remove(key);
    }
  }

  /// Retry a transient read once, sharing the retry with concurrent callers.
  /// Writes are never replayed: an upload may already have reached the server.
  static Future<dynamic> _read(
    bool auth,
    Future<http.Response> Function() call,
  ) async {
    final session = sessionChanged.value;
    for (var attempt = 0; ; attempt++) {
      try {
        return await _send(auth, call);
      } on ApiException catch (error) {
        final status = error.statusCode;
        final transient =
            status == null ||
            const [500, 502, 503, 504].contains(status) ||
            (status >= 200 && status < 300);
        if (attempt >= 1 || !transient || session != sessionChanged.value) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (session != sessionChanged.value) rethrow;
      }
    }
  }

  static Future<dynamic> _mutation(
    Future<dynamic> request, {
    bool refreshCache = true,
  }) async {
    final data = await request;
    if (refreshCache) invalidateCache();
    return data;
  }

  static Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
    bool refreshCache = true,
    Duration? requestTimeout,
    int? requiredStatusCode,
  }) => _mutation(
    _send(
      auth,
      () async => http.post(
        _uri(path),
        headers: await _headers(auth: auth, json: true),
        body: jsonEncode(body ?? {}),
      ),
      requestTimeout: requestTimeout,
      requiredStatusCode: requiredStatusCode,
    ),
    refreshCache: refreshCache,
  );

  static Future<dynamic> put(
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
    bool refreshCache = true,
    Duration? requestTimeout,
  }) => _mutation(
    _send(
      auth,
      () async => http.put(
        _uri(path),
        headers: await _headers(auth: auth, json: true),
        body: jsonEncode(body ?? {}),
      ),
      requestTimeout: requestTimeout,
    ),
    refreshCache: refreshCache,
  );

  static Future<dynamic> delete(String path, {bool auth = true}) => _mutation(
    _send(
      auth,
      () async => http.delete(
        _uri(path),
        headers: await _headers(auth: auth, json: true),
      ),
    ),
  );

  static Future<dynamic> postMultipart(
    String path, {
    required Map<String, String> fields,
    List<http.MultipartFile> files = const [],
    bool auth = true,
    void Function(int sent, int total)? onProgress,
    int? requiredStatusCode,
    String? diagnosticOrderNumber,
    Duration? requestTimeout,
  }) => _mutation(
    _send(
      auth,
      () async {
        final req = _ProgressMultipartRequest('POST', _uri(path), onProgress)
          ..headers.addAll(await _headers(auth: auth))
          ..fields.addAll(fields)
          ..files.addAll(files);
        final client = http.Client();
        if (diagnosticOrderNumber != null) {
          DeliveryUploadDiagnostics.record(diagnosticOrderNumber);
        }
        try {
          final response = await (() async => http.Response.fromStream(
            await client.send(req),
          ))().timeout(requestTimeout ?? timeout);
          if (diagnosticOrderNumber != null) {
            DeliveryUploadDiagnostics.record(
              diagnosticOrderNumber,
              statusCode: response.statusCode,
              body: response.body,
            );
          }
          return response;
        } finally {
          client.close();
        }
      },
      requestTimeout: requestTimeout,
      requiredStatusCode: requiredStatusCode,
    ),
  );

  // ---------- Internals ----------
  static Uri _uri(String path, [Map<String, String>? query]) {
    final relative = Uri.parse(path);
    if (relative.hasScheme || relative.hasAuthority || relative.hasFragment) {
      throw ArgumentError(
        'API paths must be relative to the backend base URL.',
      );
    }
    final cleanPath = relative.path.replaceFirst(RegExp(r'^/?(?:api/)+'), '');
    final u = Uri.parse(
      '$baseUrl/${cleanPath.replaceFirst(RegExp(r"^/+"), "")}',
    ).replace(query: relative.hasQuery ? relative.query : null);
    return (query == null || query.isEmpty)
        ? u
        : u.replace(queryParameters: query);
  }

  static Future<Map<String, String>> _headers({
    bool auth = true,
    bool json = false,
  }) async {
    final token = auth ? await getToken() : null;
    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<dynamic> _send(
    bool auth,
    Future<http.Response> Function() call, {
    Duration? requestTimeout,
    int? requiredStatusCode,
    bool html = false,
  }) async {
    if (auth && await getToken() == null) {
      await clearToken();
      sessionExpired.value++;
      throw ApiException('Please sign in again.', 401);
    }
    final session = sessionChanged.value;
    if (auth && _retryAt != null && DateTime.now().isBefore(_retryAt!)) {
      throw ApiException('Too many requests. Please wait before retrying.', 429)
        ..retryAt = _retryAt;
    }
    final http.Response res;
    try {
      res = await call().timeout(requestTimeout ?? timeout);
    } catch (_) {
      throw ApiException('Cannot connect to the server.');
    }
    return _handle(
      res,
      auth && session == sessionChanged.value,
      requiredStatusCode: requiredStatusCode,
      html: html,
    );
  }

  static Future<dynamic> _handle(
    http.Response res,
    bool auth, {
    int? requiredStatusCode,
    bool html = false,
  }) async {
    dynamic body;
    var validJson = true;
    try {
      body = res.body.isEmpty ? {} : jsonDecode(res.body);
    } catch (_) {
      validJson = false;
      body = {};
    }

    if (res.statusCode >= 200 &&
        res.statusCode < 300 &&
        (requiredStatusCode == null || res.statusCode == requiredStatusCode)) {
      if (html) {
        if (!(res.headers['content-type'] ?? '').toLowerCase().startsWith(
          'text/html',
        )) {
          throw ApiException(
            'The server did not return an HTML receipt.',
            res.statusCode,
          );
        }
        return res.body;
      }
      if (!validJson) {
        throw ApiException(
          'The server returned an unexpected response. Please try again.',
          res.statusCode,
        );
      }
      return body;
    }

    final map = body is Map
        ? Map<String, dynamic>.from(body)
        : <String, dynamic>{};
    final errors = map['errors'] is Map
        ? Map<String, dynamic>.from(map['errors'] as Map)
        : null;

    final defaultMessage = switch (res.statusCode) {
      401 => 'Your session has expired. Please sign in again.',
      403 => 'You do not have permission to perform this action.',
      404 => 'The requested resource was not found.',
      422 => 'Please check the information you entered.',
      _ => 'Error (${res.statusCode}).',
    };
    var msg = map['message']?.toString() ?? defaultMessage;
    if (errors != null && errors.isNotEmpty) {
      final all = errors.values
          .expand((v) => v is List ? v : [v])
          .map((e) => e.toString())
          .toList();
      if (all.isNotEmpty) msg = all.join('\n');
    }
    DateTime? retryAt;
    if (res.statusCode == 429) {
      final raw = res.headers['retry-after'];
      final seconds = int.tryParse(raw ?? '');
      DateTime? until;
      if (seconds != null && seconds >= 0) {
        until = DateTime.now().add(Duration(seconds: seconds));
      } else if (raw != null) {
        try {
          until = DateFormat(
            'EEE, dd MMM yyyy HH:mm:ss',
            'en_US',
          ).parseUtc(raw.replaceFirst(RegExp(r' GMT$'), ''));
        } catch (_) {}
      }
      retryAt = until;
      if (auth) {
        _retryAt = until;
      }
      msg = 'Too many requests. Please wait before retrying.';
    }
    if (res.statusCode >= 500) {
      msg = switch (map['code']) {
        'REGISTRATION_EMAIL_UNAVAILABLE' =>
          'Verification email could not be sent. Please try again later.',
        'REGISTRATION_UNAVAILABLE' =>
          'Registration is temporarily unavailable. Please try again later.',
        _ => 'Server problem. Please try again later.',
      };
    }
    if (res.statusCode == 413) {
      msg =
          'The upload request is too large. Reduce the photo size to at most 5 MB and try again.';
    }

    // §7.2: 401 -> burahin ang token, balik sa login
    if (res.statusCode == 401 && auth) {
      await clearToken();
      sessionExpired.value++;
    }

    throw ApiException(
      msg,
      res.statusCode,
      errors,
      (map['status'] ?? map['courier_status'])?.toString(),
      (map['rejection_reason'] ?? map['reason'])?.toString(),
    )..retryAt = retryAt;
  }
}
