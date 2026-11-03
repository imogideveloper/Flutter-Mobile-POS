// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pelanggan_dao.dart';

// ignore_for_file: type=lint
mixin _$PelangganDaoMixin on DatabaseAccessor<AppDatabase> {
  $LevelMemberTable get levelMember => attachedDatabase.levelMember;
  $PelangganTable get pelanggan => attachedDatabase.pelanggan;
  $OutletsTable get outlets => attachedDatabase.outlets;
  $PerangkatTable get perangkat => attachedDatabase.perangkat;
  $RoleTable get role => attachedDatabase.role;
  $PenggunaTable get pengguna => attachedDatabase.pengguna;
  $ShiftTable get shift => attachedDatabase.shift;
  $TipeOrderTable get tipeOrder => attachedDatabase.tipeOrder;
  $MejaTable get meja => attachedDatabase.meja;
  $TransaksiTable get transaksi => attachedDatabase.transaksi;
  $RiwayatPoinTable get riwayatPoin => attachedDatabase.riwayatPoin;
  $AturanPoinTable get aturanPoin => attachedDatabase.aturanPoin;
  PelangganDaoManager get managers => PelangganDaoManager(this);
}

class PelangganDaoManager {
  final _$PelangganDaoMixin _db;
  PelangganDaoManager(this._db);
  $$LevelMemberTableTableManager get levelMember =>
      $$LevelMemberTableTableManager(_db.attachedDatabase, _db.levelMember);
  $$PelangganTableTableManager get pelanggan =>
      $$PelangganTableTableManager(_db.attachedDatabase, _db.pelanggan);
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
  $$TipeOrderTableTableManager get tipeOrder =>
      $$TipeOrderTableTableManager(_db.attachedDatabase, _db.tipeOrder);
  $$MejaTableTableManager get meja =>
      $$MejaTableTableManager(_db.attachedDatabase, _db.meja);
  $$TransaksiTableTableManager get transaksi =>
      $$TransaksiTableTableManager(_db.attachedDatabase, _db.transaksi);
  $$RiwayatPoinTableTableManager get riwayatPoin =>
      $$RiwayatPoinTableTableManager(_db.attachedDatabase, _db.riwayatPoin);
  $$AturanPoinTableTableManager get aturanPoin =>
      $$AturanPoinTableTableManager(_db.attachedDatabase, _db.aturanPoin);
}
