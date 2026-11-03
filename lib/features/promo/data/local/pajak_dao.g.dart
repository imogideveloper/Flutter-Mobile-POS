// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pajak_dao.dart';

// ignore_for_file: type=lint
mixin _$PajakDaoMixin on DatabaseAccessor<AppDatabase> {
  $PajakTable get pajak => attachedDatabase.pajak;
  $OutletsTable get outlets => attachedDatabase.outlets;
  $StasiunDapurTable get stasiunDapur => attachedDatabase.stasiunDapur;
  $KategoriTable get kategori => attachedDatabase.kategori;
  $SatuanTable get satuan => attachedDatabase.satuan;
  $ProdukTable get produk => attachedDatabase.produk;
  $ProdukPajakTable get produkPajak => attachedDatabase.produkPajak;
  PajakDaoManager get managers => PajakDaoManager(this);
}

class PajakDaoManager {
  final _$PajakDaoMixin _db;
  PajakDaoManager(this._db);
  $$PajakTableTableManager get pajak =>
      $$PajakTableTableManager(_db.attachedDatabase, _db.pajak);
  $$OutletsTableTableManager get outlets =>
      $$OutletsTableTableManager(_db.attachedDatabase, _db.outlets);
  $$StasiunDapurTableTableManager get stasiunDapur =>
      $$StasiunDapurTableTableManager(_db.attachedDatabase, _db.stasiunDapur);
  $$KategoriTableTableManager get kategori =>
      $$KategoriTableTableManager(_db.attachedDatabase, _db.kategori);
  $$SatuanTableTableManager get satuan =>
      $$SatuanTableTableManager(_db.attachedDatabase, _db.satuan);
  $$ProdukTableTableManager get produk =>
      $$ProdukTableTableManager(_db.attachedDatabase, _db.produk);
  $$ProdukPajakTableTableManager get produkPajak =>
      $$ProdukPajakTableTableManager(_db.attachedDatabase, _db.produkPajak);
}
