import 'package:whatsbot_app/services/session_storage.dart';

/// Almacenamiento en memoria para tests (sin Keychain/Keystore).
class InMemorySessionStorage extends SessionStorage {
  InMemorySessionStorage({Map<String, String>? initial})
      : _values = Map<String, String>.from(initial ?? {});

  final Map<String, String> _values;

  @override
  Future<String?> readRefreshToken() async => _values['refresh'];

  @override
  Future<void> writeRefreshToken(String token) async {
    _values['refresh'] = token;
  }

  @override
  Future<void> clearRefreshToken() async {
    _values.remove('refresh');
  }

  @override
  Future<bool> hasRefreshToken() async {
    final token = _values['refresh'];
    return token != null && token.isNotEmpty;
  }
}
