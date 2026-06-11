// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outbound_queue_dao.dart';

// ignore_for_file: type=lint
mixin _$OutboundQueueDaoMixin on DatabaseAccessor<AppDatabase> {
  $OutboundQueueTable get outboundQueue => attachedDatabase.outboundQueue;
  OutboundQueueDaoManager get managers => OutboundQueueDaoManager(this);
}

class OutboundQueueDaoManager {
  final _$OutboundQueueDaoMixin _db;
  OutboundQueueDaoManager(this._db);
  $$OutboundQueueTableTableManager get outboundQueue =>
      $$OutboundQueueTableTableManager(_db.attachedDatabase, _db.outboundQueue);
}
