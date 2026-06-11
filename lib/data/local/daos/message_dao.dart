import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/messages.dart';

part 'message_dao.g.dart';

@DriftAccessor(tables: [Messages])
class MessageDao extends DatabaseAccessor<AppDatabase> with _$MessageDaoMixin {
  MessageDao(super.db);

  Stream<List<MessageEntity>> watchForConversation(int conversationId) {
    return (select(messages)
          ..where((t) => t.conversationId.equals(conversationId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .watch();
  }

  /// Lectura puntual del hilo (misma regla que [watchForChatThread]).
  Future<List<MessageEntity>> listForChatThread(
    int conversationId,
    bool Function(String waId) waMatches,
  ) async {
    final rows = await (select(messages)..orderBy([
          (t) => OrderingTerm.asc(t.createdAt),
          (t) => OrderingTerm.asc(t.id),
        ]))
        .get();
    final byId = <int, MessageEntity>{};
    for (final row in rows) {
      if (row.conversationId == conversationId || waMatches(row.waId)) {
        byId[row.id] = row;
      }
    }
    return byId.values.toList()
      ..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        if (byTime != 0) return byTime;
        return a.id.compareTo(b.id);
      });
  }

  /// Hilo del chat abierto: mensajes del `conversationId` local **o** mismo
  /// `wa_id` bajo otro id (p. ej. conversation_id huérfano del servidor).
  ///
  /// Observa toda la tabla: un insert bajo otro `conversation_id` no dispara
  /// [watchForConversation], pero sí debe actualizar el hilo abierto en vivo.
  Stream<List<MessageEntity>> watchForChatThread(
    int conversationId,
    bool Function(String waId) waMatches,
  ) {
    return (select(messages)..orderBy([
          (t) => OrderingTerm.asc(t.createdAt),
          (t) => OrderingTerm.asc(t.id),
        ]))
        .watch()
        .map((rows) {
      final byId = <int, MessageEntity>{};
      for (final row in rows) {
        if (row.conversationId == conversationId || waMatches(row.waId)) {
          byId[row.id] = row;
        }
      }
      return byId.values.toList()
        ..sort((a, b) {
          final byTime = a.createdAt.compareTo(b.createdAt);
          if (byTime != 0) return byTime;
          return a.id.compareTo(b.id);
        });
    });
  }

  Future<MessageEntity?> getById(int id) {
    return (select(messages)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<MessageEntity?> getByClientUuid(String clientUuid) {
    return (select(messages)
          ..where((t) => t.clientUuid.equals(clientUuid)))
        .getSingleOrNull();
  }

  Future<void> deleteById(int id) async {
    await (delete(messages)..where((t) => t.id.equals(id))).go();
  }

  Future<int> nextTempMessageId() async {
    final expr = messages.id.min();
    final query = selectOnly(messages)..addColumns([expr]);
    final row = await query.getSingleOrNull();
    final minId = row?.read(expr);
    if (minId == null || minId >= 0) return -1;
    return minId - 1;
  }

  Future<int?> maxMessageId(int conversationId) async {
    final expr = messages.id.max();
    final query = selectOnly(messages)
      ..addColumns([expr])
      ..where(messages.conversationId.equals(conversationId));
    final row = await query.getSingleOrNull();
    return row?.read(expr);
  }

  Future<void> upsert(MessagesCompanion companion) async {
    await into(messages).insertOnConflictUpdate(companion);
  }

  Future<void> upsertAll(List<MessagesCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((batch) {
      batch.insertAllOnConflictUpdate(messages, rows);
    });
  }

  Future<void> updateStatus({
    required int messageId,
    required String status,
    DateTime? deliveredAt,
    DateTime? readAt,
  }) async {
    await (update(messages)..where((t) => t.id.equals(messageId))).write(
      MessagesCompanion(
        status: Value(status),
        deliveredAt: deliveredAt == null
            ? const Value.absent()
            : Value(deliveredAt),
        readAt: readAt == null ? const Value.absent() : Value(readAt),
      ),
    );
  }

  Future<void> pruneOldMessages(
    int conversationId, {
    int keep = 500,
  }) async {
    final countExpr = messages.id.count();
    final countQuery = selectOnly(messages)
      ..addColumns([countExpr])
      ..where(messages.conversationId.equals(conversationId));
    final countRow = await countQuery.getSingleOrNull();
    final total = countRow?.read(countExpr) ?? 0;
    if (total <= keep) return;

    final rows = await (select(messages)
          ..where((t) => t.conversationId.equals(conversationId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    if (rows.length <= keep) return;

    final toDelete = rows.skip(keep).map((row) => row.id).toList();
    await batch((batch) {
      for (final id in toDelete) {
        batch.deleteWhere(messages, (t) => t.id.equals(id));
      }
    });
  }

  Future<void> deleteAll() async {
    await delete(messages).go();
  }
}
