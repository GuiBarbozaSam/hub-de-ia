import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:app_flutter/main.dart';
import 'package:app_flutter/core/http/auth_service.dart';
import 'package:app_flutter/features/auth/state/auth_controller.dart';

class _FakeAuthService extends AuthService {
  _FakeAuthService()
    : super(
        baseUrl: 'http://localhost:5045',
        client: http.Client(),
        storage: const FlutterSecureStorage(),
      );

  @override
  Future<String?> readToken() async => null;

  @override
  Future<void> clearSession() async {}
}

class _FakeAuthController extends AuthController {
  _FakeAuthController() : super(auth: _FakeAuthService());

  @override
  Future<void> bootstrap() async {}

  @override
  Future<void> login(String email, String password) async {}

  @override
  Future<void> register(String email, String password) async {}

  @override
  Future<void> handleUnauthorized() async {}

  @override
  Future<void> logout() async {}
}

void main() {
  testWidgets('app boots to login when unauthenticated', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => _FakeAuthController()),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('Cadastrar'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
