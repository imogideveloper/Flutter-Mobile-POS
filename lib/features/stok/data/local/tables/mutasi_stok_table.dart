import 'package:drift/drift.dart';

import '../../../../../core/database/tables/outlets_table.dart';
import '../../../../../core/database/tables/pengguna_table.dart';
import '../../../../produk/data/local/tables/produk_table.dart';
import '../../../../produk/data/local/tables/produk_varian_table.dart';
import 'batch_stok_table.dart';

enum MutasiJenis {
  stokAwal,
  pembelian,
  penjualan,
  refund,
  voidTransaksi,
  opname,
  transferMasuk,
  transferKeluar,
  penyesuaian,
  produksi,
}

/// Nilai string di PostgreSQL ('stok_awal', 'void', dst) dipetakan di layer
/// DTO sync, bukan di kolom ini - lihat produkTipePostgresValue.
const mutasiJenisPostgresValue = <MutasiJenis, String>{
  MutasiJenis.stokAwal: 'stok_awal',
  MutasiJenis.pembelian: 'pembelian',
  MutasiJenis.penjualan: 'penjualan',
  MutasiJenis.refund: 'refund',
  MutasiJenis.voidTransaksi: 'void',
  MutasiJenis.opname: 'opname',
  MutasiJenis.transferMasuk: 'transfer_masuk',
  MutasiJenis.transferKeluar: 'transfer_keluar',
  MutasiJenis.penyesuaian: 'penyesuaian',
  MutasiJenis.produksi: 'produksi',
};

/// Log semua perubahan stok - setiap insert di sini wajib diikuti update
/// saldo di tabel Stok dalam satu transaksi database yang sama (lihat
/// StokDao.catatMutasi).
@DataClassName('MutasiStokRow')
class MutasiStok extends Table {
  @override
  String get tableName => 'mutasi_stok';

  TextColumn get id => text()();
  TextColumn get tokoId => text()();
  TextColumn get outletId => text().references(Outlets, #id)();
  TextColumn get produkId => text().references(Produk, #id)();
  TextColumn get varianId => text().nullable().references(ProdukVarian, #id)();
  TextColumn get batchId => text().nullable().references(BatchStok, #id)();
  TextColumn get jenis => textEnum<MutasiJenis>()();
  RealColumn get qty => real()();
  IntColumn get hppSatuan => integer().withDefault(const Constant(0))();
  RealColumn get saldoSetelah => real().nullable()();
  TextColumn get refTipe => text().nullable()();
  TextColumn get refId => text().nullable()();
  TextColumn get catatan => text().nullable()();
  TextColumn get dibuatOleh => text().nullable().references(Pengguna, #id)();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
