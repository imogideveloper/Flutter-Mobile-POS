// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaksi_dao.dart';

// ignore_for_file: type=lint
mixin _$TransaksiDaoMixin on DatabaseAccessor<AppDatabase> {
  $OutletsTable get outlets => attachedDatabase.outlets;
  $PerangkatTable get perangkat => attachedDatabase.perangkat;
  $RoleTable get role => attachedDatabase.role;
  $PenggunaTable get pengguna => attachedDatabase.pengguna;
  $ShiftTable get shift => attachedDatabase.shift;
  $TipeOrderTable get tipeOrder => attachedDatabase.tipeOrder;
  $MejaTable get meja => attachedDatabase.meja;
  $TransaksiTable get transaksi => attachedDatabase.transaksi;
  $StasiunDapurTable get stasiunDapur => attachedDatabase.stasiunDapur;
  $KategoriTable get kategori => attachedDatabase.kategori;
  $SatuanTable get satuan => attachedDatabase.satuan;
  $ProdukTable get produk => attachedDatabase.produk;
  $ProdukVarianTable get produkVarian => attachedDatabase.produkVarian;
  $ItemTransaksiTable get itemTransaksi => attachedDatabase.itemTransaksi;
  $GrupModifierTable get grupModifier => attachedDatabase.grupModifier;
  $ModifierTable get modifier => attachedDatabase.modifier;
  $ItemTransaksiModifierTable get itemTransaksiModifier =>
      attachedDatabase.itemTransaksiModifier;
  $MetodeBayarTable get metodeBayar => attachedDatabase.metodeBayar;
  $PembayaranTable get pembayaran => attachedDatabase.pembayaran;
  $PajakTable get pajak => attachedDatabase.pajak;
  $TransaksiPajakTable get transaksiPajak => attachedDatabase.transaksiPajak;
  $PromoTable get promo => attachedDatabase.promo;
  $TransaksiPromoTable get transaksiPromo => attachedDatabase.transaksiPromo;
  $PesananBatalTable get pesananBatal => attachedDatabase.pesananBatal;
  TransaksiDaoManager get managers => TransaksiDaoManager(this);
}

class TransaksiDaoManager {
  final _$TransaksiDaoMixin _db;
  TransaksiDaoManager(this._db);
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
  $$ItemTransaksiTableTableManager get itemTransaksi =>
      $$ItemTransaksiTableTableManager(_db.attachedDatabase, _db.itemTransaksi);
  $$GrupModifierTableTableManager get grupModifier =>
      $$GrupModifierTableTableManager(_db.attachedDatabase, _db.grupModifier);
  $$ModifierTableTableManager get modifier =>
      $$ModifierTableTableManager(_db.attachedDatabase, _db.modifier);
  $$ItemTransaksiModifierTableTableManager get itemTransaksiModifier =>
      $$ItemTransaksiModifierTableTableManager(
        _db.attachedDatabase,
        _db.itemTransaksiModifier,
      );
  $$MetodeBayarTableTableManager get metodeBayar =>
      $$MetodeBayarTableTableManager(_db.attachedDatabase, _db.metodeBayar);
  $$PembayaranTableTableManager get pembayaran =>
      $$PembayaranTableTableManager(_db.attachedDatabase, _db.pembayaran);
  $$PajakTableTableManager get pajak =>
      $$PajakTableTableManager(_db.attachedDatabase, _db.pajak);
  $$TransaksiPajakTableTableManager get transaksiPajak =>
      $$TransaksiPajakTableTableManager(
        _db.attachedDatabase,
        _db.transaksiPajak,
      );
  $$PromoTableTableManager get promo =>
      $$PromoTableTableManager(_db.attachedDatabase, _db.promo);
  $$TransaksiPromoTableTableManager get transaksiPromo =>
      $$TransaksiPromoTableTableManager(
        _db.attachedDatabase,
        _db.transaksiPromo,
      );
  $$PesananBatalTableTableManager get pesananBatal =>
      $$PesananBatalTableTableManager(_db.attachedDatabase, _db.pesananBatal);
}
