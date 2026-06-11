import 'package:drift/drift.dart';

@DataClassName('MessageEntity')
class Messages extends Table {
  IntColumn get id => integer()();
  IntColumn get conversationId => integer()();
  TextColumn get direction => text()();
  TextColumn get body => text()();
  TextColumn get waId => text()();
  BoolColumn get isAdmin =>
      boolean().withDefault(const Constant(false))();
  TextColumn get channel =>
      text().withDefault(const Constant('whatsapp'))();
  TextColumn get status =>
      text().withDefault(const Constant('delivered'))();
  DateTimeColumn get deliveredAt => dateTime().nullable()();
  DateTimeColumn get readAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get clientUuid => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
