// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pengguna_dao.dart';

// ignore_for_file: type=lint
mixin _$PenggunaDaoMixin on DatabaseAccessor<AppDatabase> {
  $RoleTable get role => attachedDatabase.role;
  $PenggunaTable get pengguna => attachedDatabase.pengguna;
  $RoleIzinSyncTable get roleIzinSync => attachedDatabase.roleIzinSync;
  PenggunaDaoManager get managers => PenggunaDaoManager(this);
}

class PenggunaDaoManager {
  final _$PenggunaDaoMixin _db;
  PenggunaDaoManager(this._db);
  $$RoleTableTableManager get role =>
      $$RoleTableTableManager(_db.attachedDatabase, _db.role);
  $$PenggunaTableTableManager get pengguna =>
      $$PenggunaTableTableManager(_db.attachedDatabase, _db.pengguna);
  $$RoleIzinSyncTableTableManager get roleIzinSync =>
      $$RoleIzinSyncTableTableManager(_db.attachedDatabase, _db.roleIzinSync);
}
