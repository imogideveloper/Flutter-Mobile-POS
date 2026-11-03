import 'package:drift/drift.dart';

import '../../../../../core/database/tables/outlets_table.dart';
import '../../../../produk/data/local/tables/produk_table.dart';
import '../../../../produk/data/local/tables/produk_varian_table.dart';

/// pembelianId sengaja tanpa FK - tabel Pembelian hanya ada di server
/// (lihat PROMPT_Senior_Mobile_Dev_POS bagian 4.1), HP cuma menerima batch
/// hasil pembelian lewat sync, bukan membuat pembelian secara lokal.
@DataClassName('BatchStokRow')
class BatchStok extends Table {
  @override
  String get tableName => 'batch_stok';

  TextColumn get id => text()();
  TextColumn get outletId => text().references(Outlets, #id)();
  TextColumn get produkId => text().references(Produk, #id)();
  TextColumn get varianId => text().nullable().references(ProdukVarian, #id)();
  TextColumn get pembelianId => text().nullable()();
  TextColumn get nomorBatch => text().nullable()();
  // date di Postgres - disimpan sebagai epoch ms UTC tengah malam, sama
  // dengan konvensi timestamptz di kolom lain.
  IntColumn get tanggalKedaluwarsa => integer()();
  RealColumn get qtyAwal => real()();
  RealColumn get qtySisa => real()();
  IntColumn get ingatkanHari => integer().withDefault(const Constant(30))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
