import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String operation;
  final int statusCode;
  final String body;

  ApiException(this.operation, this.statusCode, this.body);

  @override
  String toString() {
    final clean = body.trim();
    if (clean.isEmpty) {
      return '$operation falhou: HTTP $statusCode.';
    }
    return '$operation falhou: HTTP $statusCode. $clean';
  }
}

class AuthSessionResponse {
  final String accessToken;
  final String refreshToken;
  final DateTime accessTokenExpiresAtUtc;

  const AuthSessionResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresAtUtc,
  });

  factory AuthSessionResponse.fromJson(Map<String, dynamic> json) {
    final accessToken = (json['accessToken'] ?? json['AccessToken'] ?? '')
        .toString()
        .trim();
    final refreshToken = (json['refreshToken'] ?? json['RefreshToken'] ?? '')
        .toString()
        .trim();
    final rawExpiry =
        (json['accessTokenExpiresAtUtc'] ??
                json['AccessTokenExpiresAtUtc'] ??
                '')
            .toString()
            .trim();
    final expiry = DateTime.tryParse(rawExpiry)?.toUtc();

    if (accessToken.isEmpty) {
      throw const FormatException('Token de acesso não foi retornado.');
    }
    if (refreshToken.isEmpty) {
      throw const FormatException('Refresh token não foi retornado.');
    }
    if (expiry == null) {
      throw const FormatException(
        'Data de expiração do token de acesso não foi retornada.',
      );
    }

    return AuthSessionResponse(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessTokenExpiresAtUtc: expiry,
    );
  }
}

class MeResponse {
  final String email;
  final String name;

  const MeResponse({required this.email, required this.name});

  factory MeResponse.fromJson(Map<String, dynamic> json) {
    return MeResponse(
      email: (json['email'] ?? '').toString(),
      name: (json['name'] ?? json['userName'] ?? '').toString(),
    );
  }
}

class AuthService {
  AuthService({
    required this.baseUrl,
    required this.client,
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final String baseUrl;
  final http.Client client;
  final FlutterSecureStorage _storage;

  static const String _primaryTokenKey = 'access_token';
  static const List<String> _tokenAliases = <String>[
    'access_token',
    'auth_access_token',
    'token',
    'jwt',
    'jwt_token',
    'auth_token',
    'bearer_token',
  ];

  static const String _refreshTokenKey = 'refresh_token';
  static const String _accessTokenExpiryKey =
      'auth_access_token_expires_at_utc';
  static const String _emailKey = 'auth_email';
  static const String _nameKey = 'auth_name';
  static const Duration _requestTimeout = Duration(seconds: 30);
  static const Duration _refreshSkew = Duration(seconds: 30);

  Future<bool>? _refreshInFlight;

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> _headers({String? token}) => <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  void _ensureOk(http.Response res, String operation) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    throw ApiException(operation, res.statusCode, res.body);
  }

  Future<void> _persistAccessToken(String token) async {
    final clean = token.trim();
    if (clean.isEmpty) return;
    for (final key in _tokenAliases) {
      await _storage.write(key: key, value: clean);
    }
  }

  Future<void> _persistRefreshToken(String token) async {
    final clean = token.trim();
    if (clean.isEmpty) return;
    await _storage.write(key: _refreshTokenKey, value: clean);
  }

  Future<void> _persistAccessTokenExpiry(DateTime expiresAtUtc) async {
    await _storage.write(
      key: _accessTokenExpiryKey,
      value: expiresAtUtc.toUtc().toIso8601String(),
    );
  }

  Future<void> persistSession(AuthSessionResponse session) async {
    await _persistAccessToken(session.accessToken);
    await _persistRefreshToken(session.refreshToken);
    await _persistAccessTokenExpiry(session.accessTokenExpiresAtUtc);
  }

  Future<void> persistToken(String token) async {
    await _persistAccessToken(token);
  }

  Future<String?> readToken() => readAccessToken();

  Future<String?> readAccessToken() async {
    for (final key in _tokenAliases) {
      final value = await _storage.read(key: key);
      if (value != null && value.trim().isNotEmpty) {
        final clean = value.trim();
        if (key != _primaryTokenKey) {
          await _storage.write(key: _primaryTokenKey, value: clean);
        }
        return clean;
      }
    }
    return null;
  }

  Future<String?> readRefreshToken() async {
    final value = await _storage.read(key: _refreshTokenKey);
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  Future<DateTime?> readAccessTokenExpiresAtUtc() async {
    final value = await _storage.read(key: _accessTokenExpiryKey);
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value.trim())?.toUtc();
  }

  Future<void> persistProfile(MeResponse me) async {
    await _storage.write(key: _emailKey, value: me.email);
    await _storage.write(key: _nameKey, value: me.name);
  }

  Future<String?> readStoredEmail() => _storage.read(key: _emailKey);
  Future<String?> readStoredName() => _storage.read(key: _nameKey);

  Future<void> clearSession() async {
    for (final key in _tokenAliases) {
      await _storage.delete(key: key);
    }
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _accessTokenExpiryKey);
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _nameKey);
  }

  Future<String?> readValidAccessToken() async {
    final token = await readAccessToken();
    if (token == null || token.isEmpty) {
      return null;
    }

    final expiresAtUtc = await readAccessTokenExpiresAtUtc();
    if (expiresAtUtc == null) {
      return token;
    }

    final threshold = DateTime.now().toUtc().add(_refreshSkew);
    if (expiresAtUtc.isAfter(threshold)) {
      return token;
    }

    final refreshed = await tryRefreshSession();
    if (!refreshed) {
      return null;
    }

    return readAccessToken();
  }

  Future<bool> tryRefreshSession() async {
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _refreshSessionInternal();
    _refreshInFlight = future;

    try {
      return await future;
    } finally {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<bool> _refreshSessionInternal() async {
    final refreshToken = await readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await clearSession();
      return false;
    }

    final res = await client
        .post(
          _u('/api/auth/refresh'),
          headers: _headers(),
          body: jsonEncode(<String, dynamic>{'refreshToken': refreshToken}),
        )
        .timeout(_requestTimeout);

    if (res.statusCode == 401 || res.statusCode == 403) {
      await clearSession();
      return false;
    }

    _ensureOk(res, 'RefreshSession');

    final session = AuthSessionResponse.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
    await persistSession(session);
    return true;
  }

  Future<http.Response> _sendAuthorized(
    String operation,
    Future<http.Response> Function(String token) send, {
    String? token,
  }) async {
    final providedToken = token?.trim();
    final currentToken = (providedToken != null && providedToken.isNotEmpty)
        ? providedToken
        : await readValidAccessToken();

    if (currentToken == null || currentToken.isEmpty) {
      throw ApiException(operation, 401, 'Nenhum token salvo na sessão atual.');
    }

    var response = await send(currentToken);
    if (response.statusCode == 401 && await tryRefreshSession()) {
      final refreshedToken = await readAccessToken();
      if (refreshedToken != null && refreshedToken.isNotEmpty) {
        response = await send(refreshedToken);
      }
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      await clearSession();
    }

    return response;
  }

  Future<String> register(String email, String password) async {
    final res = await client
        .post(
          _u('/api/auth/register'),
          headers: _headers(),
          body: jsonEncode(<String, dynamic>{
            'email': email.trim(),
            'password': password,
          }),
        )
        .timeout(_requestTimeout);

    _ensureOk(res, 'Register');

    final session = AuthSessionResponse.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
    await persistSession(session);
    return session.accessToken;
  }

  Future<String> login(String email, String password) async {
    final res = await client
        .post(
          _u('/api/auth/login'),
          headers: _headers(),
          body: jsonEncode(<String, dynamic>{
            'email': email.trim(),
            'password': password,
          }),
        )
        .timeout(_requestTimeout);

    _ensureOk(res, 'Login');

    final session = AuthSessionResponse.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
    await persistSession(session);
    return session.accessToken;
  }

  Future<MeResponse> me([String? token]) async {
    final res = await _sendAuthorized(
      'Me',
      (resolvedToken) => client
          .get(_u('/api/auth/me'), headers: _headers(token: resolvedToken))
          .timeout(_requestTimeout),
      token: token,
    );

    _ensureOk(res, 'Me');

    final me = MeResponse.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
    await persistProfile(me);
    return me;
  }

  Future<MeResponse> meFromStorage() async {
    return me();
  }

  Future<MeResponse> updateMe({
    String? token,
    required String name,
    required String email,
  }) async {
    final res = await _sendAuthorized(
      'UpdateMe',
      (resolvedToken) => client
          .put(
            _u('/api/auth/me'),
            headers: _headers(token: resolvedToken),
            body: jsonEncode(<String, dynamic>{
              'name': name.trim(),
              'email': email.trim(),
            }),
          )
          .timeout(_requestTimeout),
      token: token,
    );

    _ensureOk(res, 'UpdateMe');
    final me = MeResponse.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
    await persistProfile(me);
    return me;
  }

  Future<void> changePassword({
    String? token,
    required String currentPassword,
    required String newPassword,
  }) async {
    final res = await _sendAuthorized(
      'ChangePassword',
      (resolvedToken) => client
          .post(
            _u('/api/auth/change-password'),
            headers: _headers(token: resolvedToken),
            body: jsonEncode(<String, dynamic>{
              'currentPassword': currentPassword,
              'newPassword': newPassword,
            }),
          )
          .timeout(_requestTimeout),
      token: token,
    );

    _ensureOk(res, 'ChangePassword');
  }

  Future<void> logout() async {
    final refreshToken = await readRefreshToken();
    final accessToken = await readAccessToken();

    try {
      if ((refreshToken ?? '').isNotEmpty || (accessToken ?? '').isNotEmpty) {
        final res = await client
            .post(
              _u('/api/auth/logout'),
              headers: _headers(token: accessToken),
              body: jsonEncode(<String, dynamic>{'refreshToken': refreshToken}),
            )
            .timeout(_requestTimeout);

        if (res.statusCode >= 500) {
          throw ApiException('Logout', res.statusCode, res.body);
        }
      }
    } finally {
      await clearSession();
    }
  }
}
