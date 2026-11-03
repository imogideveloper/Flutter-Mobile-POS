// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tipe_order_dao.dart';

// ignore_for_file: type=lint
mixin _$TipeOrderDaoMixin on DatabaseAccessor<AppDatabase> {
  $TipeOrderTable get tipeOrder => attachedDatabase.tipeOrder;
  $PajakTable get pajak => attachedDatabase.pajak;
  $TipeOrderPajakTable get tipeOrderPajak => attachedDatabase.tipeOrderPajak;
  TipeOrderDaoManager get managers => TipeOrderDaoManager(this);
}

class TipeOrderDaoManager {
  final _$TipeOrderDaoMixin _db;
  TipeOrderDaoManager(this._db);
  $$TipeOrderTableTableManager get tipeOrder =>
      $$TipeOrderTableTableManager(_db.attachedDatabase, _db.tipeOrder);
  $$PajakTableTableManager get pajak =>
      $$PajakTableTableManager(_db.attachedDatabase, _db.pajak);
  $$TipeOrderPajakTableTableManager get tipeOrderPajak =>
      $$TipeOrderPajakTableTableManager(
        _db.attachedDatabase,
        _db.tipeOrderPajak,
      );
}
