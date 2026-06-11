import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/outbound_queue.dart';

part 'outbound_queue_dao.g.dart';

@DriftAccessor(tables: [OutboundQueue])
class OutboundQueueDao extends DatabaseAccessor<AppDatabase>
    with _$OutboundQueueDaoMixin {
  OutboundQueueDao(super.db);

  Future<List<OutboundQueueEntity>> listPending() {
    return (select(outboundQueue)
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<OutboundQueueEntity?> getByClientUuid(String clientUuid) {
    return (select(outboundQueue)
          ..where((t) => t.clientUuid.equals(clientUuid)))
        .getSingleOrNull();
  }

  Future<void> enqueue(OutboundQueueCompanion row) async {
    await into(outboundQueue).insertOnConflictUpdate(row);
  }

  Future<void> remove(String clientUuid) async {
    await (delete(outboundQueue)
          ..where((t) => t.clientUuid.equals(clientUuid)))
        .go();
  }

  Future<void> recordFailure(String clientUuid, String error) async {
    final row = await getByClientUuid(clientUuid);
    if (row == null) return;
    await (update(outboundQueue)
          ..where((t) => t.clientUuid.equals(clientUuid)))
        .write(
      OutboundQueueCompanion(
        attempts: Value(row.attempts + 1),
        lastError: Value(error),
      ),
    );
  }

  Future<void> deleteAll() async {
    await delete(outboundQueue).go();
  }
}
