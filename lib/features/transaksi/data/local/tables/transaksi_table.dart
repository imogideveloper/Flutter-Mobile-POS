import 'package:drift/drift.dart';

import '../../../../../core/database/tables/outlets_table.dart';
import '../../../../../core/database/tables/pengguna_table.dart';
import '../../../../../core/database/tables/perangkat_table.dart';
import '../../../../dapur/data/local/tables/meja_table.dart';
import '../../../../order/data/local/tables/tipe_order_table.dart';
import '../../../../shift/data/local/tables/shift_table.dart';

enum TransaksiStatus { draft, tersimpan, selesai, dibatalkan, refundSebagian, refund }
// diantar dan selesai ditambahkan untuk alur IMOGI (Baru, Diproses, Siap, (Diantar), Selesai);
// diambil dipertahankan untuk data lama dan dianggap setara selesai.
enum StatusPesanan { baru, diproses, siap, diambil, dibatalkan, diantar, selesai }
enum StatusBayarTransaksi { lunas, sebagian, belumBayar }

const statusBayarTransaksiPostgresValue = <StatusBayarTransaksi, String>{
  StatusBayarTransaksi.lunas: 'lunas',
  StatusBayarTransaksi.sebagian: 'sebagian',
  StatusBayarTransaksi.belumBayar: 'belum_bayar',
};

/// dibatalkan <-> 'void' dan refundSebagian <-> 'refund_sebagian' dipetakan
/// di layer DTO sync - lihat produkTipePostgresValue untuk pola yang sama.
const transaksiStatusPostgresValue = <TransaksiStatus, String>{
  TransaksiStatus.draft: 'draft',
  TransaksiStatus.tersimpan: 'tersimpan',
  TransaksiStatus.selesai: 'selesai',
  TransaksiStatus.dibatalkan: 'void',
  TransaksiStatus.refundSebagian: 'refund_sebagian',
  TransaksiStatus.refund: 'refund',
};

/// pelangganId sengaja tanpa FK - tabel Pelanggan belum dibuat di tahap ini
/// (modul 6, belum diminta). Kolom tetap disediakan agar kolom kompatibel
/// saat modul pelanggan ditambahkan nanti, tinggal tambah .references().
@DataClassName('TransaksiRow')
class Transaksi extends Table {
  @override
  String get tableName => 'transaksi';

  TextColumn get id => text()();
  TextColumn get tokoId => text()();
  TextColumn get outletId => text().references(Outlets, #id)();
  TextColumn get shiftId => text().nullable().references(Shift, #id)();
  TextColumn get perangkatId => text().nullable().references(Perangkat, #id)();
  TextColumn get penggunaId => text().references(Pengguna, #id)();
  TextColumn get pelangganId => text().nullable()();
  TextColumn get tipeOrderId => text().nullable().references(TipeOrder, #id)();
  TextColumn get mejaId => text().nullable().references(Meja, #id)();
  TextColumn get nomorStruk => text()();
  IntColumn get tanggal => integer()();
  TextColumn get nomorAntrean => text().nullable()();
  TextColumn get statusPesanan => textEnum<StatusPesanan>().nullable()();
  // Pelacak sinkron status pesanan: status berubah SETELAH transaksi tersync tidak ikut
  // payload checkout, jadi dikirim lewat daftar status_pesanan di /sync/push. Belum
  // tersync bila diubahPada tidak null dan (disinkronPada null atau lebih lama).
  IntColumn get statusPesananDiubahPada => integer().nullable()();
  IntColumn get statusPesananDisinkronPada => integer().nullable()();
  TextColumn get status => textEnum<TransaksiStatus>()();
  IntColumn get subtotal => integer().withDefault(const Constant(0))();
  IntColumn get totalDiskon => integer().withDefault(const Constant(0))();
  // Poin loyalitas yang ditukar jadi diskon checkout ini (modul 10) -
  // poinDitukar = jumlah poin, diskonPoin = nilai Rupiah-nya (SUDAH ikut
  // termasuk di totalDiskon/total di atas, disimpan terpisah di sini
  // HANYA supaya SyncRepository tahu persis berapa poin yg harus dikirim
  // ke backend/CheckoutIn.poinDitukar - lihat TransaksiRepository.checkout).
  IntColumn get poinDitukar => integer().withDefault(const Constant(0))();
  IntColumn get diskonPoin => integer().withDefault(const Constant(0))();
  IntColumn get totalPajak => integer().withDefault(const Constant(0))();
  IntColumn get pembulatan => integer().withDefault(const Constant(0))();
  IntColumn get total => integer().withDefault(const Constant(0))();
  IntColumn get totalBayar => integer().withDefault(const Constant(0))();
  IntColumn get kembalian => integer().withDefault(const Constant(0))();
  TextColumn get statusBayar =>
      textEnum<StatusBayarTransaksi>().withDefault(const Constant('lunas'))();
  // Kasbon: sisa yang belum dibayar saat status_bayar bukan 'lunas'.
  IntColumn get sisaTagihan => integer().withDefault(const Constant(0))();
  // date di Postgres - epoch ms UTC tengah malam, sama konvensinya dengan
  // tanggalKedaluwarsa di BatchStok.
  IntColumn get jatuhTempo => integer().nullable()();
  TextColumn get catatan => text().nullable()();
  TextColumn get alasanVoid => text().nullable()();
  TextColumn get voidDisetujuiOleh => text().nullable().references(Pengguna, #id)();
  IntColumn get disinkronPada => integer().nullable()();
  // Temuan A.2 (tahap 5) - JSON (encode lib/core/struk/struk_snapshot.dart)
  // persis data+pengaturan struk SAAT transaksi dibuat - dipakai cetak
  // ulang identik, BUKAN rekonstruksi dari data saat ini.
  TextColumn get snapshotStruk => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {outletId, nomorStruk},
      ];
}
