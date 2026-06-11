import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsbot_app/data/local/app_database.dart';
import 'package:whatsbot_app/data/repositories/chat_repository.dart';
import 'package:whatsbot_app/data/repositories/message_repository.dart';
import 'package:whatsbot_app/data/sync/sync_engine.dart';
import 'package:whatsbot_app/di/app_services.dart';
import 'package:whatsbot_app/models/conversation.dart';
import 'package:whatsbot_app/models/message.dart';
import 'package:whatsbot_app/models/realtime_event.dart';
import 'package:whatsbot_app/services/realtime_service.dart';

import '../helpers/test_api_client.dart';

/// Verifica que el teléfono actúa como archivo local durable:
/// - WS events persisten en SQLite correctamente.
/// - clearAll() (logout) es el único wipe permitido.
void main() {
  late AppDatabase db;
  late TestApiClient testApi;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    realtimeService.disableSocketForTesting = true;

    testApi = TestApiClient(
      conversations: [
        {
          'id': 1,
          'business_id': 'default',
          'customer_wa_id': '+5491234567890',
          'customer_name': 'Durable Client',
          'last_message_preview': 'Hola',
          'last_message_at': DateTime.utc(2026, 6, 5, 10).toIso8601String(),
          'updated_at': DateTime.utc(2026, 6, 5, 10).toIso8601String(),
        },
      ],
    );
    await testApi.login();

    db = AppDatabase.forTesting(NativeDatabase.memory());
    AppServices.database = db;
    AppServices.chatRepository = ChatRepository(db, testApi.client);
    AppServices.messageRepository = MessageRepository(db, testApi.client);
    AppServices.syncEngine = SyncEngine(
      AppServices.chatRepository,
      AppServices.messageRepository,
    );
    realtimeService.persistEvent = AppServices.syncEngine.handleRealtimeEvent;
    realtimeService.connectivityOnline = () => true;
  });

  tearDown(() async {
    await realtimeService.disconnect();
    await db.close();
  });

  test('WS message.new persiste fila en SQLite vía SyncEngine', () async {
    // Ensure conversation exists so resolveForLocalStore can bind by wa_id.
    await AppServices.chatRepository.upsertConversation(
      Conversation(
        id: 1,
        businessId: 'default',
        customerWaId: '+5491234567890',
        customerName: 'Durable Client',
        updatedAt: DateTime.utc(2026, 6, 5, 10),
      ),
    );

    await realtimeService.debugEmitEvent(
      RealtimeEvent(
        type: 'message.new',
        message: ChatMessage(
          id: 42,
          conversationId: 1,
          direction: 'incoming',
          body: 'Persistencia confirmada',
          waId: '+5491234567890',
          isAdmin: false,
          channel: 'whatsapp',
          status: 'delivered',
          createdAt: DateTime.utc(2026, 6, 5, 11),
        ),
      ),
    );

    final row = await db.messageDao.getById(42);
    expect(row, isNotNull);
    expect(row!.body, 'Persistencia confirmada');
    expect(row.conversationId, 1);
  });

  test('WS message.status persiste actualización de estado en SQLite', () async {
    await AppServices.chatRepository.upsertConversation(
      Conversation(
        id: 1,
        businessId: 'default',
        customerWaId: '+5491234567890',
        updatedAt: DateTime.utc(2026, 6, 5, 10),
      ),
    );
    await AppServices.messageRepository.upsertMessage(
      ChatMessage(
        id: 55,
        conversationId: 1,
        direction: 'outgoing',
        body: 'Saliente',
        waId: '+5491234567890',
        isAdmin: true,
        channel: 'whatsapp',
        status: 'sent',
        createdAt: DateTime.utc(2026, 6, 5, 11),
      ),
    );

    await realtimeService.debugEmitEvent(
      RealtimeEvent(
        type: 'message.status',
        messageId: 55,
        status: 'delivered',
        deliveredAt: DateTime.utc(2026, 6, 5, 11, 1),
      ),
    );

    final row = await db.messageDao.getById(55);
    expect(row?.status, 'delivered');
  });

  test('clearAll (logout) borra todas las tablas — único wipe permitido', () async {
    // Seed data.
    await AppServices.chatRepository.upsertConversation(
      Conversation(
        id: 1,
        businessId: 'default',
        customerWaId: '+5491234567890',
        updatedAt: DateTime.utc(2026, 6, 5, 10),
      ),
    );
    await AppServices.messageRepository.upsertMessage(
      ChatMessage(
        id: 1,
        conversationId: 1,
        direction: 'incoming',
        body: 'Debe borrarse en logout',
        waId: '+5491234567890',
        isAdmin: false,
        channel: 'whatsapp',
        status: 'delivered',
        createdAt: DateTime.utc(2026, 6, 5, 11),
      ),
    );

    final beforeConvs =
        await AppServices.chatRepository.watchConversations().first;
    final beforeMsgs =
        await AppServices.messageRepository.watchMessages(1).first;
    expect(beforeConvs, isNotEmpty);
    expect(beforeMsgs, isNotEmpty);

    // Simulate logout.
    await db.clearAll();

    final afterConvs =
        await AppServices.chatRepository.watchConversations().first;
    final afterMsgs =
        await AppServices.messageRepository.watchMessages(1).first;
    expect(afterConvs, isEmpty);
    expect(afterMsgs, isEmpty);
  });

  test(
    'datos locales sobreviven sync que no devuelve la conversación (no wipe)',
    () async {
      // Seed local conversation and message not present in API.
      await AppServices.chatRepository.upsertConversation(
        Conversation(
          id: 99,
          businessId: 'default',
          customerWaId: '+5499999999999',
          customerName: 'Historial antiguo',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await AppServices.messageRepository.upsertMessage(
        ChatMessage(
          id: 200,
          conversationId: 99,
          direction: 'incoming',
          body: 'Mensaje antiguo',
          waId: '+5499999999999',
          isAdmin: false,
          channel: 'whatsapp',
          status: 'delivered',
          createdAt: DateTime.utc(2026, 1, 1, 10),
        ),
      );

      // Sync conversations — API only returns conv 1, not conv 99.
      await AppServices.syncEngine.syncConversationsIncremental();

      // Local history must survive.
      final msgs =
          await AppServices.messageRepository.watchMessages(99).first;
      expect(msgs.any((m) => m.body == 'Mensaje antiguo'), isTrue);

      // Verify conv 99 still in watchConversations.
      final convs =
          await AppServices.chatRepository.watchConversations().first;
      expect(convs.any((c) => c.id == 99), isTrue);
    },
  );
}
