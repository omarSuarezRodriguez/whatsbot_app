import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:whatsbot_app/services/api_client.dart';
import 'package:whatsbot_app/services/session_storage.dart';

class _MemorySessionStorage extends SessionStorage {
  _MemorySessionStorage(this._values);

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiClient session auth', () {
    late _MemorySessionStorage storage;
    late ApiClient client;

    setUp(() {
      storage = _MemorySessionStorage({});
      SharedPreferences.setMockInitialValues({});
      client = ApiClient(
        httpClient: MockClient((request) async {
          final path = request.url.path;

          if (path.endsWith('/auth/login')) {
            return http.Response(
              jsonEncode({
                'access_token': 'access-1',
                'refresh_token': 'refresh-1',
                'business_id': 'default',
                'business_name': 'Test',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (path.endsWith('/auth/refresh')) {
            final body =
                jsonDecode(request.body as String) as Map<String, dynamic>;
            if (body['refresh_token'] != 'refresh-1') {
              return http.Response(
                jsonEncode({'detail': 'Refresh token inválido o expirado'}),
                401,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode({
                'access_token': 'access-2',
                'refresh_token': 'refresh-2',
                'business_id': 'default',
                'business_name': 'Test',
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (path.endsWith('/whatsbot/business/me')) {
            final auth = request.headers['Authorization'] ?? '';
            if (auth == 'Bearer access-1') {
              return http.Response(
                jsonEncode({'detail': 'Token inválido o expirado'}),
                401,
                headers: {'content-type': 'application/json'},
              );
            }
            if (auth == 'Bearer access-2') {
              return http.Response(
                jsonEncode({
                  'id': 'default',
                  'name': 'Test',
                  'twilio_whatsapp_from': '',
                  'admin_whatsapp_number': '',
                  'sheets_enabled': false,
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
          }

          return http.Response('[]', 404);
        }),
        sessionStorage: storage,
      );
    });

    test('login guarda refresh token en almacenamiento seguro', () async {
      await client.login('default', '1234');
      expect(await storage.readRefreshToken(), 'refresh-1');
      expect(client.accessToken, 'access-1');
    });

    test('ensureValidSession renueva access token expirado', () async {
      await client.login('default', '1234');
      final valid = await client.ensureValidSession();
      expect(valid, isTrue);
      expect(client.accessToken, 'access-2');
      expect(await storage.readRefreshToken(), 'refresh-2');
    });

    test('_authorized reintenta tras refresh en 401', () async {
      await client.login('default', '1234');
      final profile = await client.getBusinessMe();
      expect(profile.id, 'default');
      expect(client.accessToken, 'access-2');
    });
  });
}
