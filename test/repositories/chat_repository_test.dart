import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatsbot_app/data/local/app_database.dart';
import 'package:whatsbot_app/data/repositories/chat_repository.dart';
import 'package:whatsbot_app/models/conversation.dart';

import '../helpers/test_api_client.dart';

void main() {
  late AppDatabase db;
  late TestApiClient testApi;
  late ChatRepository repository;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    testApi = TestApiClient(
      conversations: [
        {
          'id': 1,
          'business_id': 'default',
          'customer_wa_id': '+5491111111111',
          'customer_name': 'Cliente',
          'last_message_preview': 'Hola',
          'last_message_at': '2026-06-01T12:00:00Z',
          'updated_at': '2026-06-01T12:00:00Z',
        },
      ],
    );
    await testApi.login();
    repository = ChatRepository(db, testApi.client);
  });

  tearDown(() async {
    await db.close();
  });

  test('refreshFromApi hidrata conversaciones en SQLite', () async {
    final list = await repository.refreshFromApi();
    expect(list, hasLength(1));

    final watched = await repository.watchConversations().first;
    expect(watched.single.displayName, 'Cliente');
  });

  test('upsertConversation preserva lastSeenAt local', () async {
    await repository.refreshFromApi();
    final seenAt = DateTime.utc(2026, 6, 1, 13);
    await repository.markSeen(1, seenAt);

    await repository.upsertConversation(
      Conversation(
        id: 1,
        businessId: 'default',
        customerWaId: '+5491111111111',
        customerName: 'Otro nombre',
        lastMessagePreview: 'Nuevo',
        lastMessageAt: DateTime.utc(2026, 6, 1, 14),
        updatedAt: DateTime.utc(2026, 6, 1, 14),
      ),
    );

    final row = await repository.getConversation(1);
    expect(row?.lastSeenAt?.toUtc(), seenAt.toUtc());
    expect(row?.customerName, 'Otro nombre');
  });

  test('mergeWithLocal conserva preview local si el timestamp empata', () {
    final local = Conversation(
      id: 1,
      businessId: 'default',
      customerWaId: '+5491111111111',
      lastMessagePreview: 'Envío del dueño',
      lastMessageAt: DateTime.utc(2026, 6, 1, 15),
      updatedAt: DateTime.utc(2026, 6, 1, 15),
    );
    final sameTime = Conversation(
      id: 1,
      businessId: 'default',
      customerWaId: '+5491111111111',
      lastMessagePreview: 'Preview viejo del servidor',
      lastMessageAt: DateTime.utc(2026, 6, 1, 15),
      updatedAt: DateTime.utc(2026, 6, 1, 15),
    );

    final merged = repository.mergeWithLocal(local, sameTime);
    expect(merged.lastMessagePreview, 'Envío del dueño');
    expect(merged.lastMessageAt?.toUtc(), DateTime.utc(2026, 6, 1, 15));
  });

  test('mergeWithLocal no retrocede lastMessageAt', () {
    final local = Conversation(
      id: 1,
      businessId: 'default',
      customerWaId: '+5491111111111',
      lastMessagePreview: 'Reciente',
      lastMessageAt: DateTime.utc(2026, 6, 1, 15),
      updatedAt: DateTime.utc(2026, 6, 1, 15),
    );
    final stale = Conversation(
      id: 1,
      businessId: 'default',
      customerWaId: '+5491111111111',
      lastMessagePreview: 'Viejo',
      lastMessageAt: DateTime.utc(2026, 6, 1, 10),
      updatedAt: DateTime.utc(2026, 6, 1, 10),
    );

    final merged = repository.mergeWithLocal(local, stale);
    expect(merged.lastMessageAt?.toUtc(), DateTime.utc(2026, 6, 1, 15));
    expect(merged.lastMessagePreview, 'Reciente');
  });

  // ── Tests de persistencia durable ────────────────────────────────────────

  test('refreshFromApi con lista vacía no borra conversaciones locales', () async {
    // Seed 2 local conversations.
    await repository.upsertConversation(
      Conversation(
        id: 1,
        businessId: 'default',
        customerWaId: '+5491111111111',
        customerName: 'Local A',
        lastMessageAt: DateTime.utc(2026, 6, 1, 12),
        updatedAt: DateTime.utc(2026, 6, 1, 12),
      ),
    );
    await repository.upsertConversation(
      Conversation(
        id: 2,
        businessId: 'default',
        customerWaId: '+5492222222222',
        customerName: 'Local B',
        lastMessageAt: DateTime.utc(2026, 6, 1, 13),
        updatedAt: DateTime.utc(2026, 6, 1, 13),
      ),
    );

    // API returns empty list — sync is additive, nothing is deleted.
    final emptyApi = TestApiClient(conversations: []);
    await emptyApi.login();
    final emptyRepo = ChatRepository(db, emptyApi.client);
    await emptyRepo.refreshFromApi();

    final local = await repository.watchConversations().first;
    expect(local, hasLength(2));
  });

  test('refreshFromApi con servidor que omite conv existente no la borra', () async {
    // Seed 2 local conversations.
    await repository.upsertConversation(
      Conversation(
        id: 10,
        businessId: 'default',
        customerWaId: '+5491110000001',
        customerName: 'Conv antigua',
        updatedAt: DateTime.utc(2026, 5, 1),
      ),
    );
    await repository.upsertConversation(
      Conversation(
        id: 11,
        businessId: 'default',
        customerWaId: '+5491110000002',
        customerName: 'Conv nueva',
        updatedAt: DateTime.utc(2026, 6, 1),
      ),
    );

    // API only returns conv 11 (omits conv 10).
    final partialApi = TestApiClient(
      conversations: [
        {
          'id': 11,
          'business_id': 'default',
          'customer_wa_id': '+5491110000002',
          'customer_name': 'Conv nueva',
          'last_message_at': '2026-06-01T00:00:00Z',
          'updated_at': '2026-06-01T00:00:00Z',
        },
      ],
    );
    await partialApi.login();
    final partialRepo = ChatRepository(db, partialApi.client);
    await partialRepo.refreshFromApi();

    final local = await repository.watchConversations().first;
    final ids = local.map((c) => c.id).toList();
    expect(ids, containsAll([10, 11]));
  });

  test('upsertConversationFromServer con servidor viejo no retrocede preview local',
      () async {
    // Seed with a recent local state (optimistic send bump).
    await repository.upsertConversation(
      Conversation(
        id: 5,
        businessId: 'default',
        customerWaId: '+5491115555555',
        lastMessagePreview: 'Mensaje reciente del dueño',
        lastMessageAt: DateTime.utc(2026, 6, 5, 15),
        updatedAt: DateTime.utc(2026, 6, 5, 15),
      ),
    );

    // Server sends stale conversation.updated event.
    await repository.upsertConversationFromServer(
      Conversation(
        id: 5,
        businessId: 'default',
        customerWaId: '+5491115555555',
        lastMessagePreview: 'Preview viejo del servidor',
        lastMessageAt: DateTime.utc(2026, 6, 5, 10),
        updatedAt: DateTime.utc(2026, 6, 5, 10),
      ),
    );

    final conv = await repository.getConversation(5);
    // mergeWithLocal protects the local preview because local lastMessageAt > server.
    expect(conv?.lastMessagePreview, 'Mensaje reciente del dueño');
    expect(conv?.lastMessageAt?.toUtc(), DateTime.utc(2026, 6, 5, 15));
  });
}
