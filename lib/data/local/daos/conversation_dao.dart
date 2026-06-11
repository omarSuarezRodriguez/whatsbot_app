import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/conversations.dart';

part 'conversation_dao.g.dart';

@DriftAccessor(tables: [Conversations])
class ConversationDao extends DatabaseAccessor<AppDatabase>
    with _$ConversationDaoMixin {
  ConversationDao(super.db);

  Stream<List<ConversationEntity>> watchForBusiness(String businessId) {
    return (select(conversations)
          ..where((t) => t.businessId.equals(businessId))
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.lastMessageAt,
                  mode: OrderingMode.desc,
                  nulls: NullsOrder.last,
                ),
            (t) => OrderingTerm.desc(t.updatedAt),
            (t) => OrderingTerm.desc(t.id),
          ]))
        .watch();
  }

  Future<ConversationEntity?> getById(int id) {
    return (select(conversations)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<List<ConversationEntity>> listForBusiness(String businessId) {
    return (select(conversations)
          ..where((t) => t.businessId.equals(businessId)))
        .get();
  }

  Future<void> upsert(ConversationsCompanion companion) async {
    await into(conversations).insertOnConflictUpdate(companion);
  }

  Future<void> upsertAll(List<ConversationsCompanion> rows) async {
    await batch((batch) {
      batch.insertAllOnConflictUpdate(conversations, rows);
    });
  }

  Future<void> updateLastSeen(int conversationId, DateTime seenAt) async {
    await (update(conversations)..where((t) => t.id.equals(conversationId)))
        .write(ConversationsCompanion(lastSeenAt: Value(seenAt)));
  }

  Future<DateTime?> getLastSeen(int conversationId) async {
    final row = await getById(conversationId);
    return row?.lastSeenAt;
  }

  Future<void> deleteAll() async {
    await delete(conversations).go();
  }
}
