import 'package:drift/drift.dart';

@DataClassName('ConversationEntity')
class Conversations extends Table {
  IntColumn get id => integer()();
  TextColumn get businessId => text()();
  TextColumn get customerWaId => text()();
  TextColumn get customerName => text().nullable()();
  TextColumn get lastMessagePreview => text().nullable()();
  DateTimeColumn get lastMessageAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();
  DateTimeColumn get syncedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
