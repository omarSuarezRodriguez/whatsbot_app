import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsbot_app/data/local/app_database.dart';
import 'package:whatsbot_app/data/repositories/message_repository.dart';
import 'package:whatsbot_app/models/conversation.dart';
import 'package:whatsbot_app/models/message.dart';

import '../helpers/test_api_client.dart';

// ignore_for_file: avoid_print

void main() {
  late AppDatabase db;
  late TestApiClient testApi;
  late MessageRepository repository;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    testApi = TestApiClient();
    await testApi.login();
    repository = MessageRepository(db, testApi.client);
  });

  tearDown(() async {
    await db.close();
  });

  test('sendMessage encola mensaje optimista si la API falla', () async {
    testApi.failSend = true;

    final result = await repository.sendMessage(
      conversationId: 1,
      customerWaId: '+5491111111111',
      body: 'Hola offline',
    );

    expect(result.queued, isTrue);
    expect(result.message.status, 'pending');
    expect(result.message.id, lessThan(0));

    final pending = await db.outboundQueueDao.listPending();
    expect(pending, hasLength(1));
    expect(pending.first.body, 'Hola offline');

    final local = await repository.watchMessages(1).first;
    expect(local, hasLength(1));
    expect(local.first.body, 'Hola offline');
  });

  test('sendMessage confirma mensaje y vacía cola si la API responde', () async {
    final result = await repository.sendMessage(
      conversationId: 1,
      customerWaId: '+5491111111111',
      body: 'Hola online',
    );

    expect(result.queued, isFalse);
    expect(result.message.id, greaterThan(0));

    final pending = await db.outboundQueueDao.listPending();
    expect(pending, isEmpty);

    final local = await repository.watchMessages(1).first;
    expect(local.single.body, 'Hola online');
    expect(local.single.id, result.message.id);
  });

  test('sendMessage conserva conversationId local si el servidor difiere', () async {
    final altApi = TestApiClient(sendConversationId: 99);
    await altApi.login();
    final altDb = AppDatabase.forTesting(NativeDatabase.memory());
    final altRepo = MessageRepository(altDb, altApi.client);

    final result = await altRepo.sendMessage(
      conversationId: 1,
      customerWaId: '+5491111111111',
      body: 'Hola con conv distinta',
    );

    expect(result.queued, isFalse);
    expect(result.message.conversationId, 1);

    final local = await altRepo.watchMessages(1).first;
    expect(local.single.body, 'Hola con conv distinta');
    expect(local.single.conversationId, 1);

    final otherConv = await altRepo.watchMessages(99).first;
    expect(otherConv, isEmpty);

    await altDb.close();
  });

  test('upsertMessageDeduped conserva conversationId tras WS con otro id', () async {
    final altApi = TestApiClient(sendConversationId: 99);
    await altApi.login();
    final altDb = AppDatabase.forTesting(NativeDatabase.memory());
    final altRepo = MessageRepository(altDb, altApi.client);

    final sendResult = await altRepo.sendMessage(
      conversationId: 1,
      customerWaId: '+5491111111111',
      body: 'Tras WS',
    );
    expect(sendResult.message.conversationId, 1);

    // Simula message.new del WS: mismo id, otra conversación, status delivered.
    await altRepo.upsertMessageDeduped(
      sendResult.message.copyWith(
        conversationId: 99,
        status: 'delivered',
        deliveredAt: DateTime.utc(2026, 6, 5, 14),
      ),
    );

    final local = await altRepo.watchMessages(1).first;
    expect(local.single.body, 'Tras WS');
    expect(local.single.conversationId, 1);
    expect(local.single.status, 'delivered');

    final otherConv = await altRepo.watchMessages(99).first;
    expect(otherConv, isEmpty);

    await altDb.close();
  });

  test('flushOutboundQueue reenvía mensajes pendientes', () async {
    testApi.failSend = true;
    await repository.sendMessage(
      conversationId: 1,
      customerWaId: '+5491111111111',
      body: 'Pendiente',
    );

    testApi.failSend = false;
    await repository.flushOutboundQueue();

    final pending = await db.outboundQueueDao.listPending();
    expect(pending, isEmpty);

    final local = await repository.watchMessages(1).first;
    expect(local.single.id, greaterThan(0));
    expect(local.single.status, 'sent');
  });

  test('needsSyncFromApi true sin caché y false tras sync reciente', () async {
    expect(await repository.needsSyncFromApi(1), isTrue);

    await repository.upsertMessage(
      ChatMessage(
        id: 1,
        conversationId: 1,
        direction: 'incoming',
        body: 'Hola',
        waId: '+5491111111111',
        isAdmin: false,
        channel: 'whatsapp',
        status: 'delivered',
        createdAt: DateTime.utc(2026, 1, 1, 12),
      ),
    );
    await db.syncCursorDao.setCursor('messages_sync_at:1', '1');

    expect(await repository.needsSyncFromApi(1), isFalse);
  });

  test(
    'resolveForLocalStore no acepta conversation_id servidor sin wa_id coincidente',
    () async {
      final now = DateTime.utc(2026, 6, 5, 12);
      await db.conversationDao.upsert(
        ConversationsCompanion(
          id: const Value(1),
          businessId: const Value('default'),
          customerWaId: const Value('+5491111111111'),
          updatedAt: Value(now),
          syncedAt: Value(now),
        ),
      );
      await db.conversationDao.upsert(
        ConversationsCompanion(
          id: const Value(99),
          businessId: const Value('default'),
          customerWaId: const Value('+5498888888888'),
          updatedAt: Value(now),
          syncedAt: Value(now),
        ),
      );

      final resolved = await repository.resolveForLocalStore(
        ChatMessage(
          id: 502,
          conversationId: 99,
          direction: 'incoming',
          body: 'No debe ir a conv 99',
          waId: '+5491111111111',
          isAdmin: false,
          channel: 'whatsapp',
          status: 'delivered',
          createdAt: now,
        ),
      );

      expect(resolved.conversationId, 1);
    },
  );

  test('resolveForLocalStore prefiere chat abierto con mismo wa_id', () async {
    final now = DateTime.utc(2026, 6, 5, 12);
    await db.conversationDao.upsert(
      ConversationsCompanion(
        id: const Value(1),
        businessId: const Value('default'),
        customerWaId: const Value('+5491111111111'),
        updatedAt: Value(now),
        syncedAt: Value(now),
      ),
    );
    await db.conversationDao.upsert(
      ConversationsCompanion(
        id: const Value(99),
        businessId: const Value('default'),
        customerWaId: const Value('+5491111111111'),
        updatedAt: Value(now),
        syncedAt: Value(now),
      ),
    );

    final resolved = await repository.resolveForLocalStore(
      ChatMessage(
        id: 503,
        conversationId: 99,
        direction: 'incoming',
        body: 'Al chat abierto',
        waId: '+5491111111111',
        isAdmin: false,
        channel: 'whatsapp',
        status: 'delivered',
        createdAt: now,
      ),
      openConversationIds: const [1],
    );

    expect(resolved.conversationId, 1);
  });

  test('watchChatMessages emite en vivo al insertar mensaje huérfano con mismo wa_id',
      () async {
    final now = DateTime.utc(2026, 6, 5, 12);
    await db.conversationDao.upsert(
      ConversationsCompanion(
        id: const Value(1),
        businessId: const Value('default'),
        customerWaId: const Value('+5491111111111'),
        updatedAt: Value(now),
        syncedAt: Value(now),
      ),
    );
    await db.messageDao.upsert(
      MessagesCompanion(
        id: const Value(1),
        conversationId: const Value(1),
        direction: const Value('incoming'),
        body: const Value('Historial local'),
        waId: const Value('+5491111111111'),
        isAdmin: const Value(false),
        channel: const Value('whatsapp'),
        status: const Value('delivered'),
        createdAt: Value(now),
      ),
    );

    final conv = Conversation(
      id: 1,
      businessId: 'default',
      customerWaId: '+5491111111111',
      updatedAt: now,
    );
    final stream = repository.watchChatMessages(conv);
    final emissions = <List<ChatMessage>>[];
    final sub = stream.listen(emissions.add);
    await Future<void>.delayed(Duration.zero);
    expect(emissions.last.single.body, 'Historial local');

    await db.messageDao.upsert(
      MessagesCompanion(
        id: const Value(900),
        conversationId: const Value(99),
        direction: const Value('incoming'),
        body: const Value('Huérfano en vivo'),
        waId: const Value('+5491111111111'),
        isAdmin: const Value(false),
        channel: const Value('whatsapp'),
        status: const Value('delivered'),
        createdAt: Value(now.add(const Duration(minutes: 1))),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(emissions.last.map((m) => m.body), contains('Huérfano en vivo'));
    await sub.cancel();
  });

  test('watchChatMessages incluye mensajes con mismo wa_id en otro conversation_id',
      () async {
    final now = DateTime.utc(2026, 6, 5, 12);
    await db.conversationDao.upsert(
      ConversationsCompanion(
        id: const Value(1),
        businessId: const Value('default'),
        customerWaId: const Value('+5491111111111'),
        updatedAt: Value(now),
        syncedAt: Value(now),
      ),
    );
    await db.messageDao.upsert(
      MessagesCompanion(
        id: const Value(700),
        conversationId: const Value(99),
        direction: const Value('incoming'),
        body: const Value('Mismo wa, otro id'),
        waId: const Value('+5491111111111'),
        isAdmin: const Value(false),
        channel: const Value('whatsapp'),
        status: const Value('delivered'),
        createdAt: Value(now),
      ),
    );

    final local = await repository
        .watchChatMessages(
          Conversation(
            id: 1,
            businessId: 'default',
            customerWaId: '+5491111111111',
            updatedAt: now,
          ),
        )
        .first;

    expect(local.single.body, 'Mismo wa, otro id');
  });

  test('resolveForLocalStore prefiere hilo local por wa_id', () async {
    final now = DateTime.utc(2026, 6, 5, 12);
    await db.conversationDao.upsert(
      ConversationsCompanion(
        id: const Value(1),
        businessId: const Value('default'),
        customerWaId: const Value('+5491111111111'),
        updatedAt: Value(now),
        syncedAt: Value(now),
      ),
    );
    await db.conversationDao.upsert(
      ConversationsCompanion(
        id: const Value(99),
        businessId: const Value('default'),
        customerWaId: const Value('+5498888888888'),
        updatedAt: Value(now),
        syncedAt: Value(now),
      ),
    );

    final resolved = await repository.resolveForLocalStore(
      ChatMessage(
        id: 501,
        conversationId: 99,
        direction: 'incoming',
        body: 'WS con id servidor distinto',
        waId: '+5491111111111',
        isAdmin: false,
        channel: 'whatsapp',
        status: 'delivered',
        createdAt: now,
      ),
    );

    expect(resolved.conversationId, 1);
  });

  test(
    'upsertMessageDeduped re-homologa conversationId cuando alreadyResolved',
    () async {
      final now = DateTime.utc(2026, 6, 5, 12);
      await db.conversationDao.upsert(
        ConversationsCompanion(
          id: const Value(1),
          businessId: const Value('default'),
          customerWaId: const Value('+5491111111111'),
          updatedAt: Value(now),
          syncedAt: Value(now),
        ),
      );
      await db.messageDao.upsert(
        MessagesCompanion(
          id: const Value(800),
          conversationId: const Value(99),
          direction: const Value('incoming'),
          body: const Value('Huérfano'),
          waId: const Value('+5491111111111'),
          isAdmin: const Value(false),
          channel: const Value('whatsapp'),
          status: const Value('delivered'),
          createdAt: Value(now),
        ),
      );

      await repository.upsertMessageDeduped(
        ChatMessage(
          id: 800,
          conversationId: 1,
          direction: 'incoming',
          body: 'Huérfano',
          waId: '+5491111111111',
          isAdmin: false,
          channel: 'whatsapp',
          status: 'delivered',
          createdAt: now,
        ),
        alreadyResolved: true,
      );

      final row = await db.messageDao.getById(800);
      expect(row?.conversationId, 1);
    },
  );

  test('upsertMessageDeduped omite mensajes idénticos', () async {
    final message = ChatMessage(
      id: 50,
      conversationId: 1,
      direction: 'incoming',
      body: 'Hola',
      waId: '+5491111111111',
      isAdmin: false,
      channel: 'whatsapp',
      status: 'delivered',
      createdAt: DateTime.utc(2026, 1, 1, 12),
    );

    expect(await repository.upsertMessageDeduped(message), isTrue);
    expect(await repository.upsertMessageDeduped(message), isFalse);
  });

  // ── Tests de persistencia durable ────────────────────────────────────────

  test('retentionPerChat es 10000 (política de archivo durable)', () {
    expect(MessageRepository.retentionPerChat, 10000);
  });

  test('pruneOldMessages conserva los mensajes más recientes según el límite',
      () async {
    // Seed 7 messages with sequential createdAt; prune to keep=5.
    final base = DateTime.utc(2026, 1, 1, 12);
    for (var i = 1; i <= 7; i++) {
      await db.messageDao.upsert(
        MessagesCompanion(
          id: Value(i),
          conversationId: const Value(1),
          direction: const Value('incoming'),
          body: Value('Msg $i'),
          waId: const Value('+5491111111111'),
          isAdmin: const Value(false),
          channel: const Value('whatsapp'),
          status: const Value('delivered'),
          createdAt: Value(base.add(Duration(minutes: i))),
        ),
      );
    }

    await db.messageDao.pruneOldMessages(1, keep: 5);

    final remaining = await db.messageDao.watchForConversation(1).first;
    expect(remaining, hasLength(5));
    // The 5 most recent (highest id / latest createdAt) survive.
    expect(remaining.map((r) => r.id), containsAll([3, 4, 5, 6, 7]));
    expect(remaining.map((r) => r.id), isNot(contains(1)));
    expect(remaining.map((r) => r.id), isNot(contains(2)));
  });

  test(
      'getCachedChatMessages incluye huérfano con mismo wa_id tras upsert bajo otro conversation_id',
      () async {
    final now = DateTime.utc(2026, 6, 5, 12);
    await db.conversationDao.upsert(
      ConversationsCompanion(
        id: const Value(1),
        businessId: const Value('default'),
        customerWaId: const Value('+5491111111111'),
        updatedAt: Value(now),
        syncedAt: Value(now),
      ),
    );
    // Mensaje local normal bajo conv 1.
    await db.messageDao.upsert(
      MessagesCompanion(
        id: const Value(10),
        conversationId: const Value(1),
        direction: const Value('incoming'),
        body: const Value('Normal'),
        waId: const Value('+5491111111111'),
        isAdmin: const Value(false),
        channel: const Value('whatsapp'),
        status: const Value('delivered'),
        createdAt: Value(now),
      ),
    );
    // Huérfano: mismo wa_id pero almacenado bajo conv 99 (id servidor).
    await db.messageDao.upsert(
      MessagesCompanion(
        id: const Value(900),
        conversationId: const Value(99),
        direction: const Value('incoming'),
        body: const Value('Huérfano cacheado'),
        waId: const Value('+5491111111111'),
        isAdmin: const Value(false),
        channel: const Value('whatsapp'),
        status: const Value('delivered'),
        createdAt: Value(now.add(const Duration(minutes: 1))),
      ),
    );

    final conv = Conversation(
      id: 1,
      businessId: 'default',
      customerWaId: '+5491111111111',
      updatedAt: now,
    );
    final cached = await repository.getCachedChatMessages(conv);

    expect(cached.map((m) => m.body), containsAll(['Normal', 'Huérfano cacheado']));
  });

  test('normalizeIncomingChronology coloca WS con created_at viejo al final', () async {
    await repository.upsertMessage(
      ChatMessage(
        id: 180,
        conversationId: 1,
        direction: 'incoming',
        body: 'Último visible',
        waId: '+5491111111111',
        isAdmin: false,
        channel: 'whatsapp',
        status: 'delivered',
        createdAt: DateTime.utc(2026, 6, 10, 18),
      ),
    );

    final incoming = ChatMessage(
      id: 181,
      conversationId: 1,
      direction: 'incoming',
      body: 'Nuevo en vivo',
      waId: '+5491111111111',
      isAdmin: false,
      channel: 'whatsapp',
      status: 'delivered',
      createdAt: DateTime.utc(2026, 6, 1, 8),
    );

    final normalized = await repository.normalizeIncomingChronology(incoming);
    expect(normalized.id, 181);
    expect(
      normalized.createdAt.isAfter(DateTime.utc(2026, 6, 10, 18)),
      isTrue,
    );

    await repository.upsertMessage(normalized, alreadyResolved: true);
    final thread = await repository.getCachedChatMessages(
      Conversation(
        id: 1,
        businessId: 'default',
        customerWaId: '+5491111111111',
        updatedAt: DateTime.utc(2026, 6, 10, 18),
      ),
    );
    expect(thread.last.id, 181);
    expect(thread.last.body, 'Nuevo en vivo');
  });

  test('normalizeIncomingChronology coloca respuesta bot con created_at viejo al final',
      () async {
    await repository.upsertMessage(
      ChatMessage(
        id: 180,
        conversationId: 1,
        direction: 'incoming',
        body: 'Cliente',
        waId: '+5491111111111',
        isAdmin: false,
        channel: 'whatsapp',
        status: 'delivered',
        createdAt: DateTime.utc(2026, 6, 10, 18),
      ),
    );

    final botReply = ChatMessage(
      id: 182,
      conversationId: 1,
      direction: 'outgoing',
      body: 'Respuesta bot',
      waId: '+5491111111111',
      isAdmin: false,
      channel: 'whatsapp',
      status: 'delivered',
      createdAt: DateTime.utc(2026, 6, 1, 8),
    );

    final normalized = await repository.normalizeIncomingChronology(botReply);
    expect(normalized.createdAt.isAfter(DateTime.utc(2026, 6, 10, 18)), isTrue);

    await repository.upsertMessage(normalized, alreadyResolved: true);
    final thread = await repository.getCachedChatMessages(
      Conversation(
        id: 1,
        businessId: 'default',
        customerWaId: '+5491111111111',
        updatedAt: DateTime.utc(2026, 6, 10, 18),
      ),
    );
    expect(thread.last.body, 'Respuesta bot');
  });

  test('refreshFromApi incremental con API vacía no borra mensajes locales',
      () async {
    // Seed a local message.
    await repository.upsertMessage(
      ChatMessage(
        id: 1,
        conversationId: 1,
        direction: 'incoming',
        body: 'Local durable',
        waId: '+5491111111111',
        isAdmin: false,
        channel: 'whatsapp',
        status: 'delivered',
        createdAt: DateTime.utc(2026, 6, 5, 10),
      ),
    );

    // API returns no messages for this conversation.
    testApi.messagesByConversation[1] = [];
    await repository.refreshFromApi(1, incremental: true);

    final local = await repository.watchMessages(1).first;
    expect(local, hasLength(1));
    expect(local.first.body, 'Local durable');
  });
}
