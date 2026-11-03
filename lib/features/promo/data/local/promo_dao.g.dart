// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'promo_dao.dart';

// ignore_for_file: type=lint
mixin _$PromoDaoMixin on DatabaseAccessor<AppDatabase> {
  $PromoTable get promo => attachedDatabase.promo;
  $OutletsTable get outlets => attachedDatabase.outlets;
  $StasiunDapurTable get stasiunDapur => attachedDatabase.stasiunDapur;
  $KategoriTable get kategori => attachedDatabase.kategori;
  $SatuanTable get satuan => attachedDatabase.satuan;
  $ProdukTable get produk => attachedDatabase.produk;
  $PromoProdukTable get promoProduk => attachedDatabase.promoProduk;
  PromoDaoManager get managers => PromoDaoManager(this);
}

class PromoDaoManager {
  final _$PromoDaoMixin _db;
  PromoDaoManager(this._db);
  $$PromoTableTableManager get promo =>
      $$PromoTableTableManager(_db.attachedDatabase, _db.promo);
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
  $$PromoProdukTableTableManager get promoProduk =>
      $$PromoProdukTableTableManager(_db.attachedDatabase, _db.promoProduk);
}
