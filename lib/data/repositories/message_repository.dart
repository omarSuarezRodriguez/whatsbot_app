import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../models/send_message_result.dart';
import '../../services/api_client.dart';
import '../local/app_database.dart';

/// Mensajes: historial local, sync incremental y cola saliente offline (OF-C).
class MessageRepository {
  MessageRepository(this._db, this._api);

  final AppDatabase _db;
  final ApiClient _api;
  final _uuid = const Uuid();

  String _messagesCursorKey(int conversationId) => 'messages:$conversationId';

  String _messagesSyncTimeKey(int conversationId) => 'messages_sync_at:$conversationId';

  static const Duration syncTtl = Duration(minutes: 2);

  Future<bool> hasLocalMessages(int conversationId) async {
    final maxId = await _db.messageDao.maxMessageId(conversationId);
    return (maxId ?? 0) > 0;
  }

  /// True si hace falta pedir delta al servidor (sin caché, sin sync previo o TTL vencido).
  Future<bool> needsSyncFromApi(int conversationId) async {
    if (!await hasLocalMessages(conversationId)) return true;
    final lastSync =
        await _db.syncCursorDao.getUpdatedAt(_messagesSyncTimeKey(conversationId));
    if (lastSync == null) return true;
    return DateTime.now().toUtc().difference(lastSync) > syncTtl;
  }

  Stream<List<ChatMessage>> watchMessages(int conversationId) {
    return _db.messageDao.watchForConversation(conversationId).map(_mapSorted);
  }

  /// Stream del hilo abierto: id local + mensajes con mismo wa_id aunque el
  /// servidor haya usado otro conversation_id al persistir.
  Stream<List<ChatMessage>> watchChatMessages(Conversation conversation) {
    return _db.messageDao
        .watchForChatThread(
          conversation.id,
          (waId) => _sameWa(waId, conversation.customerWaId),
        )
        .map(_mapSorted);
  }

  List<ChatMessage> _mapSorted(List<MessageEntity> rows) {
    final messages = rows.map(ChatMessage.fromLocalRow).toList();
    messages.sort(ChatMessage.compareChronological);
    return messages;
  }

  /// Lectura puntual de SQLite para precargar antes de abrir el chat.
  Future<List<ChatMessage>> getCachedMessages(int conversationId) =>
      watchMessages(conversationId).first;

  /// Maximum messages kept per chat in local storage.
  ///
  /// Policy: prune is a local storage limit only — messages are NEVER deleted
  /// because the server stopped returning them. Server = sync channel for new
  /// data; local SQLite = durable archive of received history. The only full
  /// wipe is explicit user logout via [AppDatabase.clearAll].
  static const int retentionPerChat = 10000;

  /// No mover mensajes entre conversaciones al sincronizar (PK = id).
  ChatMessage _preserveLocalConversation(
    ChatMessage incoming,
    MessageEntity? existing,
  ) {
    if (existing == null) return incoming;
    return incoming.copyWith(conversationId: existing.conversationId);
  }

  static bool _sameWa(String a, String b) {
    final na = a.replaceAll(RegExp(r'[^0-9+]'), '');
    final nb = b.replaceAll(RegExp(r'[^0-9+]'), '');
    return na == nb || na.endsWith(nb) || nb.endsWith(na);
  }

  /// Enlaza mensaje WS/REST al hilo local que ve la UI (wa_id antes que conversation_id servidor).
  Future<ChatMessage> resolveForLocalStore(
    ChatMessage message, {
    Iterable<int>? openConversationIds,
  }) async {
    final existing = await _db.messageDao.getById(message.id);
    if (existing != null) {
      return message.copyWith(conversationId: existing.conversationId);
    }

    if (message.clientUuid != null && message.clientUuid!.isNotEmpty) {
      final byClient = await _db.messageDao.getByClientUuid(message.clientUuid!);
      if (byClient != null) {
        return message.copyWith(conversationId: byClient.conversationId);
      }
    }

    final boundToOpen = await _bindToOpenConversations(
      message,
      openConversationIds,
    );
    if (boundToOpen != null) return boundToOpen;

    final businessId = _api.businessId;
    if (businessId != null && businessId.isNotEmpty) {
      final conversations = await _db.conversationDao.listForBusiness(businessId);
      for (final conv in conversations) {
        if (_sameWa(conv.customerWaId, message.waId)) {
          return message.copyWith(conversationId: conv.id);
        }
      }
    }

    final localConv = await _db.conversationDao.getById(message.conversationId);
    if (localConv != null && _sameWa(localConv.customerWaId, message.waId)) {
      return message;
    }

    // Fallthrough: no local conversation matched by id, clientUuid, wa_id, or
    // server conversationId. SyncEngine._ensureLocalConversation should have
    // prevented this; message will be stored under the server's conversationId.
    assert(() {
      // ignore: avoid_print
      print('[resolveForLocalStore] no local conv for '
          'id=${message.id} waId=${message.waId} '
          'serverConvId=${message.conversationId}');
      return true;
    }());
    return message;
  }

  Future<ChatMessage?> _bindToOpenConversations(
    ChatMessage message,
    Iterable<int>? openConversationIds,
  ) async {
    if (openConversationIds == null) return null;
    for (final openId in openConversationIds) {
      final open = await _db.conversationDao.getById(openId);
      if (open != null && _sameWa(open.customerWaId, message.waId)) {
        return message.copyWith(conversationId: openId);
      }
    }
    return null;
  }

  Future<ChatMessage> _resolveForLocalStore(ChatMessage message) =>
      resolveForLocalStore(message);

  Future<void> upsertMessage(
    ChatMessage message, {
    bool alreadyResolved = false,
  }) async {
    final existing = await _db.messageDao.getById(message.id);
    final resolved =
        alreadyResolved ? message : await _resolveForLocalStore(message);
    final toWrite = _preserveLocalConversation(resolved, existing);
    await _db.messageDao.upsert(toWrite.toLocalRow());
    if (toWrite.id > 0) {
      await _updateMessagesCursor(toWrite.conversationId, toWrite.id);
    }
    await _db.messageDao.pruneOldMessages(
      toWrite.conversationId,
      keep: retentionPerChat,
    );
  }

  /// Inserta o actualiza solo si el mensaje es nuevo o cambió.
  Future<bool> upsertMessageDeduped(
    ChatMessage message, {
    bool alreadyResolved = false,
  }) async {
    final resolved =
        alreadyResolved ? message : await _resolveForLocalStore(message);

    if (resolved.clientUuid != null && resolved.clientUuid!.isNotEmpty) {
      final pending = await _db.outboundQueueDao.getByClientUuid(
        resolved.clientUuid!,
      );
      if (pending != null) {
        await _ackOutbound(
          clientUuid: resolved.clientUuid!,
          serverMessage: resolved,
          tempMessageId: pending.tempMessageId,
        );
        return true;
      }
    }

    final existing = await _db.messageDao.getById(resolved.id);
    if (existing != null &&
        existing.body == resolved.body &&
        existing.status == resolved.status &&
        existing.deliveredAt == resolved.deliveredAt &&
        existing.readAt == resolved.readAt) {
      return false;
    }
    if (existing != null &&
        existing.body == resolved.body &&
        (existing.status != resolved.status ||
            existing.deliveredAt != resolved.deliveredAt ||
            existing.readAt != resolved.readAt)) {
      await updateStatus(
        messageId: resolved.id,
        status: resolved.status,
        deliveredAt: resolved.deliveredAt,
        readAt: resolved.readAt,
      );
      return true;
    }
    await upsertMessage(resolved, alreadyResolved: true);
    return true;
  }

  Future<void> upsertMessages(List<ChatMessage> messages) async {
    if (messages.isEmpty) return;

    final toWrite = <ChatMessage>[];
    for (final message in messages) {
      if (message.clientUuid != null && message.clientUuid!.isNotEmpty) {
        final pending = await _db.outboundQueueDao.getByClientUuid(
          message.clientUuid!,
        );
        if (pending != null) {
          await _ackOutbound(
            clientUuid: message.clientUuid!,
            serverMessage: message,
            tempMessageId: pending.tempMessageId,
          );
          continue;
        }
      }

      final existing = await _db.messageDao.getById(message.id);
      if (existing != null &&
          existing.body == message.body &&
          existing.status == message.status &&
          existing.deliveredAt == message.deliveredAt &&
          existing.readAt == message.readAt) {
        continue;
      }
      if (existing != null &&
          existing.body == message.body &&
          (existing.status != message.status ||
              existing.deliveredAt != message.deliveredAt ||
              existing.readAt != message.readAt)) {
        await updateStatus(
          messageId: message.id,
          status: message.status,
          deliveredAt: message.deliveredAt,
          readAt: message.readAt,
        );
        continue;
      }
      toWrite.add(await _resolveForLocalStore(message));
    }
    if (toWrite.isEmpty) return;

    final preservedToWrite = <ChatMessage>[];
    final rows = <MessagesCompanion>[];
    for (final message in toWrite) {
      final existing = await _db.messageDao.getById(message.id);
      final preserved = _preserveLocalConversation(message, existing);
      preservedToWrite.add(preserved);
      rows.add(preserved.toLocalRow());
    }
    await _db.messageDao.upsertAll(rows);

    final byConversation = <int, int>{};
    for (final message in preservedToWrite) {
      if (message.id <= 0) continue;
      final current = byConversation[message.conversationId];
      if (current == null || message.id > current) {
        byConversation[message.conversationId] = message.id;
      }
    }
    for (final entry in byConversation.entries) {
      await _updateMessagesCursor(entry.key, entry.value);
      await _db.messageDao.pruneOldMessages(
        entry.key,
        keep: retentionPerChat,
      );
    }
    await _bumpConversationsFromMessages(preservedToWrite);
  }

  Future<void> updateStatus({
    required int messageId,
    required String status,
    DateTime? deliveredAt,
    DateTime? readAt,
  }) async {
    await _db.messageDao.updateStatus(
      messageId: messageId,
      status: status,
      deliveredAt: deliveredAt,
      readAt: readAt,
    );
  }

  Future<bool> updateStatusDeduped({
    required int messageId,
    required String status,
    DateTime? deliveredAt,
    DateTime? readAt,
  }) async {
    final existing = await _db.messageDao.getById(messageId);
    if (existing != null &&
        existing.status == status &&
        existing.deliveredAt == deliveredAt &&
        existing.readAt == readAt) {
      return false;
    }
    await updateStatus(
      messageId: messageId,
      status: status,
      deliveredAt: deliveredAt,
      readAt: readAt,
    );
    return true;
  }

  Future<List<ChatMessage>> refreshFromApi(
    int conversationId, {
    bool incremental = false,
  }) async {
    int? afterId;
    if (incremental) {
      afterId = await _db.messageDao.maxMessageId(conversationId);
      if (afterId != null && afterId <= 0) {
        afterId = null;
      }
    }

    final messages = await _api.getMessages(
      conversationId,
      afterId: afterId,
    );
    if (messages.isNotEmpty) {
      await upsertMessages(messages);
    }
    await _db.syncCursorDao.setCursor(_messagesSyncTimeKey(conversationId), '1');
    return messages;
  }

  /// Inserta mensaje optimista, encola y envía si hay red.
  Future<SendMessageResult> sendMessage({
    required int conversationId,
    required String customerWaId,
    required String body,
    String? clientUuid,
  }) async {
    final resolvedClientUuid = clientUuid ?? _uuid.v4();
    final tempId = await _db.messageDao.nextTempMessageId();
    final now = DateTime.now().toUtc();

    final optimistic = ChatMessage(
      id: tempId,
      conversationId: conversationId,
      direction: 'outgoing',
      body: body,
      waId: customerWaId,
      isAdmin: true,
      channel: 'whatsapp',
      status: 'pending',
      createdAt: now,
      clientUuid: resolvedClientUuid,
    );

    await upsertMessage(optimistic);
    await _bumpConversation(optimistic);
    await _db.outboundQueueDao.enqueue(
      OutboundQueueCompanion.insert(
        clientUuid: resolvedClientUuid,
        conversationId: conversationId,
        tempMessageId: tempId,
        customerWaId: customerWaId,
        body: body,
        createdAt: now,
      ),
    );

    try {
      final server = await _api.sendMessage(
        customerWaId: customerWaId,
        body: body,
        clientId: resolvedClientUuid,
      );
      final resolved = await _ackOutbound(
        clientUuid: resolvedClientUuid,
        serverMessage: server,
        tempMessageId: tempId,
      );
      return SendMessageResult(message: resolved, queued: false);
    } catch (_) {
      return SendMessageResult(message: optimistic, queued: true);
    }
  }

  /// Reintenta todos los mensajes pendientes en la cola.
  Future<void> flushOutboundQueue() async {
    final pending = await _db.outboundQueueDao.listPending();
    for (final item in pending) {
      try {
        final server = await _api.sendMessage(
          customerWaId: item.customerWaId,
          body: item.body,
          clientId: item.clientUuid,
        );
        await _ackOutbound(
          clientUuid: item.clientUuid,
          serverMessage: server,
          tempMessageId: item.tempMessageId,
        );
      } catch (e) {
        await _db.outboundQueueDao.recordFailure(
          item.clientUuid,
          e.toString(),
        );
      }
    }
  }

  Future<ChatMessage> _ackOutbound({
    required String clientUuid,
    required ChatMessage serverMessage,
    required int tempMessageId,
  }) async {
    final tempRow = await _db.messageDao.getById(tempMessageId);
    final pending = await _db.outboundQueueDao.getByClientUuid(clientUuid);
    // Mantener la conversación abierta en la app aunque el servidor canonicalice wa_id distinto.
    var localConversationId = tempRow?.conversationId ??
        pending?.conversationId ??
        serverMessage.conversationId;
    if (tempRow == null && pending == null) {
      localConversationId =
          (await _resolveForLocalStore(serverMessage)).conversationId;
    }
    final resolved = ChatMessage(
      id: serverMessage.id,
      conversationId: localConversationId,
      direction: serverMessage.direction,
      body: serverMessage.body,
      waId: serverMessage.waId,
      isAdmin: serverMessage.isAdmin,
      channel: serverMessage.channel,
      status: serverMessage.status,
      deliveredAt: serverMessage.deliveredAt,
      readAt: serverMessage.readAt,
      createdAt: tempRow?.createdAt.toUtc() ?? serverMessage.createdAt,
      clientUuid: serverMessage.clientUuid ?? clientUuid,
    );

    await _db.transaction(() async {
      await _db.messageDao.deleteById(tempMessageId);
      await _db.messageDao.upsert(resolved.toLocalRow());
      await _db.outboundQueueDao.remove(clientUuid);
    });
    await _updateMessagesCursor(
      resolved.conversationId,
      resolved.id,
    );
    await _db.messageDao.pruneOldMessages(
      resolved.conversationId,
      keep: retentionPerChat,
    );

    await _bumpConversation(resolved);
    return resolved;
  }

  Future<void> _bumpConversation(ChatMessage message) async {
    final conversation = await _db.conversationDao.getById(
      message.conversationId,
    );
    if (conversation == null) return;

    final preview = message.body.length > 80
        ? '${message.body.substring(0, 77)}...'
        : message.body;
    final localAt = conversation.lastMessageAt?.toUtc();
    final messageAt = message.createdAt.toUtc();
    if (localAt != null && localAt.isAfter(messageAt) && !message.isOutgoing) {
      return;
    }

    await _db.conversationDao.upsert(
      ConversationsCompanion(
        id: Value(conversation.id),
        businessId: Value(conversation.businessId),
        customerWaId: Value(conversation.customerWaId),
        customerName: Value(conversation.customerName),
        lastMessagePreview: Value(preview),
        lastMessageAt: Value(messageAt),
        updatedAt: Value(messageAt),
        lastSeenAt: Value(conversation.lastSeenAt),
        syncedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> _updateMessagesCursor(int conversationId, int messageId) async {
    if (messageId <= 0) return;
    final key = _messagesCursorKey(conversationId);
    final currentRaw = await _db.syncCursorDao.getValue(key);
    final current = int.tryParse(currentRaw ?? '') ?? 0;
    if (messageId > current) {
      await _db.syncCursorDao.setCursor(key, messageId.toString());
    }
  }

  Future<void> _bumpConversationsFromMessages(List<ChatMessage> messages) async {
    if (messages.isEmpty) return;

    final latestByConversation = <int, ChatMessage>{};
    for (final message in messages) {
      if (message.id <= 0) continue;
      final current = latestByConversation[message.conversationId];
      if (current == null ||
          ChatMessage.compareChronological(message, current) > 0) {
        latestByConversation[message.conversationId] = message;
      }
    }

    for (final message in latestByConversation.values) {
      await _bumpConversation(message);
    }
  }
}
