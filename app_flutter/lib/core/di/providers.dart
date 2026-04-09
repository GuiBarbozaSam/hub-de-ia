import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../http/auth_service.dart';

final httpClientProvider = Provider<http.Client>((ref) {
  return http.Client();
});

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    baseUrl: AppConfig.apiBaseUrl,
    client: ref.read(httpClientProvider),
  );
});
