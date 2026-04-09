import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/http/auth_service.dart';

class AuthState {
  final bool loading;
  final String? token;
  final Object? error;

  const AuthState({required this.loading, this.token, this.error});

  factory AuthState.initial() => const AuthState(loading: false);

  static const _unset = Object();

  AuthState copyWith({
    bool? loading,
    Object? token = _unset,
    Object? error = _unset,
  }) {
    return AuthState(
      loading: loading ?? this.loading,
      token: identical(token, _unset) ? this.token : token as String?,
      error: identical(error, _unset) ? this.error : error,
    );
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    return AuthController(auth: ref.read(authServiceProvider))..bootstrap();
  },
);

class AuthController extends StateNotifier<AuthState> {
  AuthController({required this.auth}) : super(AuthState.initial());

  final AuthService auth;

  Future<void> bootstrap() async {
    state = state.copyWith(loading: true, error: null);

    try {
      final me = await auth.meFromStorage();
      final token = await auth.readToken();
      await auth.persistProfile(me);
      state = state.copyWith(loading: false, token: token, error: null);
    } catch (e) {
      if (_isUnauthorized(e)) {
        await auth.clearSession();
        state = state.copyWith(loading: false, token: null, error: null);
        return;
      }

      final token = await auth.readToken();
      state = state.copyWith(loading: false, token: token, error: e);
    }
  }

  Future<void> register(String email, String password) async {
    state = state.copyWith(loading: true, error: null);

    try {
      await auth.register(email, password);
      try {
        final me = await auth.meFromStorage();
        await auth.persistProfile(me);
      } catch (e) {
        if (_isUnauthorized(e)) {
          await auth.clearSession();
          rethrow;
        }
      }

      final token = await auth.readToken();
      state = state.copyWith(loading: false, token: token, error: null);
    } catch (e) {
      state = state.copyWith(loading: false, token: null, error: e);
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(loading: true, error: null);

    try {
      await auth.login(email, password);
      try {
        final me = await auth.meFromStorage();
        await auth.persistProfile(me);
      } catch (e) {
        if (_isUnauthorized(e)) {
          await auth.clearSession();
          rethrow;
        }
      }

      final token = await auth.readToken();
      state = state.copyWith(loading: false, token: token, error: null);
    } catch (e) {
      state = state.copyWith(loading: false, token: null, error: e);
    }
  }

  Future<void> handleUnauthorized() async {
    await auth.clearSession();
    state = AuthState.initial();
  }

  Future<void> logout() async {
    await auth.logout();
    state = AuthState.initial();
  }

  bool _isUnauthorized(Object error) {
    return error is ApiException && error.statusCode == 401;
  }
}
