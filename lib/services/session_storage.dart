import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Refresh token en almacenamiento seguro del SO (Keychain / Keystore).
class SessionStorage {
  SessionStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _refreshKey = 'whatsbot_refresh_token';

  final FlutterSecureStorage _storage;

  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _refreshKey, value: token);

  Future<void> clearRefreshToken() => _storage.delete(key: _refreshKey);

  Future<bool> hasRefreshToken() async {
    final token = await readRefreshToken();
    return token != null && token.isNotEmpty;
  }
}
