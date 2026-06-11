import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/conversation_dao.dart';
import 'daos/message_dao.dart';
import 'daos/outbound_queue_dao.dart';
import 'daos/sync_cursor_dao.dart';
import 'tables/conversations.dart';
import 'tables/messages.dart';
import 'tables/outbound_queue.dart';
import 'tables/sync_cursors.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Conversations, Messages, SyncCursors, OutboundQueue],
  daos: [
    ConversationDao,
    MessageDao,
    SyncCursorDao,
    OutboundQueueDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.createTable(outboundQueue);
          }
        },
      );

  Future<void> clearAll() async {
    await transaction(() async {
      await outboundQueueDao.deleteAll();
      await messageDao.deleteAll();
      await conversationDao.deleteAll();
      await syncCursorDao.deleteAll();
    });
  }

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'whatsbot_local.db'));
      return NativeDatabase(file);
    });
  }
}
