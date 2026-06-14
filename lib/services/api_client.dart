import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/business.dart';
import '../models/conversation.dart';
import '../models/customer.dart';
import '../models/menu_item.dart';
import '../models/message.dart';
import '../models/order.dart';
import 'session_storage.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isAuthError => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

typedef SessionExpiredCallback = Future<void> Function();
typedef TokenRefreshedCallback = Future<void> Function();

/// Cliente HTTP para la API WhatsBot (Fase 7). Sin secrets Twilio.
class ApiClient {
  ApiClient({
    http.Client? httpClient,
    SessionStorage? sessionStorage,
  })  : _http = httpClient ?? http.Client(),
        _sessionStorage = sessionStorage ?? SessionStorage();

  http.Client _http;
  SessionStorage _sessionStorage;

  /// Sustituye el cliente HTTP (solo tests widget/integration).
  void replaceHttpClient(http.Client client) {
    _http = client;
  }

  /// Sustituye almacenamiento seguro (solo tests).
  void replaceSessionStorage(SessionStorage storage) {
    _sessionStorage = storage;
  }

  String? _token;
  String? businessId;
  String? businessName;

  SessionExpiredCallback? onSessionExpired;
  TokenRefreshedCallback? onTokenRefreshed;

  bool _refreshInProgress = false;
  Completer<bool>? _refreshCompleter;
  bool _sessionExpiredHandling = false;

  static const _tokenKey = 'whatsbot_access_token';
  static const _businessIdKey = 'whatsbot_business_id';
  static const _businessNameKey = 'whatsbot_business_name';
  static const Duration _requestTimeout = Duration(seconds: 12);

  Future<T> _withTimeout<T>(Future<T> future) {
    return future.timeout(
      _requestTimeout,
      onTimeout: () => throw ApiException(
        'Sin respuesta del servidor. Revisa la conexión o la URL de la API.',
      ),
    );
  }

  bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  String? get accessToken => _token;

  Future<bool> hasRefreshToken() => _sessionStorage.hasRefreshToken();

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        ...ApiConfig.connectionHeaders,
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        ...ApiConfig.connectionHeaders,
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('${ApiConfig.apiBaseUrl}$path')
        .replace(queryParameters: query);
  }

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    businessId = prefs.getString(_businessIdKey);
    businessName = prefs.getString(_businessNameKey);
  }

  Future<void> _saveSession(LoginResult result) async {
    _token = result.accessToken;
    businessId = result.businessId;
    businessName = result.businessName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, result.accessToken);
    await prefs.setString(_businessIdKey, result.businessId);
    await prefs.setString(_businessNameKey, result.businessName);
    if (result.refreshToken != null && result.refreshToken!.isNotEmpty) {
      await _sessionStorage.writeRefreshToken(result.refreshToken!);
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    _token = null;
    businessId = null;
    businessName = null;
    await prefs.remove(_tokenKey);
    await prefs.remove(_businessIdKey);
    await prefs.remove(_businessNameKey);
    await _sessionStorage.clearRefreshToken();
  }

  /// Valida sesión al abrir la app o volver de background. Renueva con refresh si hace falta.
  Future<bool> ensureValidSession({bool invalidateOnFailure = true}) async {
    if (!isLoggedIn) {
      final refreshed = await _tryRefreshSession();
      if (refreshed || !invalidateOnFailure) return refreshed;
      await _handleSessionExpired();
      return false;
    }

    try {
      final response = await _withTimeout(
        _http.get(
          _uri('/whatsbot/business/me'),
          headers: _authHeaders,
        ),
      );
      if (response.statusCode == 401) {
        if (await _tryRefreshSession()) {
          final retry = await _withTimeout(
            _http.get(
              _uri('/whatsbot/business/me'),
              headers: _authHeaders,
            ),
          );
          if (retry.statusCode == 200) return true;
        }
        if (invalidateOnFailure) {
          await _handleSessionExpired();
        }
        return false;
      }
      _ensureOk(response);
      return true;
    } on ApiException catch (e) {
      if (e.isAuthError) return false;
      rethrow;
    } catch (_) {
      // Sin red: conservar sesión local y reintentar más tarde.
      return true;
    }
  }

  Future<bool> _tryRefreshSession() async {
    if (_refreshInProgress) {
      return _refreshCompleter!.future;
    }

    _refreshInProgress = true;
    _refreshCompleter = Completer<bool>();
    var success = false;
    try {
      final refreshToken = await _sessionStorage.readRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        return false;
      }

      final response = await _withTimeout(
        _http.post(
          _uri('/auth/refresh'),
          headers: _jsonHeaders,
          body: jsonEncode({'refresh_token': refreshToken}),
        ),
      );
      if (response.statusCode != 200) {
        return false;
      }

      final result = LoginResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      await _saveSession(result);
      final refreshed = onTokenRefreshed;
      if (refreshed != null) {
        await refreshed();
      }
      success = true;
      return true;
    } catch (_) {
      return false;
    } finally {
      _refreshInProgress = false;
      _refreshCompleter?.complete(success);
      _refreshCompleter = null;
    }
  }

  Future<void> _handleSessionExpired() async {
    if (_sessionExpiredHandling) return;
    _sessionExpiredHandling = true;
    try {
      await logout();
      final callback = onSessionExpired;
      if (callback != null) {
        await callback();
      }
    } finally {
      _sessionExpiredHandling = false;
    }
  }

  Future<http.Response> _authorized(
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    var response = await _withTimeout(send(_authHeaders));
    if (response.statusCode == 401) {
      if (await _tryRefreshSession()) {
        response = await _withTimeout(send(_authHeaders));
      }
      if (response.statusCode == 401) {
        await _handleSessionExpired();
      }
    }
    return response;
  }

  Future<LoginResult> login(String businessIdInput, String pin) async {
    final response = await _withTimeout(
      _http.post(
        _uri('/auth/login'),
        headers: _jsonHeaders,
        body: jsonEncode({'business_id': businessIdInput, 'pin': pin}),
      ),
    );
    if (response.statusCode == 200) {
      final result = LoginResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      await _saveSession(result);
      return result;
    }
    throw _errorFromResponse(response, 'No se pudo iniciar sesión');
  }

  Future<List<Conversation>> getConversations({DateTime? since}) async {
    final query = since != null
        ? {'since': since.toUtc().toIso8601String()}
        : null;
    final response = await _authorized(
      (headers) => _http.get(
        _uri('/whatsbot/conversations', query),
        headers: headers,
      ),
    );
    _ensureOk(response);
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> markConversationRead(int conversationId) async {
    final response = await _authorized(
      (headers) => _http.post(
        _uri('/whatsbot/conversations/$conversationId/mark-read'),
        headers: headers,
      ),
    );
    _ensureOk(response, expected: {204, 200});
  }

  Future<List<ChatMessage>> getMessages(
    int conversationId, {
    int? afterId,
  }) async {
    final query =
        afterId != null ? {'after_id': afterId.toString()} : null;
    final response = await _authorized(
      (headers) => _http.get(
        _uri('/whatsbot/conversations/$conversationId/messages', query),
        headers: headers,
      ),
    );
    _ensureOk(response);
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ChatMessage> sendMessage({
    required String customerWaId,
    required String body,
    String? clientId,
  }) async {
    final payload = <String, dynamic>{
      'customer_wa_id': customerWaId,
      'body': body,
    };
    if (clientId != null && clientId.isNotEmpty) {
      payload['client_id'] = clientId;
    }
    final response = await _authorized(
      (headers) => _http.post(
        _uri('/whatsbot/messages'),
        headers: headers,
        body: jsonEncode(payload),
      ),
    );
    _ensureOk(response, expected: {201, 200});
    return ChatMessage.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<PendingOrder>> getPendingOrders() async {
    final response = await _authorized(
      (headers) => _http.get(
        _uri('/whatsbot/orders/pending'),
        headers: headers,
      ),
    );
    _ensureOk(response);
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => PendingOrder.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> approveOrder(String orderId) async {
    final response = await _authorized(
      (headers) => _http.post(
        _uri('/whatsbot/orders/$orderId/approve'),
        headers: headers,
      ),
    );
    _ensureOk(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw ApiException(
        data['message'] as String? ?? 'No se pudo confirmar el pedido',
        statusCode: response.statusCode,
      );
    }
    return data['message'] as String? ?? 'Pedido aprobado';
  }

  Future<void> registerDeviceToken({
    required String token,
    required String platform,
  }) async {
    final response = await _authorized(
      (headers) => _http.post(
        _uri('/whatsbot/device-token'),
        headers: headers,
        body: jsonEncode({'token': token, 'platform': platform}),
      ),
    );
    _ensureOk(response, expected: {204, 200});
  }

  Future<void> unregisterDeviceToken({
    required String token,
    required String platform,
  }) async {
    final response = await _authorized((headers) async {
      final request = http.Request('DELETE', _uri('/whatsbot/device-token'));
      request.headers.addAll(headers);
      request.body = jsonEncode({'token': token, 'platform': platform});
      final streamed = await _http.send(request);
      return http.Response.fromStream(streamed);
    });
    _ensureOk(response, expected: {204, 200});
  }

  Future<String> rejectOrder(String orderId, {String reason = ''}) async {
    final response = await _authorized(
      (headers) => _http.post(
        _uri('/whatsbot/orders/$orderId/reject', {'reason': reason}),
        headers: headers,
      ),
    );
    _ensureOk(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['message'] as String? ?? 'Pedido rechazado';
  }

  Future<BusinessProfile> getBusinessMe() async {
    final response = await _authorized(
      (headers) => _http.get(
        _uri('/whatsbot/business/me'),
        headers: headers,
      ),
    );
    _ensureOk(response);
    return BusinessProfile.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<MenuItemModel>> getMenu() async {
    final response = await _authorized(
      (headers) => _http.get(
        _uri('/whatsbot/business/menu'),
        headers: headers,
      ),
    );
    _ensureOk(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    return items
        .map((e) => MenuItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MenuItemModel>> saveMenu(List<MenuItemModel> items) async {
    final response = await _authorized(
      (headers) => _http.put(
        _uri('/whatsbot/business/menu'),
        headers: headers,
        body: jsonEncode({
          'items': items.map((i) => i.toApiJson()).toList(),
        }),
      ),
    );
    _ensureOk(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final saved = data['items'] as List<dynamic>? ?? [];
    return saved
        .map((e) => MenuItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> getIntents() async {
    final response = await _authorized(
      (headers) => _http.get(
        _uri('/whatsbot/business/intents'),
        headers: headers,
      ),
    );
    _ensureOk(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(data['config'] as Map? ?? {});
  }

  Future<Map<String, dynamic>> saveIntents(Map<String, dynamic> config) async {
    final response = await _authorized(
      (headers) => _http.put(
        _uri('/whatsbot/business/intents'),
        headers: headers,
        body: jsonEncode({'config': config}),
      ),
    );
    _ensureOk(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return Map<String, dynamic>.from(data['config'] as Map? ?? {});
  }

  Future<Map<String, String>> getPrompts() async {
    final response = await _authorized(
      (headers) => _http.get(
        _uri('/whatsbot/business/prompts'),
        headers: headers,
      ),
    );
    _ensureOk(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final config = data['config'] as Map? ?? {};
    return config.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  Future<Map<String, String>> savePrompts(Map<String, String> config) async {
    final response = await _authorized(
      (headers) => _http.put(
        _uri('/whatsbot/business/prompts'),
        headers: headers,
        body: jsonEncode({'config': config}),
      ),
    );
    _ensureOk(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final saved = data['config'] as Map? ?? {};
    return saved.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  Future<List<Customer>> getCustomers({String? search}) async {
    final query = search != null && search.isNotEmpty ? {'search': search} : null;
    final response = await _authorized(
      (headers) => _http.get(
        _uri('/whatsbot/customers', query),
        headers: headers,
      ),
    );
    _ensureOk(response);
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.map((e) => Customer.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Customer> createCustomer({
    required String waId,
    String? name,
    String? phone,
    String? notes,
  }) async {
    final payload = <String, dynamic>{'wa_id': waId};
    if (name != null) payload['name'] = name;
    if (phone != null) payload['phone'] = phone;
    if (notes != null) payload['notes'] = notes;
    final response = await _authorized(
      (headers) => _http.post(
        _uri('/whatsbot/customers'),
        headers: headers,
        body: jsonEncode(payload),
      ),
    );
    _ensureOk(response, expected: {201, 200});
    return Customer.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Customer> updateCustomer(
    int customerId, {
    String? name,
    String? phone,
    String? notes,
    bool? blocked,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name;
    if (phone != null) payload['phone'] = phone;
    if (notes != null) payload['notes'] = notes;
    if (blocked != null) payload['blocked'] = blocked;
    final response = await _authorized(
      (headers) => _http.put(
        _uri('/whatsbot/customers/$customerId'),
        headers: headers,
        body: jsonEncode(payload),
      ),
    );
    _ensureOk(response);
    return Customer.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> deleteCustomer(int customerId) async {
    final response = await _authorized(
      (headers) => _http.delete(
        _uri('/whatsbot/customers/$customerId'),
        headers: headers,
      ),
    );
    _ensureOk(response, expected: {204, 200});
  }

  void _ensureOk(http.Response response, {Set<int>? expected}) {
    final ok = expected ?? {200};
    if (!ok.contains(response.statusCode)) {
      throw _errorFromResponse(response);
    }
  }

  ApiException _errorFromResponse(http.Response response, [String? fallback]) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map && data['detail'] != null) {
        final detail = data['detail'];
        if (detail is String) {
          return ApiException(detail, statusCode: response.statusCode);
        }
        if (detail is List && detail.isNotEmpty) {
          return ApiException(
            detail.first['msg']?.toString() ?? fallback ?? 'Error',
            statusCode: response.statusCode,
          );
        }
      }
    } catch (_) {}
    return ApiException(
      fallback ?? 'Error ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }
}

/// Singleton compartido en la app.
final apiClient = ApiClient();
