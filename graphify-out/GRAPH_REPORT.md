# Graph Report - whatsbot_app  (2026-06-17)

## Corpus Check
- 86 files · ~51,415 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1258 nodes · 1616 edges · 73 communities (67 shown, 6 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 1 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `e04e20d8`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 33|Community 33]]
- [[_COMMUNITY_Community 34|Community 34]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_Community 36|Community 36]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 43|Community 43]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]
- [[_COMMUNITY_Community 48|Community 48]]
- [[_COMMUNITY_Community 49|Community 49]]
- [[_COMMUNITY_Community 50|Community 50]]
- [[_COMMUNITY_Community 51|Community 51]]
- [[_COMMUNITY_Community 52|Community 52]]
- [[_COMMUNITY_Community 53|Community 53]]
- [[_COMMUNITY_Community 54|Community 54]]
- [[_COMMUNITY_Community 55|Community 55]]
- [[_COMMUNITY_Community 56|Community 56]]
- [[_COMMUNITY_Community 57|Community 57]]
- [[_COMMUNITY_Community 58|Community 58]]
- [[_COMMUNITY_Community 59|Community 59]]
- [[_COMMUNITY_Community 60|Community 60]]
- [[_COMMUNITY_Community 61|Community 61]]
- [[_COMMUNITY_Community 62|Community 62]]
- [[_COMMUNITY_Community 63|Community 63]]
- [[_COMMUNITY_Community 64|Community 64]]
- [[_COMMUNITY_Community 65|Community 65]]
- [[_COMMUNITY_Community 66|Community 66]]

## God Nodes (most connected - your core abstractions)
1. `_` - 103 edges
2. `Plan senior: Fix ChatScreen reactivo + persistencia local durable en el teléfono` - 50 edges
3. `AppDatabase` - 14 edges
4. `map` - 8 edges
5. `TestApiClient` - 8 edges
6. `AppDelegate` - 5 edges
7. `DataClass` - 5 edges
8. `ConversationDao` - 5 edges
9. `_` - 5 edges
10. `MessageDao` - 5 edges

## Surprising Connections (you probably didn't know these)
- `ConversationDao` --references--> `AppDatabase`  [EXTRACTED]
  lib/data/local/daos/conversation_dao.dart → lib/data/local/app_database.dart
- `MessageDao` --references--> `AppDatabase`  [EXTRACTED]
  lib/data/local/daos/message_dao.dart → lib/data/local/app_database.dart
- `OutboundQueueDao` --references--> `AppDatabase`  [EXTRACTED]
  lib/data/local/daos/outbound_queue_dao.dart → lib/data/local/app_database.dart
- `SyncCursorDao` --references--> `AppDatabase`  [EXTRACTED]
  lib/data/local/daos/sync_cursor_dao.dart → lib/data/local/app_database.dart

## Import Cycles
- None detected.

## Communities (73 total, 6 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.02
Nodes (87): class ConversationEntity extends, class OutboundQueueEntity extends, class SyncCursorEntity extends, ColumnFilters, ColumnOrderings, ConversationDao, GeneratedColumn, GeneratedDatabase (+79 more)

### Community 1 - "Community 1"
Cohesion: 0.03
Nodes (60): accessToken, approveOrder, _authHeaders, _authorized, businessId, _businessIdKey, businessName, _businessNameKey (+52 more)

### Community 2 - "Community 2"
Cohesion: 0.04
Nodes (53): Completer, ../config/api_config.dart, package:web_socket_channel/io.dart, package:web_socket_channel/status.dart, package:web_socket_channel/web_socket_channel.dart, _ackTimeout, _ackTimeoutTimer, _backoffSeconds (+45 more)

### Community 3 - "Community 3"
Cohesion: 0.05
Nodes (47): @DataClassName, BoolColumn get, DateTimeColumn get, IntColumn get, Set, Table, businessId, Conversations (+39 more)

### Community 4 - "Community 4"
Cohesion: 0.04
Nodes (50): 1.10, 1.11 - Caveman y ponytail added, 1.12, 1.4, 1.5, 1.6 - Chat totalmente funcional, 1.7 - mejora incremental al chat, 1.8 (+42 more)

### Community 5 - "Community 5"
Cohesion: 0.04
Nodes (47): MessageRepository get, order_actions_bar.dart, package:flutter/scheduler.dart, _approveOrder, build, _chats, _connectionSub, _connectivitySub (+39 more)

### Community 6 - "Community 6"
Cohesion: 0.05
Nodes (42): chats_list_screen.dart, apiBaseUrl, ApiConfig, _env, _urls, customers_list_screen.dart, FlutterSecureStorage, menu_editor_screen.dart (+34 more)

### Community 7 - "Community 7"
Cohesion: 0.05
Nodes (38): AudioPlayer, package:audioplayers/audioplayers.dart, package:flutter_local_notifications/flutter_local_notifications.dart, package:flutter/services.dart, _activeConversationId, _appInForeground, _channelId, _channelName (+30 more)

### Community 8 - "Community 8"
Cohesion: 0.05
Nodes (37): Customer, customer_editor_screen.dart, List, ../models/customer.dart, address, businessId, createdAt, customerName (+29 more)

### Community 9 - "Community 9"
Cohesion: 0.05
Nodes (36): ../../models/send_message_result.dart, package:uuid/uuid.dart, _ackOutbound, _api, _bindToOpenConversations, _bumpConversation, _bumpConversationsFromMessages, _db (+28 more)

### Community 10 - "Community 10"
Cohesion: 0.06
Nodes (33): Conversation, conversation.dart, int?, message.dart, businessId, categoria, copyWith, disponible (+25 more)

### Community 11 - "Community 11"
Cohesion: 0.07
Nodes (29): Future, ../repositories/chat_repository.dart, ../repositories/message_repository.dart, static const int, _bindToOpenConversation, _bumpConversationForMessage, _chats, _ensureLocalConversation (+21 more)

### Community 12 - "Community 12"
Cohesion: 0.07
Nodes (27): ../data/repositories/message_repository.dart, ../data/sync/sync_engine.dart, AppServices, chatRepository, clearLocalData, database, hydrateAfterLogin, _hydratedThisSession (+19 more)

### Community 13 - "Community 13"
Cohesion: 0.08
Nodes (25): @pragma, api_client.dart, message_alerts_service.dart, package:firebase_core/firebase_core.dart, package:firebase_messaging/firebase_messaging.dart, package:flutter/foundation.dart, _available, _configureMessaging (+17 more)

### Community 14 - "Community 14"
Cohesion: 0.08
Nodes (25): FormState, _blocked, build, controller, createState, customer, CustomerEditorScreen, _CustomerEditorScreenState (+17 more)

### Community 15 - "Community 15"
Cohesion: 0.09
Nodes (22): ../local/app_database.dart, ../models/conversation.dart, _api, bumpConversationFromMessage, ChatRepository, _conversationsCursorKey, _db, findConversationByWaId (+14 more)

### Community 16 - "Community 16"
Cohesion: 0.09
Nodes (21): IconData, _approve, _askReason, build, createState, _error, _filter, _fmt (+13 more)

### Community 17 - "Community 17"
Cohesion: 0.10
Nodes (15): Any, Bool, Flutter, FlutterAppDelegate, FlutterImplicitEngineBridge, FlutterImplicitEngineDelegate, FlutterSceneDelegate, AppDelegate (+7 more)

### Community 18 - "Community 18"
Cohesion: 0.10
Nodes (20): chat_screen.dart, ChatRepository get, ../data/repositories/chat_repository.dart, ../main.dart, ../models/realtime_event.dart, _chats, _connectionSub, _connectivitySub (+12 more)

### Community 19 - "Community 19"
Cohesion: 0.10
Nodes (20): _asInt, body, channel, clientUuid, compareChronological, conversationId, copyWith, createdAt (+12 more)

### Community 20 - "Community 20"
Cohesion: 0.11
Nodes (18): bool get, package:connectivity_plus/connectivity_plus.dart, _connectivity, ConnectivityService, _hasNetwork, instance, isOnline, _online (+10 more)

### Community 21 - "Community 21"
Cohesion: 0.12
Nodes (15): message_status_ticks.dart, ../models/message.dart, package:flutter/material.dart, package:intl/intl.dart, package:whatsbot_app/screens/login_screen.dart, main, ../theme/whatsapp_theme.dart, build (+7 more)

### Community 22 - "Community 22"
Cohesion: 0.11
Nodes (18): 1.0 - Versión inicial limpia, 1.1, 1.12, 1.2, 1.3, Comparación campo por campo, Consecuencia directa, DESCARTADO (+10 more)

### Community 23 - "Community 23"
Cohesion: 0.15
Nodes (15): emitRealtimeEvent, db, main, testApi, db, emitIncoming, main, notifiedBodies (+7 more)

### Community 24 - "Community 24"
Cohesion: 0.12
Nodes (16): ../data/local/app_database.dart, businessId, Conversation, copyWith, customerName, customerWaId, displayName, fromJson (+8 more)

### Community 25 - "Community 25"
Cohesion: 0.12
Nodes (15): DateTime?, blocked, businessId, copyWith, createdAt, Customer, displayName, fromJson (+7 more)

### Community 26 - "Community 26"
Cohesion: 0.13
Nodes (15): main_shell.dart, build, _businessController, createState, dispose, _error, initState, _loading (+7 more)

### Community 27 - "Community 27"
Cohesion: 0.13
Nodes (15): ../models/menu_item.dart, _addItem, build, createState, _editItem, initState, _items, _load (+7 more)

### Community 28 - "Community 28"
Cohesion: 0.13
Nodes (15): build, _config, createState, _editIntent, initState, _intentMap, IntentsEditorScreen, _IntentsEditorScreenState (+7 more)

### Community 29 - "Community 29"
Cohesion: 0.16
Nodes (13): ChatRepository, ../helpers/test_api_client.dart, TestApiClient, package:whatsbot_app/data/local/app_database.dart, package:whatsbot_app/models/conversation.dart, db, main, repository (+5 more)

### Community 30 - "Community 30"
Cohesion: 0.13
Nodes (14): deleteAll, deleteById, getByClientUuid, getById, listForChatThread, maxMessageId, nextTempMessageId, pruneOldMessages (+6 more)

### Community 31 - "Community 31"
Cohesion: 0.14
Nodes (14): intents_editor_screen.dart, login_screen.dart, BusinessProfile, ../models/business.dart, prompts_editor_screen.dart, createState, initState, _load (+6 more)

### Community 32 - "Community 32"
Cohesion: 0.14
Nodes (14): build, createState, disconnect, init, initState, main, navigatorKey, _onSessionExpired (+6 more)

### Community 33 - "Community 33"
Cohesion: 0.14
Nodes (13): daos/conversation_dao.dart, daos/message_dao.dart, daos/outbound_queue_dao.dart, daos/sync_cursor_dao.dart, dart:io, int? get, clearAll, migration (+5 more)

### Community 34 - "Community 34"
Cohesion: 0.14
Nodes (13): _buildMockClient, client, conversations, failConversations, failSend, login, messagesByConversation, mockHttp (+5 more)

### Community 35 - "Community 35"
Cohesion: 0.14
Nodes (13): db, disconnect, disposeWidgetTree, login, pump, pumpWidget, setUpTestAppServices, tearDownTestAppServices (+5 more)

### Community 36 - "Community 36"
Cohesion: 0.23
Nodes (13): _, @DriftAccessor, @DriftDatabase, _$ConversationDaoMixin, ConversationDao, MessageDao, OutboundQueueDao, SyncCursorDao (+5 more)

### Community 37 - "Community 37"
Cohesion: 0.15
Nodes (12): ../helpers/test_session_storage.dart, ListView, package:whatsbot_app/screens/chat_screen.dart, package:whatsbot_app/widgets/message_bubble.dart, package:whatsbot_app/widgets/typing_indicator.dart, conversation, main, pumpChatScreen (+4 more)

### Community 38 - "Community 38"
Cohesion: 0.15
Nodes (12): accessToken, adminWhatsappNumber, businessId, businessName, fromJson, id, LoginResult, name (+4 more)

### Community 39 - "Community 39"
Cohesion: 0.15
Nodes (12): static const Color, accentGreen, chatBackground, divider, headerGreen, incomingBubble, light, lightGreen (+4 more)

### Community 40 - "Community 40"
Cohesion: 0.17
Nodes (11): dart:convert, package:http/http.dart, package:http/testing.dart, package:shared_preferences/shared_preferences.dart, package:whatsbot_app/services/api_client.dart, clearRefreshToken, hasRefreshToken, main (+3 more)

### Community 41 - "Community 41"
Cohesion: 0.18
Nodes (10): dart:async, ../di/app_services.dart, package:flutter/widgets.dart, Widget, build, child, createState, didChangeAppLifecycleState (+2 more)

### Community 42 - "Community 42"
Cohesion: 0.18
Nodes (10): clearRefreshToken, hasRefreshToken, InMemorySessionStorage, readRefreshToken, _values, writeRefreshToken, map, package:whatsbot_app/services/session_storage.dart (+2 more)

### Community 43 - "Community 43"
Cohesion: 0.29
Nodes (11): Insertable, ConversationEntity, ConversationsCompanion, DataClass, MessageEntity, MessagesCompanion, OutboundQueueCompanion, OutboundQueueEntity (+3 more)

### Community 44 - "Community 44"
Cohesion: 0.24
Nodes (11): ChatScreen, _ChatScreenState, ChatsListScreen, _ChatsListScreenState, OrdersListScreen, _OrdersListScreenState, State, StatefulWidget (+3 more)

### Community 45 - "Community 45"
Cohesion: 0.20
Nodes (9): deleteAll, getById, getLastSeen, listForBusiness, updateLastSeen, upsert, upsertAll, watchForBusiness (+1 more)

### Community 46 - "Community 46"
Cohesion: 0.20
Nodes (9): ../helpers/realtime_test_helper.dart, ../helpers/test_app_services.dart, ListTile, package:whatsbot_app/di/app_services.dart, package:whatsbot_app/screens/chats_list_screen.dart, listTitles, main, seedConversations (+1 more)

### Community 47 - "Community 47"
Cohesion: 0.22
Nodes (8): ../app_database.dart, deleteAll, enqueue, getByClientUuid, listPending, recordFailure, remove, ../tables/outbound_queue.dart

### Community 48 - "Community 48"
Cohesion: 0.22
Nodes (8): MessageRepository, chats, db, engine, main, messages, testApi, SyncEngine

### Community 49 - "Community 49"
Cohesion: 0.22
Nodes (8): ../models/order.dart, PendingOrder, build, busy, onApprove, onReject, order, VoidCallback

### Community 50 - "Community 50"
Cohesion: 0.29
Nodes (5): FlutterEngine, FlutterLocalNotificationsPlugin, GeneratedPluginRegistrant, GeneratedPluginRegistrant, -registerWithRegistry

### Community 51 - "Community 51"
Cohesion: 0.29
Nodes (6): deleteAll, getUpdatedAt, getValue, setCursor, package:drift/drift.dart, ../tables/sync_cursors.dart

### Community 52 - "Community 52"
Cohesion: 0.29
Nodes (7): WhatsBotApp, _Field, _CustomerTile, OrderActionsBar, _InfoRow, _OrderCard, StatelessWidget

### Community 53 - "Community 53"
Cohesion: 0.33
Nodes (5): handle_new_rx_page(), __lldb_init_module(), Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages., SBDebugger, SBFrame

### Community 54 - "Community 54"
Cohesion: 0.60
Nodes (4): commit_message(), git(), main(), Git save: add, commit (versión del README), push.

### Community 55 - "Community 55"
Cohesion: 0.40
Nodes (5): MaterialPageRoute, build, _openChat, _openConversationById, build

### Community 56 - "Community 56"
Cohesion: 0.40
Nodes (4): main, msg, package:flutter_test/flutter_test.dart, package:whatsbot_app/models/message.dart

### Community 57 - "Community 57"
Cohesion: 0.67
Nodes (4): ConversationDaoManager get, ConversationDaoManager, managers, _

### Community 58 - "Community 58"
Cohesion: 0.67
Nodes (4): managers, MessageDaoManager, _, MessageDaoManager get

### Community 59 - "Community 59"
Cohesion: 0.67
Nodes (4): managers, OutboundQueueDaoManager, _, OutboundQueueDaoManager get

### Community 60 - "Community 60"
Cohesion: 0.67
Nodes (4): managers, SyncCursorDaoManager, _, SyncCursorDaoManager get

## Knowledge Gaps
- **872 isolated node(s):** `SBFrame`, `SBDebugger`, `flutter_export_environment.sh script`, `XCTest`, `UserNotifications` (+867 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `_` connect `Community 0` to `Community 33`, `Community 38`, `Community 8`, `Community 42`, `Community 43`, `Community 25`?**
  _High betweenness centrality (0.144) - this node is a cross-community bridge._
- **Why does `map` connect `Community 42` to `Community 0`, `Community 1`, `Community 34`, `Community 6`, `Community 7`, `Community 40`, `Community 28`?**
  _High betweenness centrality (0.050) - this node is a cross-community bridge._
- **Why does `AppDatabase` connect `Community 36` to `Community 33`, `Community 9`, `Community 15`, `Community 48`, `Community 23`, `Community 29`?**
  _High betweenness centrality (0.025) - this node is a cross-community bridge._
- **What connects `Git save: add, commit (versión del README), push.`, `SBFrame`, `SBDebugger` to the rest of the system?**
  _874 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.023255813953488372 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.03278688524590164 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.037037037037037035 - nodes in this community are weakly interconnected._