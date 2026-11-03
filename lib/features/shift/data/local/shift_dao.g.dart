// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shift_dao.dart';

// ignore_for_file: type=lint
mixin _$ShiftDaoMixin on DatabaseAccessor<AppDatabase> {
  $OutletsTable get outlets => attachedDatabase.outlets;
  $PerangkatTable get perangkat => attachedDatabase.perangkat;
  $RoleTable get role => attachedDatabase.role;
  $PenggunaTable get pengguna => attachedDatabase.pengguna;
  $ShiftTable get shift => attachedDatabase.shift;
  $KasShiftTable get kasShift => attachedDatabase.kasShift;
  ShiftDaoManager get managers => ShiftDaoManager(this);
}

class ShiftDaoManager {
  final _$ShiftDaoMixin _db;
  ShiftDaoManager(this._db);
  $$OutletsTableTableManager get outlets =>
      $$OutletsTableTableManager(_db.attachedDatabase, _db.outlets);
  $$PerangkatTableTableManager get perangkat =>
      $$PerangkatTableTableManager(_db.attachedDatabase, _db.perangkat);
  $$RoleTableTableManager get role =>
      $$RoleTableTableManager(_db.attachedDatabase, _db.role);
  $$PenggunaTableTableManager get pengguna =>
      $$PenggunaTableTableManager(_db.attachedDatabase, _db.pengguna);
  $$ShiftTableTableManager get shift =>
      $$ShiftTableTableManager(_db.attachedDatabase, _db.shift);
  $$KasShiftTableTableManager get kasShift =>
      $$KasShiftTableTableManager(_db.attachedDatabase, _db.kasShift);
}
