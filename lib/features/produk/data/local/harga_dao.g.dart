// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'harga_dao.dart';

// ignore_for_file: type=lint
mixin _$HargaDaoMixin on DatabaseAccessor<AppDatabase> {
  $OutletsTable get outlets => attachedDatabase.outlets;
  $StasiunDapurTable get stasiunDapur => attachedDatabase.stasiunDapur;
  $KategoriTable get kategori => attachedDatabase.kategori;
  $SatuanTable get satuan => attachedDatabase.satuan;
  $ProdukTable get produk => attachedDatabase.produk;
  $ProdukVarianTable get produkVarian => attachedDatabase.produkVarian;
  $HargaOutletTable get hargaOutlet => attachedDatabase.hargaOutlet;
  $HargaGrosirTable get hargaGrosir => attachedDatabase.hargaGrosir;
  $PengaturanOutletTable get pengaturanOutlet =>
      attachedDatabase.pengaturanOutlet;
  HargaDaoManager get managers => HargaDaoManager(this);
}

class HargaDaoManager {
  final _$HargaDaoMixin _db;
  HargaDaoManager(this._db);
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
  $$HargaOutletTableTableManager get hargaOutlet =>
      $$HargaOutletTableTableManager(_db.attachedDatabase, _db.hargaOutlet);
  $$HargaGrosirTableTableManager get hargaGrosir =>
      $$HargaGrosirTableTableManager(_db.attachedDatabase, _db.hargaGrosir);
  $$PengaturanOutletTableTableManager get pengaturanOutlet =>
      $$PengaturanOutletTableTableManager(
        _db.attachedDatabase,
        _db.pengaturanOutlet,
      );
}
