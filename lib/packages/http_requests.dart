import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/constants.dart';

typedef JsonMap = Map<String, dynamic>;

class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();
  /// Slow shared hosting / first cold DB hit after login: allow extra headroom.
  static const Duration _requestTimeout = Duration(seconds: 45);

  static const _tokenKey = 'auth_token';
  static const _baseUrlKey = 'api_base_url';
  static const _legacyTokenKey = 'auth_token_legacy';
  /// Same as [ApiConstants.baseUrl] after compile-time `API_BASE` (see [ApiConstants.defaultLaravelApiBase]).
  static String get productionBaseUrl =>
      normalizeApiBaseUrl(ApiConstants.baseUrl);

  /// Laravel host only (no `/api` or `/api/v1`). Paths in [ApiConstants] already include `/api/v1/...`.
  static String normalizeApiBaseUrl(String url) {
    var u = url.trim().replaceAll(RegExp(r'/+$'), '');
    while (true) {
      final l = u.toLowerCase();
      if (l.endsWith('/api/v1')) {
        u = u.substring(0, u.length - '/api/v1'.length);
      } else if (l.endsWith('/api')) {
        u = u.substring(0, u.length - '/api'.length);
      } else {
        break;
      }
      u = u.replaceAll(RegExp(r'/+$'), '');
    }
    return u;
  }

  bool _isUnreachableSavedBase(String url) {
    final lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return true;
    }
    // Only treat obvious local/dev loopback hosts as invalid for production builds.
    return lower.contains('127.0.0.1') ||
        lower.contains('localhost') ||
        lower.contains('10.0.2.2');
  }

  /// SmSver1 portal host: serves PHP/HTML, not Laravel `/api/v1/…` (login would 404 as HTML).
  static bool isSmsPortalHostMisusedAsApi(String url) {
    try {
      final host = Uri.parse(url.trim()).host.toLowerCase();
      return host == 'sms.victorialush.co.tz';
    } catch (_) {
      return false;
    }
  }

  String get _defaultBaseUrl => normalizeApiBaseUrl(
        ApiConstants.baseUrl.isNotEmpty
            ? ApiConstants.baseUrl
            : productionBaseUrl,
      );

  Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final fallback = _defaultBaseUrl;
    if (kReleaseMode) {
      final saved = prefs.getString(_baseUrlKey)?.trim();
      if (saved != null &&
          saved.isNotEmpty &&
          !_isUnreachableSavedBase(saved) &&
          !isSmsPortalHostMisusedAsApi(saved)) {
        return normalizeApiBaseUrl(saved);
      }
      await prefs.setString(_baseUrlKey, fallback);
      return fallback;
    }
    final saved = prefs.getString(_baseUrlKey)?.trim();
    if (saved != null && saved.isNotEmpty) {
      if (_isUnreachableSavedBase(saved) ||
          isSmsPortalHostMisusedAsApi(saved)) {
        await prefs.setString(_baseUrlKey, fallback);
        return fallback;
      }
      return normalizeApiBaseUrl(saved);
    }
    await prefs.setString(_baseUrlKey, fallback);
    return fallback;
  }

  /// In **release** builds only: seed the API host from compile-time default when nothing valid is saved.
  /// Does not overwrite a user-set production API URL (logo → PIN → API server).
  Future<void> ensureProductionApiBase() async {
    if (!kReleaseMode) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_baseUrlKey)?.trim();
    if (saved == null ||
        saved.isEmpty ||
        _isUnreachableSavedBase(saved) ||
        isSmsPortalHostMisusedAsApi(saved)) {
      await prefs.setString(_baseUrlKey, _defaultBaseUrl);
    }
  }

  Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = normalizeApiBaseUrl(url);
    if (isSmsPortalHostMisusedAsApi(normalized)) {
      await prefs.setString(_baseUrlKey, _defaultBaseUrl);
      return;
    }
    await prefs.setString(_baseUrlKey, normalized);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final direct = prefs.getString(_tokenKey);
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }
    // One-time migration from older keys / pre–desktop-login storage layout.
    final legacy = prefs.getString(_legacyTokenKey);
    if (legacy != null && legacy.isNotEmpty) {
      await prefs.setString(_tokenKey, legacy);
      await prefs.remove(_legacyTokenKey);
      return legacy;
    }
    return null;
  }

  Future<void> setToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_tokenKey);
      await prefs.remove(_legacyTokenKey);
    } else {
      await prefs.setString(_tokenKey, token);
      await prefs.remove(_legacyTokenKey);
    }
  }

  Future<Uri> uri(String path) async {
    final base = await getBaseUrl();
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  /// GET [ApiConstants.healthPath] at an explicit base URL (no `Authorization`). Use before saving API prefs.
  Future<http.Response> getHealthAtBase(String rawBaseUrl) async {
    final base = normalizeApiBaseUrl(rawBaseUrl.trim());
    if (base.isEmpty ||
        (!base.startsWith('http://') && !base.startsWith('https://'))) {
      throw ArgumentError('Invalid base URL');
    }
    if (isSmsPortalHostMisusedAsApi(base)) {
      throw ArgumentError('SMS portal host cannot be used as the API base');
    }
    final u = Uri.parse('$base${ApiConstants.healthPath}');
    return http
        .get(
          u,
          headers: const {'Accept': 'application/json'},
        )
        .timeout(
          _requestTimeout,
          onTimeout: () => throw _timeout(ApiConstants.healthPath),
        );
  }

  Future<Map<String, String>> _headers({bool jsonBody = false}) async {
    final headers = <String, String>{
      'Accept': 'application/json',
    };
    if (jsonBody) {
      headers['Content-Type'] = 'application/json';
    }
    final token = await getToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<http.Response> postJson(String path, JsonMap body) async {
    final res = await http
        .post(
          await uri(path),
          headers: await _headers(jsonBody: true),
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout, onTimeout: () => throw _timeout(path));
    return res;
  }

  Future<http.Response> putJson(String path, JsonMap body) async {
    final res = await http
        .put(
          await uri(path),
          headers: await _headers(jsonBody: true),
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout, onTimeout: () => throw _timeout(path));
    return res;
  }

  Future<http.Response> postForm(
      String path, Map<String, String> fields) async {
    final res = await http
        .post(
          await uri(path),
          headers: await _headers(jsonBody: false),
          body: fields,
        )
        .timeout(_requestTimeout, onTimeout: () => throw _timeout(path));
    return res;
  }

  Future<http.Response> get(String path, {Map<String, String>? query}) async {
    final u = await uri(path);
    final withQuery =
        query == null || query.isEmpty ? u : u.replace(queryParameters: query);
    return http
        .get(withQuery, headers: await _headers())
        .timeout(_requestTimeout, onTimeout: () => throw _timeout(path));
  }

  Future<http.Response> patchJson(String path, JsonMap body) async {
    final res = await http
        .patch(
          await uri(path),
          headers: await _headers(jsonBody: true),
          body: jsonEncode(body),
        )
        .timeout(_requestTimeout, onTimeout: () => throw _timeout(path));
    return res;
  }

  Future<http.Response> delete(String path) async {
    return http
        .delete(await uri(path), headers: await _headers())
        .timeout(_requestTimeout, onTimeout: () => throw _timeout(path));
  }

  TimeoutException _timeout(String path) {
    return TimeoutException(
      'Request timed out. Check internet/server and try again. Endpoint: $path',
    );
  }

  static Object? decodeBody(http.Response response) {
    final raw = response.body.trim();
    if (raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  /// Laravel standard envelope: `{ success, message, data }`.
  static bool isSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return false;
    }
    final decoded = decodeBody(response);
    // Wrong host / proxy HTML error pages sometimes return 200 with a non-JSON body.
    if (decoded == null || decoded is String) {
      return false;
    }
    if (decoded is Map) {
      final s = decoded['success'];
      if (s is bool) return s;
    }
    return true;
  }

  /// `message` from Laravel `{ success, message, data }` when [isSuccess] is true.
  static String? successMessageFromResponse(http.Response response) {
    if (!isSuccess(response)) return null;
    final decoded = decodeBody(response);
    if (decoded is Map) {
      final msg = decoded['message'];
      if (msg is String && msg.trim().isNotEmpty) return msg.trim();
    }
    return null;
  }

  /// Throws [Exception] when HTTP status is not 2xx or JSON `success` is false (Laravel envelope).
  static void ensureHttpAndEnvelopeSuccess(
    http.Response response, {
    String fallbackPrefix = 'Request failed',
  }) {
    if (!isSuccess(response)) {
      throw Exception(errorMessageFromResponse(
        response,
        fallbackPrefix: fallbackPrefix,
      ));
    }
  }

  static dynamic responseData(http.Response response) {
    final decoded = decodeBody(response);
    if (decoded is Map && decoded['data'] != null) {
      return decoded['data'];
    }
    return decoded;
  }

  /// `Retry-After` header when sent as seconds (typical for Laravel throttle). Web-safe (no `dart:io`).
  static int? parseRetryAfterSeconds(http.Response response) {
    final ra = response.headers['retry-after']?.trim();
    if (ra == null || ra.isEmpty) return null;
    final asInt = int.tryParse(ra);
    if (asInt != null) {
      return asInt.clamp(1, 120);
    }
    return null;
  }

  static String errorMessageFromResponse(
    http.Response response, {
    String fallbackPrefix = 'Request failed',
  }) {
    if (response.statusCode == 429) {
      final decoded = decodeBody(response);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        final direct = map['message'] ?? map['error'];
        if (direct is String && direct.trim().isNotEmpty) {
          return direct.trim();
        }
      }
      final ra = response.headers['retry-after']?.trim();
      if (ra != null && ra.isNotEmpty) {
        return 'Too many requests. Retry after $ra second(s).';
      }
      return 'Too many requests. Wait a minute, then try again.';
    }

    final sc = response.statusCode;
    if (sc == 502 || sc == 503 || sc == 504) {
      final decodedGateway = decodeBody(response);
      if (decodedGateway is Map) {
        final map = Map<String, dynamic>.from(decodedGateway);
        final direct = map['message'] ?? map['error'];
        if (direct is String && direct.trim().isNotEmpty) {
          return direct.trim();
        }
      }
      if (sc == 504) {
        return 'Server timed out. Try again in a moment.';
      }
      if (sc == 502) {
        return 'Bad gateway. The API may be restarting — retry shortly.';
      }
      return 'Service temporarily unavailable. Try again shortly.';
    }

    final decoded = decodeBody(response);
    if (sc >= 200 && sc < 300) {
      if (decoded is String && decoded.trim().isNotEmpty) {
        return 'Wrong API URL or a proxy returned HTML instead of JSON. Tap the logo five times, enter the admin PIN, and set the Laravel API host (not the SMS web portal).';
      }
      if (decoded == null) {
        return 'Empty response from server. Check API base URL.';
      }
    }
    if (sc == 404) {
      if (decoded is String && decoded.isNotEmpty) {
        final t = decoded.trimLeft();
        if (t.startsWith('<!DOCTYPE') ||
            t.startsWith('<html') ||
            t.toLowerCase().contains('not found')) {
          return 'Login API not found (404). The app must use your Laravel JSON host (e.g. ${ApiConstants.defaultLaravelApiBase}), not the SMS portal. Tap the logo five times → admin PIN → API server.';
        }
      }
    }
    if (decoded is String && decoded.isNotEmpty) {
      final t = decoded.trimLeft();
      if (t.startsWith('<!DOCTYPE') || t.startsWith('<html')) {
        return 'Server returned HTML instead of JSON. Use the Laravel API base URL, not sms.victorialush.co.tz. Tap the logo five times → admin PIN → API server.';
      }
      if (t.length > 280) {
        return '$fallbackPrefix (${response.statusCode}): non-JSON response (truncated). Check API base URL.';
      }
      return decoded;
    }
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      final direct = map['message'] ?? map['error'];
      if (direct is String && direct.trim().isNotEmpty) {
        return direct.trim();
      }

      final errors = map['errors'];
      if (errors is List && errors.isNotEmpty) {
        final first = errors.first;
        if (first is String && first.trim().isNotEmpty) return first.trim();
        return first.toString();
      }
      if (errors is Map) {
        for (final value in errors.values) {
          if (value is List && value.isNotEmpty) {
            final first = value.first;
            if (first is String && first.trim().isNotEmpty) return first.trim();
            return first.toString();
          }
          if (value is String && value.trim().isNotEmpty) return value.trim();
        }
      }
    }

    final reason = response.reasonPhrase?.trim();
    if (reason != null && reason.isNotEmpty) {
      return '$fallbackPrefix (${response.statusCode}): $reason';
    }
    return '$fallbackPrefix (${response.statusCode})';
  }
}
