import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/sync_cursors.dart';

part 'sync_cursor_dao.g.dart';

@DriftAccessor(tables: [SyncCursors])
class SyncCursorDao extends DatabaseAccessor<AppDatabase>
    with _$SyncCursorDaoMixin {
  SyncCursorDao(super.db);

  Future<String?> getValue(String key) async {
    final row = await (select(syncCursors)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<DateTime?> getUpdatedAt(String key) async {
    final row = await (select(syncCursors)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.updatedAt;
  }

  Future<void> setCursor(String key, String value) async {
    await into(syncCursors).insertOnConflictUpdate(
      SyncCursorsCompanion(
        key: Value(key),
        value: Value(value),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> deleteAll() async {
    await delete(syncCursors).go();
  }
}
