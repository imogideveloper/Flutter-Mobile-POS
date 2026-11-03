import 'package:drift/drift.dart';

import '../../../../shift/data/local/tables/shift_table.dart';
import 'metode_bayar_table.dart';
import 'transaksi_table.dart';

enum PembayaranStatus { pending, berhasil, gagal, kedaluwarsa }
enum PembayaranJenis { penuh, dp, cicilan, pelunasan }

/// payloadGateway menyimpan JSON mentah dari Midtrans/Xendit sebagai teks -
/// status final transaksi WAJIB dikonfirmasi lewat webhook/polling ke
/// server, bukan dipercaya dari nilai yang ditulis HP saat offline.
@DataClassName('PembayaranRow')
class Pembayaran extends Table {
  @override
  String get tableName => 'pembayaran';

  TextColumn get id => text()();
  TextColumn get transaksiId => text().references(Transaksi, #id)();
  TextColumn get metodeBayarId => text().references(MetodeBayar, #id)();
  // Shift TEMPAT uang ini diterima (tahap 3b-1) - bisa beda dari
  // transaksi.shiftId utk cicilan/pelunasan kasbon yang dibayar belakangan
  // di shift lain (lihat PelunasanPage). Nullable krn kolom ini baru.
  TextColumn get shiftId => text().nullable().references(Shift, #id)();
  IntColumn get jumlah => integer()();
  TextColumn get jenis =>
      textEnum<PembayaranJenis>().withDefault(const Constant('penuh'))();
  TextColumn get status => textEnum<PembayaranStatus>()();
  TextColumn get refGateway => text().nullable()();
  TextColumn get payloadGateway => text().nullable()();
  IntColumn get dibayarPada => integer().nullable()();
  // Watermark sync (tahap 3b-1) - sama pola dgn transaksi.disinkronPada.
  // Pembayaran yang lahir BERSAMA transaksi (dp/penuh saat checkout) ikut
  // tersync lewat payload checkout transaksinya; baris cicilan/pelunasan
  // yang dicatat BELAKANGAN (transaksi induk mungkin sudah tersync) butuh
  // watermark sendiri supaya bisa di-push terpisah lewat /sync/push.
  IntColumn get disinkronPada => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
