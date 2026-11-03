// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fitur_dao.dart';

// ignore_for_file: type=lint
mixin _$FiturDaoMixin on DatabaseAccessor<AppDatabase> {
  $StatusFiturTokoTable get statusFiturToko => attachedDatabase.statusFiturToko;
  $FiturAktifTable get fiturAktif => attachedDatabase.fiturAktif;
  $BatasFiturTable get batasFitur => attachedDatabase.batasFitur;
  FiturDaoManager get managers => FiturDaoManager(this);
}

class FiturDaoManager {
  final _$FiturDaoMixin _db;
  FiturDaoManager(this._db);
  $$StatusFiturTokoTableTableManager get statusFiturToko =>
      $$StatusFiturTokoTableTableManager(
        _db.attachedDatabase,
        _db.statusFiturToko,
      );
  $$FiturAktifTableTableManager get fiturAktif =>
      $$FiturAktifTableTableManager(_db.attachedDatabase, _db.fiturAktif);
  $$BatasFiturTableTableManager get batasFitur =>
      $$BatasFiturTableTableManager(_db.attachedDatabase, _db.batasFitur);
}
