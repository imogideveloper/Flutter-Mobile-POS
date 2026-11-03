// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stok_dao.dart';

// ignore_for_file: type=lint
mixin _$StokDaoMixin on DatabaseAccessor<AppDatabase> {
  $OutletsTable get outlets => attachedDatabase.outlets;
  $StasiunDapurTable get stasiunDapur => attachedDatabase.stasiunDapur;
  $KategoriTable get kategori => attachedDatabase.kategori;
  $SatuanTable get satuan => attachedDatabase.satuan;
  $ProdukTable get produk => attachedDatabase.produk;
  $ProdukVarianTable get produkVarian => attachedDatabase.produkVarian;
  $StokTable get stok => attachedDatabase.stok;
  $BatchStokTable get batchStok => attachedDatabase.batchStok;
  $RoleTable get role => attachedDatabase.role;
  $PenggunaTable get pengguna => attachedDatabase.pengguna;
  $MutasiStokTable get mutasiStok => attachedDatabase.mutasiStok;
  StokDaoManager get managers => StokDaoManager(this);
}

class StokDaoManager {
  final _$StokDaoMixin _db;
  StokDaoManager(this._db);
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
  $$StokTableTableManager get stok =>
      $$StokTableTableManager(_db.attachedDatabase, _db.stok);
  $$BatchStokTableTableManager get batchStok =>
      $$BatchStokTableTableManager(_db.attachedDatabase, _db.batchStok);
  $$RoleTableTableManager get role =>
      $$RoleTableTableManager(_db.attachedDatabase, _db.role);
  $$PenggunaTableTableManager get pengguna =>
      $$PenggunaTableTableManager(_db.attachedDatabase, _db.pengguna);
  $$MutasiStokTableTableManager get mutasiStok =>
      $$MutasiStokTableTableManager(_db.attachedDatabase, _db.mutasiStok);
}
