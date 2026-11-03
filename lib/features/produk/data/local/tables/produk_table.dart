import 'package:drift/drift.dart';

import 'kategori_table.dart';
import 'satuan_table.dart';

// 'bundling', bukan 'paket' - mengikuti CHECK constraint produk.tipe di
// schema_pos v2 (barang, jasa, bahan_baku, bundling). Sempat salah ditulis
// 'paket' sebelum skema resminya dicek ulang.
enum ProdukTipe { barang, jasa, bahanBaku, bundling }

/// Nilai string di PostgreSQL pakai snake_case ('bahan_baku'), beda dengan
/// .name Dart enum ini - dipetakan di layer DTO sync, bukan di kolom ini.
const produkTipePostgresValue = <ProdukTipe, String>{
  ProdukTipe.barang: 'barang',
  ProdukTipe.jasa: 'jasa',
  ProdukTipe.bahanBaku: 'bahan_baku',
  ProdukTipe.bundling: 'bundling',
};

@DataClassName('ProdukRow')
class Produk extends Table {
  @override
  String get tableName => 'produk';

  TextColumn get id => text()();
  TextColumn get tokoId => text()();
  TextColumn get kategoriId => text().nullable().references(Kategori, #id)();
  TextColumn get satuanId => text().nullable().references(Satuan, #id)();
  TextColumn get sku => text().nullable()();
  TextColumn get barcode => text().nullable()();
  TextColumn get nama => text()();
  TextColumn get deskripsi => text().nullable()();
  TextColumn get gambarUrl => text().nullable()();
  TextColumn get tipe => textEnum<ProdukTipe>()();
  BoolColumn get lacakStok => boolean().withDefault(const Constant(true))();
  BoolColumn get punyaVarian => boolean().withDefault(const Constant(false))();
  BoolColumn get pakaiResep => boolean().withDefault(const Constant(false))();
  BoolColumn get lacakKedaluwarsa => boolean().withDefault(const Constant(false))();
  IntColumn get hpp => integer().withDefault(const Constant(0))();
  IntColumn get hargaJual => integer().withDefault(const Constant(0))();
  BoolColumn get dijual => boolean().withDefault(const Constant(true))();
  BoolColumn get aktif => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {tokoId, sku},
        {tokoId, barcode},
      ];
}
