import 'package:drift/drift.dart';

@DataClassName('SyncCursorEntity')
class SyncCursors extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
