import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/http/auth_service.dart';
import 'auth_controller.dart';

class ProfileState {
  final bool loading;
  final bool saving;
  final bool changingPassword;
  final MeResponse? me;
  final String? error;
  final String? success;

  const ProfileState({
    this.loading = false,
    this.saving = false,
    this.changingPassword = false,
    this.me,
    this.error,
    this.success,
  });

  ProfileState copyWith({
    bool? loading,
    bool? saving,
    bool? changingPassword,
    MeResponse? me,
    String? error,
    String? success,
  }) {
    return ProfileState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      changingPassword: changingPassword ?? this.changingPassword,
      me: me ?? this.me,
      error: error,
      success: success,
    );
  }
}

final profileControllerProvider =
    StateNotifierProvider<ProfileController, ProfileState>((ref) {
      return ProfileController(ref: ref, api: ref.read(authServiceProvider));
    });

class ProfileController extends StateNotifier<ProfileState> {
  final Ref ref;
  final AuthService api;

  ProfileController({required this.ref, required this.api})
    : super(const ProfileState());

  Future<void> _handleError(Object error) async {
    if (error is ApiException && error.statusCode == 401) {
      await ref.read(authControllerProvider.notifier).handleUnauthorized();
    }
  }

  Future<void> loadMe() async {
    state = state.copyWith(loading: true, error: null, success: null);

    try {
      final me = await api.meFromStorage();
      state = state.copyWith(loading: false, me: me);
    } catch (e) {
      await _handleError(e);
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<bool> updateMe({required String name, required String email}) async {
    state = state.copyWith(saving: true, error: null, success: null);

    try {
      final me = await api.updateMe(name: name, email: email);

      state = state.copyWith(
        saving: false,
        me: me,
        success: 'Perfil atualizado com sucesso.',
      );
      return true;
    } catch (e) {
      await _handleError(e);
      state = state.copyWith(saving: false, error: e.toString());
      return false;
    }
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    state = state.copyWith(changingPassword: true, error: null, success: null);

    try {
      await api.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

      state = state.copyWith(
        changingPassword: false,
        success: 'Senha alterada com sucesso.',
      );
      return true;
    } catch (e) {
      await _handleError(e);
      state = state.copyWith(changingPassword: false, error: e.toString());
      return false;
    }
  }

  void clearMessages() {
    state = state.copyWith(error: null, success: null);
  }
}
