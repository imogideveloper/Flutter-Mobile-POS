// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pairing_dao.dart';

// ignore_for_file: type=lint
mixin _$PairingDaoMixin on DatabaseAccessor<AppDatabase> {
  $OutletsTable get outlets => attachedDatabase.outlets;
  $PerangkatTable get perangkat => attachedDatabase.perangkat;
  PairingDaoManager get managers => PairingDaoManager(this);
}

class PairingDaoManager {
  final _$PairingDaoMixin _db;
  PairingDaoManager(this._db);
  $$OutletsTableTableManager get outlets =>
      $$OutletsTableTableManager(_db.attachedDatabase, _db.outlets);
  $$PerangkatTableTableManager get perangkat =>
      $$PerangkatTableTableManager(_db.attachedDatabase, _db.perangkat);
}
