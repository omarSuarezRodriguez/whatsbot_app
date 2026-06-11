import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../models/realtime_event.dart';
import '../../services/realtime_service.dart';
import '../repositories/chat_repository.dart';
import '../repositories/message_repository.dart';

/// Callback tras persistir un mensaje entrante (alertas / badges).
typedef IncomingMessageCallback = Future<void> Function(
  Conversation conversation,
  ChatMessage message,
);

/// Motor de sync incremental: REST + WS → SQLite con dedup.
class SyncEngine {
  SyncEngine(this._chats, this._messages);

  final ChatRepository _chats;
  final MessageRepository _messages;

  IncomingMessageCallback? onIncomingMessage;

  final Set<int> _openConversationIds = {};
  Future<void> _syncChain = Future.value();
  bool _syncRunning = false;

  static const int messageRetentionPerChat = 500;

  void trackOpenConversation(int conversationId) {
    _openConversationIds.add(conversationId);
  }

  void untrackOpenConversation(int conversationId) {
    _openConversationIds.remove(conversationId);
  }

  /// Persiste evento WS en SQLite antes de que la UI lo procese.
  Future<void> handleRealtimeEvent(RealtimeEvent event) async {
    switch (event.type) {
      case 'message.new':
        await _handleMessageNew(event);
        break;
      case 'message.status':
        await _handleMessageStatus(event);
        break;
      case 'conversation.updated':
      case 'conversation.sync':
        final conversation = event.conversation;
        if (conversation != null) {
          await _chats.upsertConversationFromServer(conversation);
        }
        break;
    }
  }

  /// Sync incremental tras reconexión WS (cursors en SQLite).
  /// Serializado para evitar carreras tras login + WS connected simultáneos.
  Future<void> syncOnReconnect() {
    final run = _syncChain.then((_) => _syncOnReconnectUnlocked());
    _syncChain = run.catchError((_) {});
    return run;
  }

  Future<void> _syncOnReconnectUnlocked() async {
    if (_syncRunning) return;
    _syncRunning = true;
    try {
      await _messages.flushOutboundQueue();
      await syncConversationsIncremental();
      for (final conversationId in _openConversationIds) {
        await syncMessagesIncremental(conversationId, force: true);
      }
    } finally {
      _syncRunning = false;
    }
  }

  /// Sync incremental for open chats when WebSocket is down (fallback, no polling when WS up).
  Future<void> syncOpenConversations({bool force = false}) async {
    for (final conversationId in _openConversationIds) {
      await syncMessagesIncremental(conversationId, force: force);
    }
  }

  Future<List<Conversation>> syncConversationsIncremental() {
    return _chats.refreshFromApi();
  }

  Future<List<ChatMessage>> syncMessagesIncremental(
    int conversationId, {
    bool force = false,
  }) async {
    // WS caído: no confiar en TTL; REST es el único canal de mensajes nuevos.
    final bypassTtl = force || !realtimeService.isConnected;
    if (!bypassTtl && !await _messages.needsSyncFromApi(conversationId)) {
      return const [];
    }
    return _messages.refreshFromApi(
      conversationId,
      incremental: true,
    );
  }

  Future<void> _handleMessageNew(RealtimeEvent event) async {
    final message = event.message;
    if (message == null) return;

    // Ensure the local conversation exists before resolving the message's
    // conversationId. Without this, resolveForLocalStore may fall through and
    // store the message under the server's conversationId, which no open
    // ChatScreen watches.
    await _ensureLocalConversation(event, message);

    final resolved = await _bindToOpenConversation(
      await _messages.resolveForLocalStore(
        message,
        openConversationIds: _openConversationIds,
      ),
    );
    await _messages.upsertMessageDeduped(resolved, alreadyResolved: true);
    await _bumpConversationForMessage(event, resolved);

    if (!resolved.isOutgoing) {
      final conversation = await _resolveLocalConversation(event, resolved);
      final notify = onIncomingMessage;
      if (conversation != null && notify != null) {
        await notify(conversation, resolved);
      }
    }
  }

  /// Guarantees a local conversation row exists for [message] so that
  /// [resolveForLocalStore] can bind the message to the correct local id.
  /// Fuerza el hilo del chat abierto cuando el wa_id coincide (prioridad sobre
  /// otro conversation_id local con el mismo cliente).
  Future<ChatMessage> _bindToOpenConversation(ChatMessage message) async {
    for (final openId in _openConversationIds) {
      final open = await _chats.getConversation(openId);
      if (open != null && _sameWa(open.customerWaId, message.waId)) {
        if (message.conversationId != openId) {
          return message.copyWith(conversationId: openId);
        }
        return message;
      }
    }
    return message;
  }

  static bool _sameWa(String a, String b) {
    final na = a.replaceAll(RegExp(r'[^0-9+]'), '');
    final nb = b.replaceAll(RegExp(r'[^0-9+]'), '');
    return na == nb || na.endsWith(nb) || nb.endsWith(na);
  }

  Future<void> _ensureLocalConversation(
    RealtimeEvent event,
    ChatMessage message,
  ) async {
    var conv = await _chats.getConversation(message.conversationId) ??
        await _chats.findConversationByWaId(message.waId);
    if (conv != null) return;

    // Not found locally — pull fresh conversation list from server.
    await syncConversationsIncremental();
    conv = await _chats.getConversation(message.conversationId) ??
        await _chats.findConversationByWaId(message.waId);
    if (conv != null) return;

    // Use the inline conversation from the WS event as last resort.
    if (event.conversation != null) {
      await _chats.upsertConversationFromServer(event.conversation!);
    }
  }

  Future<Conversation?> _resolveLocalConversation(
    RealtimeEvent event,
    ChatMessage message,
  ) async {
    var conversation = await _chats.findConversationByWaId(message.waId) ??
        await _chats.getConversation(message.conversationId);
    if (conversation != null) return conversation;

    if (event.conversation != null) {
      final eventConv = event.conversation!;
      conversation = await _chats.getConversation(eventConv.id) ??
          await _chats.findConversationByWaId(eventConv.customerWaId);
      if (conversation != null) return conversation;
      return eventConv;
    }
    return null;
  }

  Future<void> _bumpConversationForMessage(
    RealtimeEvent event,
    ChatMessage message,
  ) async {
    var existing = await _chats.getConversation(message.conversationId) ??
        await _chats.findConversationByWaId(message.waId);
    if (existing == null) {
      await syncConversationsIncremental();
      existing = await _chats.getConversation(message.conversationId) ??
          await _chats.findConversationByWaId(message.waId);
    }

    if (existing == null && event.conversation != null) {
      await _chats.upsertConversationFromServer(event.conversation!);
      existing = await _chats.getConversation(event.conversation!.id) ??
          await _chats.findConversationByWaId(event.conversation!.customerWaId);
    }

    if (existing == null) return;

    await _chats.bumpConversationFromMessage(existing, message);
  }

  Future<void> _handleMessageStatus(RealtimeEvent event) async {
    final messageId = event.messageId;
    if (messageId == null) return;

    await _messages.updateStatusDeduped(
      messageId: messageId,
      status: event.status ?? 'delivered',
      deliveredAt: event.deliveredAt,
      readAt: event.readAt,
    );
  }
}
