import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../services/api_client.dart';
import '../local/app_database.dart';

/// Conversaciones: lectura local instantánea + hidratación HTTP en background.
///
/// Sync policy: all writes are additive (upsert by id). Conversations and
/// messages are NEVER deleted because the server stops returning them.
/// The only full wipe is explicit user logout via [AppDatabase.clearAll].
class ChatRepository {
  ChatRepository(this._db, this._api);

  final AppDatabase _db;
  final ApiClient _api;

  static const _conversationsCursorKey = 'conversations';

  Stream<List<Conversation>> watchConversations() {
    final businessId = _api.businessId;
    if (businessId == null || businessId.isEmpty) {
      return Stream.value(const []);
    }
    return _db.conversationDao
        .watchForBusiness(businessId)
        .map((rows) => rows.map(Conversation.fromLocalRow).toList());
  }

  Future<Conversation?> getConversation(int id) async {
    final row = await _db.conversationDao.getById(id);
    if (row == null) return null;
    return Conversation.fromLocalRow(row);
  }

  static bool _sameWa(String a, String b) {
    final na = a.replaceAll(RegExp(r'[^0-9+]'), '');
    final nb = b.replaceAll(RegExp(r'[^0-9+]'), '');
    return na == nb || na.endsWith(nb) || nb.endsWith(na);
  }

  /// Busca hilo local aunque el servidor use otro conversation_id (wa_id canonicalizado).
  Future<Conversation?> findConversationByWaId(String waId) async {
    final businessId = _api.businessId;
    if (businessId == null || businessId.isEmpty) return null;

    final rows = await _db.conversationDao.listForBusiness(businessId);
    for (final row in rows) {
      if (_sameWa(row.customerWaId, waId)) {
        return Conversation.fromLocalRow(row);
      }
    }
    return null;
  }

  Future<void> upsertConversation(
    Conversation conversation, {
    bool preserveLastSeen = true,
  }) async {
    DateTime? seen;
    if (preserveLastSeen) {
      seen = await _db.conversationDao.getLastSeen(conversation.id);
    }
    final existing = await _db.conversationDao.getById(conversation.id);
    final toWrite = existing == null
        ? conversation
        : mergeWithLocal(Conversation.fromLocalRow(existing), conversation);
    await _db.conversationDao.upsert(
      toWrite.toLocalRow(lastSeenAtOverride: seen ?? toWrite.lastSeenAt),
    );
  }

  /// Nunca retrocede lastMessageAt/preview si el servidor manda datos viejos.
  Conversation mergeWithLocal(Conversation local, Conversation incoming) {
    final localAt = local.lastMessageAt?.toUtc();
    final incomingAt = incoming.lastMessageAt?.toUtc();

    // Solo gana el servidor si trae timestamp estrictamente más nuevo.
    // Si empatan, conservar preview/at local (p. ej. envío optimista del dueño).
    final incomingWins =
        incomingAt != null && (localAt == null || incomingAt.isAfter(localAt));

    if (incomingWins) {
      return incoming.copyWith(
        lastSeenAt: local.lastSeenAt,
        updatedAt: _maxDateTime(local.updatedAt, incoming.updatedAt) ??
            incoming.updatedAt,
      );
    }

    return local.copyWith(
      customerName: _preferNonEmpty(incoming.customerName, local.customerName),
      updatedAt:
          _maxDateTime(local.updatedAt, incoming.updatedAt) ?? local.updatedAt,
    );
  }

  Future<void> upsertConversations(List<Conversation> conversations) async {
    if (conversations.isEmpty) return;

    for (final conversation in conversations) {
      await upsertConversation(conversation);
    }
    await _updateConversationsCursor(conversations);
  }

  Conversation mergeConversationWithMessage(
    Conversation conversation,
    ChatMessage message,
  ) {
    final preview = message.body.length > 80
        ? '${message.body.substring(0, 77)}...'
        : message.body;
    final lastAt = conversation.lastMessageAt?.toUtc();
    final messageAt = message.createdAt.toUtc();
    final newestAt = lastAt == null || messageAt.isAfter(lastAt)
        ? messageAt
        : lastAt;
    return conversation.copyWith(
      lastMessagePreview: preview,
      lastMessageAt: newestAt,
      updatedAt: newestAt,
    );
  }

  /// Actualiza preview/fecha tras un mensaje en vivo (WS).
  Future<void> bumpConversationFromMessage(
    Conversation conversation,
    ChatMessage message,
  ) async {
    final convId = message.conversationId;
    var base = conversation;
    if (base.id != convId) {
      base = await getConversation(convId) ?? base;
    }

    final merged = mergeConversationWithMessage(base, message);
    final seen = await _db.conversationDao.getLastSeen(merged.id);
    await _db.conversationDao.upsert(
      merged.toLocalRow(lastSeenAtOverride: seen),
    );
  }

  /// Persiste conversación del servidor aplicando [mergeWithLocal] para
  /// proteger el preview/lastMessageAt local si el servidor manda datos viejos.
  Future<void> upsertConversationFromServer(Conversation conversation) async {
    await upsertConversation(conversation);
  }

  Future<void> markSeen(int conversationId, DateTime seenAt) async {
    await _db.conversationDao.updateLastSeen(conversationId, seenAt);
  }

  Future<DateTime?> getLastSeen(int conversationId) {
    return _db.conversationDao.getLastSeen(conversationId);
  }

  Future<List<Conversation>> refreshFromApi({
    DateTime? since,
    bool silent = true,
  }) async {
    DateTime? effectiveSince = since;
    if (effectiveSince == null) {
      final cursor = await _db.syncCursorDao.getValue(_conversationsCursorKey);
      if (cursor != null && cursor.isNotEmpty) {
        effectiveSince = DateTime.tryParse(cursor);
      }
    }

    final list = await _api.getConversations(since: effectiveSince);
    if (list.isEmpty) return list;

    if (effectiveSince == null) {
      await upsertConversations(list);
      return list;
    }

    for (final conversation in list) {
      await upsertConversation(conversation);
    }
    await _updateConversationsCursor(list);
    return list;
  }

  static DateTime? _maxDateTime(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  static String? _preferNonEmpty(String? preferred, String? fallback) {
    if (preferred != null && preferred.trim().isNotEmpty) return preferred;
    return fallback;
  }

  Future<void> _updateConversationsCursor(List<Conversation> conversations) async {
    DateTime? maxAt;
    for (final conversation in conversations) {
      final candidates = [
        conversation.updatedAt,
        if (conversation.lastMessageAt != null) conversation.lastMessageAt!,
      ];
      for (final candidate in candidates) {
        if (maxAt == null || candidate.isAfter(maxAt)) {
          maxAt = candidate;
        }
      }
    }
    if (maxAt != null) {
      await _db.syncCursorDao.setCursor(
        _conversationsCursorKey,
        maxAt.toUtc().toIso8601String(),
      );
    }
  }
}
