// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'produk_dao.dart';

// ignore_for_file: type=lint
mixin _$ProdukDaoMixin on DatabaseAccessor<AppDatabase> {
  $OutletsTable get outlets => attachedDatabase.outlets;
  $StasiunDapurTable get stasiunDapur => attachedDatabase.stasiunDapur;
  $KategoriTable get kategori => attachedDatabase.kategori;
  $SatuanTable get satuan => attachedDatabase.satuan;
  $ProdukTable get produk => attachedDatabase.produk;
  $ProdukVarianTable get produkVarian => attachedDatabase.produkVarian;
  ProdukDaoManager get managers => ProdukDaoManager(this);
}

class ProdukDaoManager {
  final _$ProdukDaoMixin _db;
  ProdukDaoManager(this._db);
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
  $$ProdukVarianTableTableManager get produkVarian =>
      $$ProdukVarianTableTableManager(_db.attachedDatabase, _db.produkVarian);
}
