import 'package:drift/drift.dart';

@DataClassName('OutboundQueueEntity')
class OutboundQueue extends Table {
  TextColumn get clientUuid => text()();
  IntColumn get conversationId => integer()();
  IntColumn get tempMessageId => integer()();
  TextColumn get customerWaId => text()();
  TextColumn get body => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts =>
      integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {clientUuid};
}
