## 1.2





##################################################################
## 1.0 - Versión inicial limpia





##################################################################
## 1.1

## prompt ##

Construye un mapa completo del sistema de mensajería.

No propongas soluciones.

Identifica:

- Componentes involucrados.
- Flujo backend → frontend.
- Flujo frontend → backend.
- Estado.
- Eventos.
- Streams.
- Listeners.
- Suscripciones.
- WebSockets.
- Polling.
- Cache.
- Renderizado UI.

Genera un diagrama ASCII completo.

## resp cursor ##

Sistema de Mensajería — WhatsBot App
Diagrama ASCII Completo
╔══════════════════════════════════════════════════════════════════════════════════════════════╗
║                              WHATSBOT — MAPA DEL SISTEMA DE MENSAJERÍA                      ║
╚══════════════════════════════════════════════════════════════════════════════════════════════╝
┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│  BACKEND / SERVIDOR                                                                          │
│                                                                                              │
│  ┌─────────────────────────┐    ┌──────────────────────────────────────────────────────────┐│
│  │  REST API               │    │  WebSocket Server                                        ││
│  │                         │    │  /whatsbot/ws?token=JWT                                  ││
│  │  GET  /conversations    │    │                                                           ││
│  │  GET  /messages         │    │  ← ping          → pong                                  ││
│  │  POST /messages         │    │  ← pong          ← ping (cliente)                        ││
│  │  POST /mark-read        │    │                                                           ││
│  │  POST /orders           │    │  → connected                                              ││
│  └─────────────────────────┘    │  → message.new                                           ││
│           ↑↓  HTTP              │  → message.status                                        ││
│                                 │  → typing.start / typing.stop                            ││
│                                 │  → conversation.updated / conversation.sync               ││
│                                 │  → order.pending / order.updated                         ││
│                                 │  ← typing.start / typing.stop (cliente)                  ││
│                                 └──────────────────────────────────────────────────────────┘│
│                                              ↑↓  WSS/WS                                     │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
                │ HTTP                                  │ WS
                │                                       │
╔═══════════════╪═══════════════════════════════════════╪══════════════════════════════════════╗
║  CAPA DE SERVICIOS (Singletons)                       │                                      ║
║                                                       │                                      ║
║  ┌───────────────────────────────────────────────────────────────────────────────────────┐   ║
║  │  RealtimeService.instance                                                             │   ║
║  │                                                                                       │   ║
║  │  CONEXIÓN                                                                             │   ║
║  │  ┌────────────────────────────────────────────────────────────────────────────────┐  │   ║
║  │  │  IOWebSocketChannel.connect(wsUrl)     ← web_socket_channel ^3.0.2            │  │   ║
║  │  │  _subscription: StreamSubscription<dynamic>                                    │  │   ║
║  │  │  _onData() ──→ frame router                                                    │  │   ║
║  │  └────────────────────────────────────────────────────────────────────────────────┘  │   ║
║  │                                                                                       │   ║
║  │  ESTADO INTERNO                                                                       │   ║
║  │  _connected: bool            _connecting: bool                                        │   ║
║  │  _backoffSeconds: int        _lastActivityAt: DateTime                                │   ║
║  │  _lastSyncAt: DateTime                                                                │   ║
║  │                                                                                       │   ║
║  │  FRAME ROUTER (_onData)                                                               │   ║
║  │  ┌──────────────────────────────────────────────────────────────────────────────┐    │   ║
║  │  │  frame = JSON.decode                                                         │    │   ║
║  │  │   ├─ "ping"      → channel.sink.add('{"type":"pong"}')                      │    │   ║
║  │  │   ├─ "pong"      → _lastActivityAt = now                                    │    │   ║
║  │  │   ├─ "connected" → _connected=true, syncOnReconnect()                       │    │   ║
║  │  │   └─ *           → persistEvent(event) ──then──→ _events.add(event)         │    │   ║
║  │  └──────────────────────────────────────────────────────────────────────────────┘    │   ║
║  │                                                                                       │   ║
║  │  TIMERS (keepalive)                                                                   │   ║
║  │  ┌──────────────────────────────────────────────────────────────────────────────┐    │   ║
║  │  │  _clientPingTimer  periodic 25s  → channel.sink.add('{"type":"ping"}')      │    │   ║
║  │  │  _watchdogTimer    periodic 45s  → si sin actividad >90s: reconnect         │    │   ║
║  │  │  _reconnectTimer   one-shot exp  → backoff 1→2→4→...→30s                    │    │   ║
║  │  │  _ackTimeoutTimer  one-shot 15s  → si no llega "connected": reconnect       │    │   ║
║  │  └──────────────────────────────────────────────────────────────────────────────┘    │   ║
║  │                                                                                       │   ║
║  │  STREAMS EXPUESTOS (broadcast)                                                        │   ║
║  │  _events:          StreamController<RealtimeEvent>.broadcast()                        │   ║
║  │  _connectionState: StreamController<bool>.broadcast()                                 │   ║
║  │                                                                                       │   ║
║  │  CALLBACKS INYECTADOS (desde AppServices)                                             │   ║
║  │  persistEvent     → SyncEngine.handleRealtimeEvent                                    │   ║
║  │  onReconnectSync  → SyncEngine.syncOnReconnect                                        │   ║
║  │  connectivityOnline → ConnectivityService.isOnline                                    │   ║
║  └───────────────────────────────────────────────────────────────────────────────────────┘   ║
║                                                                                              ║
║  ┌───────────────────────────┐   ┌──────────────────────────────────────────────────────┐   ║
║  │  ApiClient                │   │  ConnectivityService                                 │   ║
║  │                           │   │                                                      │   ║
║  │  http ^1.x                │   │  _subscription: StreamSubscription (OS)              │   ║
║  │  headers: ApiConfig       │   │  _onlineState: StreamController<bool>.broadcast()    │   ║
║  │  (ngrok bypass)           │   │  isOnline: bool                                      │   ║
║  │                           │   │  onBackOnline → AppServices.startRealtimeSession()   │   ║
║  │  getConversations()       │   └──────────────────────────────────────────────────────┘   ║
║  │  getMessages(convId)      │                                                              ║
║  │  sendMessage(...)         │   ┌──────────────────────────────────────────────────────┐   ║
║  │  markConversationRead()   │   │  PushService (FCM)                                   │   ║
║  └───────────────────────────┘   │                                                      │   ║
║                                  │  onMessage → syncEngine.syncMessagesIncremental      │   ║
║                                  │  onMessageOpenedApp → navigate to chat               │   ║
║                                  │  _tokenRefreshSub: StreamSubscription                │   ║
║                                  └──────────────────────────────────────────────────────┘   ║
╚══════════════════════════════════════════════════════════════════════════════════════════════╝
                          │ persistEvent (antes de UI)
                          ▼
╔══════════════════════════════════════════════════════════════════════════════════════════════╗
║  CAPA DE DATOS Y SINCRONIZACIÓN                                                              ║
║                                                                                              ║
║  ┌───────────────────────────────────────────────────────────────────────────────────────┐   ║
║  │  SyncEngine                                                                           │   ║
║  │                                                                                       │   ║
║  │  ESTADO INTERNO                                                                       │   ║
║  │  _openConversationIds: Set<int>     _syncRunning: bool                                │   ║
║  │  _syncChain: Future (serial lock)                                                     │   ║
║  │                                                                                       │   ║
║  │  handleRealtimeEvent(event)                                                           │   ║
║  │  ┌──────────────────────────────────────────────────────────────────────────────┐    │   ║
║  │  │  type == message.new        → messageRepo.upsertMessageDeduped()            │    │   ║
║  │  │                               chatRepo.bumpConversation()                   │    │   ║
║  │  │                               onIncomingMessage() → MessageAlertsService    │    │   ║
║  │  │  type == message.status     → messageRepo.updateStatusDeduped()             │    │   ║
║  │  │  type == conversation.*     → chatRepo.upsertConversationFromServer()       │    │   ║
║  │  └──────────────────────────────────────────────────────────────────────────────┘    │   ║
║  │                                                                                       │   ║
║  │  syncOnReconnect()   → flushOutboundQueue + syncConversations + syncOpenChats         │   ║
║  │  syncMessagesIncremental(force)  → REST si TTL expirado (2min) o force               │   ║
║  │  syncConversationsIncremental()  → REST, cursor: ISO timestamp                       │   ║
║  │                                                                                       │   ║
║  │  CALLBACK EXPUESTO                                                                    │   ║
║  │  onIncomingMessage: Function(ChatMessage)  → wired → MessageAlertsService            │   ║
║  └───────────────────────────────────────────────────────────────────────────────────────┘   ║
║         ↑↓                              ↑↓                                                   ║
║  ┌─────────────────────────┐   ┌─────────────────────────────────────────────────────────┐   ║
║  │  MessageRepository      │   │  ChatRepository                                         │   ║
║  │                         │   │                                                         │   ║
║  │  sendMessage()          │   │  watchConversations() → Stream<List<Conversation>>      │   ║
║  │   ├ insert optimista    │   │  syncConversationsIncremental()                         │   ║
║  │   ├ OutboundQueue.enq() │   │  upsertConversationFromServer()                         │   ║
║  │   ├ POST /messages      │   │  bumpConversation()                                     │   ║
║  │   └ _ackOutbound()      │   └─────────────────────────────────────────────────────────┘   ║
║  │                         │            ↑↓                                                    ║
║  │  watchMessages(id)      │                                                                  ║
║  │   → Stream<List<Msg>>   │                                                                  ║
║  │                         │                                                                  ║
║  │  syncTtl: 2min          │                                                                  ║
║  │  retentionPerChat: 500  │                                                                  ║
║  └─────────────────────────┘                                                                  ║
║         ↑↓                                                                                   ║
╚══════════════════════════════════════════════════════════════════════════════════════════════╝
                          │ DAOs / Drift
                          ▼
╔══════════════════════════════════════════════════════════════════════════════════════════════╗
║  PERSISTENCIA LOCAL — SQLite (Drift)   whatsbot_local.db   schema v2                        ║
║                                                                                              ║
║  ┌───────────────────────┐  ┌───────────────────────┐  ┌────────────────────────────────┐  ║
║  │  Messages             │  │  Conversations        │  │  OutboundQueue                 │  ║
║  │                       │  │                       │  │                                │  ║
║  │  PK: id (int)         │  │  PK: id               │  │  PK: clientUuid (UUID)         │  ║
║  │  clientUuid (UUID)    │  │  businessId           │  │  conversationId                │  ║
║  │  conversationId       │  │  waId                 │  │  body                          │  ║
║  │  body                 │  │  lastMessageAt        │  │  attempts                      │  ║
║  │  status               │  │  lastSeenAt           │  │  tempId (int negativo)         │  ║
║  │  isOutgoing           │  │  previewText          │  └────────────────────────────────┘  ║
║  │  timestamp            │  └───────────────────────┘                                       ║
║  └───────────────────────┘                            ┌────────────────────────────────┐   ║
║                                                        │  SyncCursors                  │   ║
║  DAOs (Drift .watch() → Stream reactivo):              │                               │   ║
║  MessageDao.watchForConversation(id) ──────────────┐  │  conversations: ISO ts         │   ║
║  ConversationDao.watchForBusiness(bId) ────────────┤  │  messages:{id}: lastMsgId      │   ║
║                                                    │  │  messages_sync_at:{id}: ts     │   ║
║  Ambos usan SELECT ... WHERE → emit on change      │  └────────────────────────────────┘   ║
╚════════════════════════════════════════════════════╪═════════════════════════════════════════╝
                                                     │ Drift Streams
                                                     ▼
╔══════════════════════════════════════════════════════════════════════════════════════════════╗
║  CAPA UI — Flutter (sin Provider/Riverpod/Bloc)                                              ║
║                                                                                              ║
║  ┌───────────────────────────────────────────────────────────────────────────────────────┐   ║
║  │  ChatsListScreen (StatefulWidget)                                                     │   ║
║  │                                                                                       │   ║
║  │  ESTADO LOCAL                                                                         │   ║
║  │  _refreshing: bool    _error: String?    _wasConnected: bool                          │   ║
║  │                                                                                       │   ║
║  │  SUSCRIPCIONES (initState → dispose)                                                  │   ║
║  │  _realtimeSub:    realtimeService.events          StreamSubscription<RealtimeEvent>   │   ║
║  │  _connectionSub:  realtimeService.connectionState StreamSubscription<bool>            │   ║
║  │  _connectivitySub: connectivityService.onlineState StreamSubscription<bool>           │   ║
║  │                                                                                       │   ║
║  │  RENDERIZADO                                                                          │   ║
║  │  StreamBuilder<List<Conversation>>(                                                   │   ║
║  │    stream: chatRepository.watchConversations(),      ← Drift reactivo                 │   ║
║  │    builder: (ctx, snap) → ListView                                                    │   ║
║  │      └─ ListTile(preview, badge unread, hora, icono offline)                          │   ║
║  │  )                                                                                    │   ║
║  │                                                                                       │   ║
║  │  onTap(conv) → preload getCachedMessages() → Navigator.push(ChatScreen)               │   ║
║  └───────────────────────────────────────────────────────────────────────────────────────┘   ║
║                                                                                              ║
║  ┌───────────────────────────────────────────────────────────────────────────────────────┐   ║
║  │  ChatScreen (StatefulWidget)                                                          │   ║
║  │                                                                                       │   ║
║  │  ESTADO LOCAL                                                                         │   ║
║  │  _displayMessages: List<ChatMessage>   ← capa de presentación reconciliada            │   ║
║  │  _peerTyping: bool                                                                    │   ║
║  │  _refreshing: bool    _sending: bool    _orderBusy: bool                              │   ║
║  │  _pendingOrder: PendingOrder?                                                         │   ║
║  │                                                                                       │   ║
║  │  SUSCRIPCIONES (initState → dispose)                                                  │   ║
║  │  _messagesSub:     watchMessages(id)              ← Drift Stream                      │   ║
║  │  _realtimeSub:     realtimeService.events         ← WS Stream                         │   ║
║  │  _connectionSub:   realtimeService.connectionState                                    │   ║
║  │  _connectivitySub: connectivityService.onlineState                                    │   ║
║  │  _inputController.addListener(_onInputChanged)   ← TextField                          │   ║
║  │                                                                                       │   ║
║  │  TIMERS LOCALES                                                                       │   ║
║  │  _wsFallbackTimer  periodic 30s → sync REST si WS caído + online                     │   ║
║  │  _typingStopTimer  one-shot 2s  → typing.stop al servidor                             │   ║
║  │                                                                                       │   ║
║  │  HANDLERS DE STREAMS                                                                  │   ║
║  │  ┌──────────────────────────────────────────────────────────────────────────────┐    │   ║
║  │  │  _onMessagesFromStore(List<ChatMessage>)  ← Drift watch                      │    │   ║
║  │  │   → _applyStoreSnapshot() → _reconcileWithStore()                            │    │   ║
║  │  │   → setState si snapshot cambió                                              │    │   ║
║  │  │                                                                              │    │   ║
║  │  │  _onRealtimeEvent(RealtimeEvent)  ← WS events stream                        │    │   ║
║  │  │   ├─ message.new    → _mergeMessageIntoDisplay() → setState + auto-scroll   │    │   ║
║  │  │   ├─ message.status → _applyStatusUpdate() → setState                       │    │   ║
║  │  │   ├─ typing.start   → _peerTyping=true → setState                           │    │   ║
║  │  │   ├─ typing.stop    → _peerTyping=false → setState                          │    │   ║
║  │  │   ├─ order.*        → _pendingOrder update → setState                       │    │   ║
║  │  │   └─ conversation.* → _refresh()                                            │    │   ║
║  │  └──────────────────────────────────────────────────────────────────────────────┘    │   ║
║  │                                                                                       │   ║
║  │  ENVÍO (_send)                                                                        │   ║
║  │  ┌──────────────────────────────────────────────────────────────────────────────┐    │   ║
║  │  │  messageRepository.sendMessage(convId, waId, body)                          │    │   ║
║  │  │   → insertar optimista en SQLite (tempId negativo, status: pending)         │    │   ║
║  │  │   → OutboundQueue.enqueue(clientUuid)                                       │    │   ║
║  │  │   → POST /whatsbot/messages                                                 │    │   ║
║  │  │   → éxito: _ackOutbound (borra temp, inserta real)                          │    │   ║
║  │  │   → fallo: queued=true → flushOutboundQueue al reconectar                   │    │   ║
║  │  └──────────────────────────────────────────────────────────────────────────────┘    │   ║
║  │                                                                                       │   ║
║  │  TYPING (_onInputChanged)                                                             │   ║
║  │   → texto no vacío → WS send { type: typing.start, conversation_id }                 │   ║
║  │   → reset _typingStopTimer 2s                                                         │   ║
║  │   → timer dispara → WS send { type: typing.stop }                                    │   ║
║  │                                                                                       │   ║
║  │  RENDERIZADO (build)                                                                  │   ║
║  │  ┌──────────────────────────────────────────────────────────────────────────────┐    │   ║
║  │  │  ListView.builder(reverse: true)                                            │    │   ║
║  │  │   ├─ índice 0 (si _peerTyping): TypingIndicator                            │    │   ║
║  │  │   └─ índices n: MessageBubble(key: ValueKey(clientUuid ?? 'msg-$id'))      │    │   ║
║  │  │        ├─ isOutgoing → alinear derecha / izquierda                         │    │   ║
║  │  │        ├─ isAdmin == false → color bot                                     │    │   ║
║  │  │        └─ MessageStatusTicks(status)                                       │    │   ║
║  │  │              pending   → ⏱                                                 │    │   ║
║  │  │              sent      → ✓                                                 │    │   ║
║  │  │              delivered → ✓✓                                                │    │   ║
║  │  │              read      → ✓✓ (azul)                                        │    │   ║
║  │  └──────────────────────────────────────────────────────────────────────────────┘    │   ║
║  └───────────────────────────────────────────────────────────────────────────────────────┘   ║
╚══════════════════════════════════════════════════════════════════════════════════════════════╝
══════════════════════════════════════════════════════════════════════════════════════════════
  FLUJOS PRINCIPALES
══════════════════════════════════════════════════════════════════════════════════════════════
  BACKEND → FRONTEND (mensaje entrante)
  ─────────────────────────────────────
  Servidor WS
    │  JSON frame: { type: "message.new", payload: {...} }
    ▼
  RealtimeService._onData()
    │  decode + route
    ▼
  [persistEvent] SyncEngine.handleRealtimeEvent()          ← ESCRIBE EN SQLite PRIMERO
    │  messageRepo.upsertMessageDeduped()
    │  chatRepo.bumpConversation()
    │  onIncomingMessage() ──→ MessageAlertsService (sonido/notif si no está en este chat)
    ▼
  [emitAfterPersist] _events.add(RealtimeEvent)
    │
    ├──→ ChatScreen._onRealtimeEvent()
    │      _mergeMessageIntoDisplay() → setState() → ListView rebuild
    │      auto-scroll si _isNearBottom()
    │      markConversationRead() → POST /mark-read
    │
    └──→ ChatsListScreen._onRealtimeEvent()
           bump preview + badge unread
  SQLite (Drift) ──watch()──→ ChatScreen._onMessagesFromStore()
                                _applyStoreSnapshot() → _reconcileWithStore() → setState()
  FRONTEND → BACKEND (mensaje saliente)
  ──────────────────────────────────────
  ChatScreen._send()
    │  messageRepository.sendMessage(convId, waId, body)
    │   ├─ 1. SQLite insert optimista (tempId negativo, status: pending)
    │   │        → Drift watch emite → UI muestra burbuja con ⏱
    │   ├─ 2. OutboundQueue.enqueue(clientUuid)
    │   └─ 3. ApiClient.sendMessage() → POST /whatsbot/messages
    │           ├─ Éxito: _ackOutbound()
    │           │           delete tempId, upsert servidor ID
    │           │           remove OutboundQueue entry
    │           │           Drift watch emite → UI actualiza burbuja ✓
    │           └─ Fallo red: devuelve SendMessageResult(queued: true)
    │                          Cola persiste → flushOutboundQueue al reconectar
  Servidor procesa → envía WS message.status (delivered/read)
    → ChatScreen._applyStatusUpdate() → setState() → ticks ✓✓ / ✓✓(azul)
  RECONEXIÓN / RESILIENCIA
  ─────────────────────────
  WS cae
    │
    ├─ _watchdogTimer 45s detecta > 90s sin actividad → _forceReconnect()
    ├─ onError / onDone → _scheduleReconnect() backoff exp 1→30s
    └─ AppLifecycleObserver (app resume) → realtimeService.onAppResumed()
                                            reset backoff, reconnect, sync forzado
  WS reconecta → "connected" frame
    → syncOnReconnect()
        ├─ flushOutboundQueue() (mensajes cola offline)
        ├─ syncConversationsIncremental() (REST, cursor ISO)
        └─ syncMessagesIncremental() por cada chat abierto
  Red vuelve (ConnectivityService)
    → onBackOnline → AppServices.startRealtimeSession()
  ChatScreen: _wsFallbackTimer periodic 30s
    → si WS caído + online → syncMessagesIncremental(force: true)
══════════════════════════════════════════════════════════════════════════════════════════════
  SHARED PREFERENCES (sesión)
  ─────────────────────────────
  whatsbot_access_token    whatsbot_business_id    whatsbot_business_name
══════════════════════════════════════════════════════════════════════════════════════════════
  WIRING (AppServices.init)
  ──────────────────────────
  AppDatabase ─────────────────────────────────── DAOs
       │
       ├── MessageRepository ◄──► MessageDao
       ├── ChatRepository    ◄──► ConversationDao
       └── SyncEngine ◄──────────────────────────── ambos repos
              │
              └── callbacks:
                   RealtimeService.persistEvent       = SyncEngine.handleRealtimeEvent
                   RealtimeService.onReconnectSync    = SyncEngine.syncOnReconnect
                   RealtimeService.connectivityOnline = ConnectivityService.isOnline
                   SyncEngine.onIncomingMessage       = MessageAlertsService.handle
                   ConnectivityService.onBackOnline   = AppServices.startRealtimeSession
Resumen de la arquitectura
Dimensión	Mecanismo
Estado global
Singletons + SQLite (Drift) — sin Provider/Riverpod/Bloc
Estado UI
_displayMessages, _peerTyping, flags locales en StatefulWidget
Tiempo real
WebSocket (web_socket_channel) con auth por query param JWT
Streams
2 broadcast controllers (WS events, connectionState) + 2 Drift watches
Suscripciones
4 por ChatScreen, 3 por ChatsListScreen, 1 global WS, 1 OS connectivity
Persistencia
SQLite Drift: Messages, Conversations, OutboundQueue, SyncCursors
Cache sesión
SharedPreferences solo para JWT y businessId
Polling
Solo fallback (timer 30s en ChatScreen cuando WS caído + online)
Offline
Inserción optimista + OutboundQueue; flush al reconectar
Reconexión WS
Backoff exponencial 1→30s + watchdog 90s + resume lifecycle
Deduplicación
clientUuid (UUID v4) para prevenir duplicados entre REST y WS
Renderizado
ListView.builder(reverse: true) + ValueKey(clientUuid) para reconciliación de keys


#####################################################################
## 1.2

## prompt ##

Tengo este síntoma:

Mientras estoy dentro de ChatScreen, llegan mensajes al sistema pero la UI no se actualiza automáticamente.

Busca exclusivamente dónde podría romperse la actualización visual.

Empieza desde ChatScreen y recorre hacia atrás:

ChatScreen
← Streams
← SQLite Drift
← SyncEngine
← RealtimeService
← WebSocket
← Backend

Identifica el punto más probable de fallo.

No expliques toda la arquitectura.
Solo busca el bug.

## resp cursor ##


Demuestra esta hipótesis.

No quiero posibilidades.

Quiero evidencia completa.

Traza exactamente:

1. Dónde se construye el frame WebSocket.
2. Qué JSON exacto envía el backend.
3. Qué función serializa el evento.
4. Qué estructura exacta recibe Flutter.
5. Qué campos espera RealtimeEvent.fromJson().
6. Compara ambos objetos campo por campo.

Entrega:

- JSON real enviado.
- JSON esperado.
- Diferencias.
- Evidencia archivo:línea.

Al final responde:

CONFIRMADO
o
DESCARTADO

No propongas fixes todavía.



## resp cursor ##

Tengo todo. La evidencia es completa y definitiva.

---

## Comparación campo por campo

### JSON real enviado por el backend

**Función:** `build_message_new_event` — `C:\Users\Usuario\Desktop\whatsbot\services\realtime_service.py:69–74`

```python
{
    "type": "message.new",
    "message": { ...serialize_message(msg)... },
    "conversation": { ...serialize_conversation(conv)... }
}
```

Enviado en `_emit_local` → `ws.send_text(payload)` — línea **197** y **232**. Sin ningún wrapper `payload`.

---

### JSON esperado por Flutter

**Función:** `RealtimeEvent.fromJson` — `lib/models/realtime_event.dart:29–49`

```dart
{
    "type":            json['type'],
    "message":         json['message'],      // ← lee top-level
    "conversation":    json['conversation'], // ← lee top-level
    "message_id":      json['message_id'],
    "conversation_id": json['conversation_id'],
    "status":          json['status'],
    "delivered_at":    json['delivered_at'],
    "read_at":         json['read_at']
}
```

---

### Tabla comparativa campo por campo

| Campo | Backend envía | Flutter lee | ¿Coincide? |
|---|---|---|---|
| `type` | `"message.new"` (top-level) | `json['type']` | **SÍ** |
| `message` | top-level `dict` | `json['message']` | **SÍ** |
| `conversation` | top-level `dict` | `json['conversation']` | **SÍ** |
| `payload` | **NO existe en el frame real** | no se lee | **N/A** |

---

## DESCARTADO

La hipótesis `payload` wrapper queda **descartada**. El backend nunca envía un campo `payload` en los frames de mensajes — la documentación estaba desactualizada o era especulativa.

**El JSON real enviado es plano y coincide exactamente con lo que `RealtimeEvent.fromJson` espera.**

---

## Consecuencia directa

El bug **no está** en el parsing del JSON. La cadena `RealtimeService → RealtimeEvent.fromJson` funciona correctamente. El punto de rotura está en otro eslabón. Los candidatos que siguen en pie son:

1. `SyncEngine._handleMessageNew` — ¿hay un guard de `conversationId` que filtra el mensaje antes de insertarlo?
2. `MessageDao.watchForConversation` — ¿el `conversationId` del mensaje insertado coincide con el de la pantalla abierta?
3. `ChatScreen._onRealtimeEvent` — ¿`_messageBelongsToChat()` falla silenciosamente?

¿Continúo trazando desde `SyncEngine` hacia adentro?



## prompt ##

Tenemos una hipótesis descartada:

- RealtimeEvent.fromJson funciona correctamente.

Ahora continúa la traza exclusivamente desde:

SyncEngine._handleMessageNew

Sigue el flujo completo hasta que el mensaje debería aparecer en pantalla.

Para cada salto identifica:

1. Entrada recibida.
2. Condiciones de filtrado (guards, ifs, returns).
3. Transformaciones.
4. Inserciones en SQLite.
5. Streams observados.
6. Renderizado final.

Detente inmediatamente cuando encuentres el primer punto donde un mensaje válido podría ser descartado.

No propongas soluciones.

Quiero el primer punto de fallo más probable con evidencia archivo:línea.


###################################################
