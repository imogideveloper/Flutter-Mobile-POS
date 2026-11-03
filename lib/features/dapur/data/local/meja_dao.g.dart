// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meja_dao.dart';

// ignore_for_file: type=lint
mixin _$MejaDaoMixin on DatabaseAccessor<AppDatabase> {
  $OutletsTable get outlets => attachedDatabase.outlets;
  $MejaTable get meja => attachedDatabase.meja;
  MejaDaoManager get managers => MejaDaoManager(this);
}

class MejaDaoManager {
  final _$MejaDaoMixin _db;
  MejaDaoManager(this._db);
  $$OutletsTableTableManager get outlets =>
      $$OutletsTableTableManager(_db.attachedDatabase, _db.outlets);
  $$MejaTableTableManager get meja =>
      $$MejaTableTableManager(_db.attachedDatabase, _db.meja);
}
