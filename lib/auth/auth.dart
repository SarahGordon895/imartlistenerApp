import 'dart:async';

import 'package:http/http.dart' as http;

import '../packages/http_requests.dart';
import '../shared/constants.dart';

class AuthService {
  AuthService(this._api);

  final ApiClient _api;

  String? _extractToken(dynamic decoded) {
    if (decoded is List && decoded.isNotEmpty) {
      return _extractToken(decoded.first);
    }
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    for (final key in ['token', 'access_token', 'jwt']) {
      final v = map[key];
      if (v is String && v.isNotEmpty) return v;
    }
    final data = map['data'];
    if (data is Map) {
      final dm = Map<String, dynamic>.from(data);
      for (final key in ['token', 'access_token', 'jwt']) {
        final v = dm[key];
        if (v is String && v.isNotEmpty) return v;
      }
    }
    return null;
  }

  bool _ok(http.Response res) => res.statusCode >= 200 && res.statusCode < 300;

  /// Same credentials as SMSver1 portal (`users` table via Laravel).
  Future<String> login({required String login, required String password}) async {
    http.Response res;
    try {
      // Laravel accepts `user_id` (portal field name) or `login` / `username` / `email` aliases.
      res = await _api.postJson(ApiConstants.loginPath, {
        'user_id': login,
        'login': login,
        'password': password,
      });
      if (!_ok(res) && res.statusCode != 429) {
        res = await _api.postForm(ApiConstants.loginPath, {
          'user_id': login,
          'login': login,
          'password': password,
        });
      }
    } on TimeoutException {
      throw AuthException(
        'Login request timed out. Check server/network and try again.',
      );
    } on http.ClientException {
      throw AuthException(
        'Unable to reach auth server. Verify portal URL and backend status.',
      );
    } catch (e) {
      throw AuthException('Login failed: $e');
    }

    if (!_ok(res)) {
      throw AuthException(ApiClient.errorMessageFromResponse(res));
    }
    final decoded = ApiClient.decodeBody(res);
    final token = _extractToken(decoded);
    if (token == null || token.isEmpty) {
      throw AuthException('Login succeeded but no token was returned.');
    }
    await _api.setToken(token);
    return token;
  }

  Future<void> logout() async {
    // Server can expose logout as GET (current Laravel route) or POST in some envs.
    try {
      await _api.get(ApiConstants.logoutPath);
    } catch (_) {
      try {
        await _api.postJson(ApiConstants.logoutPath, const {});
      } catch (_) {
        // Ignore network/server issues: local token clear still logs user out of app.
      }
    }
    await _api.setToken(null);
  }

  Future<bool> hasValidSession() async {
    final token = await _api.getToken();
    if (token == null || token.isEmpty) return false;
    try {
      final res = await _api.get(ApiConstants.userPath);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = ApiClient.decodeBody(res);
        if (decoded is Map && decoded['success'] == false) {
          return false;
        }
        return true;
      }
      return false;
    } on TimeoutException {
      return true;
    } on http.ClientException {
      return true;
    } catch (_) {
      return false;
    }
  }
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}
