import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import 'tables/item_transaksi_modifier_table.dart';
import 'tables/item_transaksi_table.dart';
import 'tables/pembayaran_table.dart';
import 'tables/pesanan_batal_table.dart';
import 'tables/transaksi_pajak_table.dart';
import 'tables/transaksi_promo_table.dart';
import 'tables/transaksi_table.dart';

part 'transaksi_dao.g.dart';

@DriftAccessor(
  tables: [
    Transaksi,
    ItemTransaksi,
    ItemTransaksiModifier,
    Pembayaran,
    TransaksiPajak,
    TransaksiPromo,
    PesananBatal,
  ],
)
class TransaksiDao extends DatabaseAccessor<AppDatabase> with _$TransaksiDaoMixin {
  TransaksiDao(super.db);

  Stream<List<TransaksiRow>> watchTransaksiShift(String shiftId) =>
      (select(transaksi)..where((t) => t.shiftId.equals(shiftId) & t.deletedAt.isNull()))
          .watch();

  /// Dipakai halaman Riwayat/Piutang - semua transaksi SUNGGUHAN (sudah
  /// terjadi) di outlet, terbaru lebih dulu. Pesanan tersimpan (F3.E, open
  /// bill - status 'tersimpan', belum pernah benar2 dibayar/terjadi)
  /// SENGAJA dikecualikan di sini (bukan di tiap pemanggil) - draft yang
  /// belum dibayar bukan "transaksi" dlm arti riwayat/piutang, lihat
  /// watchPesananTersimpan utk daftar drafts.
  Stream<List<TransaksiRow>> watchTransaksiOutlet(String outletId) =>
      (select(transaksi)
            ..where((t) =>
                t.outletId.equals(outletId) &
                t.deletedAt.isNull() &
                t.status.equalsValue(TransaksiStatus.tersimpan).not())
            ..orderBy([(t) => OrderingTerm.desc(t.tanggal)]))
          .watch();

  /// Pesanan tersimpan (F3.E, open bill) di outlet ini - SELALU di device
  /// ini saja (versi pertama per-HP, lihat keterbatasan di
  /// docs/aturan_harga.md/README). Terbaru lebih dulu.
  Stream<List<TransaksiRow>> watchPesananTersimpan(String outletId) =>
      (select(transaksi)
            ..where((t) =>
                t.outletId.equals(outletId) &
                t.deletedAt.isNull() &
                t.status.equalsValue(TransaksiStatus.tersimpan))
            ..orderBy([(t) => OrderingTerm.desc(t.tanggal)]))
          .watch();

  /// Hapus draft pesanan tersimpan + item-nya - dipakai saat dibatalkan
  /// ATAU setelah benar2 dibayar (jadi transaksi baru lewat checkout()
  /// biasa, draft lama ini sudah tidak relevan). Hard delete (bukan
  /// deletedAt) - draft yang belum pernah jadi penjualan sungguhan tidak
  /// perlu jejak audit permanen, beda dari void/refund transaksi asli.
  Future<void> hapusPesananTersimpan(String transaksiId) {
    return transaction(() async {
      await (delete(itemTransaksi)..where((t) => t.transaksiId.equals(transaksiId))).go();
      await (delete(transaksi)..where((t) => t.id.equals(transaksiId))).go();
    });
  }

  Stream<TransaksiRow> watchTransaksiById(String id) =>
      (select(transaksi)..where((t) => t.id.equals(id))).watchSingle();

  Future<List<TransaksiRow>> transaksiBelumSync() =>
      (select(transaksi)..where((t) => t.disinkronPada.isNull())).get();

  Future<TransaksiRow> transaksiById(String id) =>
      (select(transaksi)..where((t) => t.id.equals(id))).getSingle();

  /// Temuan A.2 (tahap 5) - simpan snapshot struk (JSON, lihat
  /// lib/core/struk/struk_snapshot.dart) tepat setelah checkout - dipanggil
  /// dari StrukPage, bukan dari checkout() sendiri, krn butuh konteks yang
  /// cuma tersedia di layar itu (pengaturan outlet/profil toko/dkk).
  Future<void> simpanSnapshotStruk(String transaksiId, String snapshotJson) =>
      (update(transaksi)..where((t) => t.id.equals(transaksiId))).write(
        TransaksiCompanion(snapshotStruk: Value(snapshotJson)),
      );

  Future<int> jumlahItemTransaksi(String transaksiId) async {
    final exp = itemTransaksi.id.count();
    final query = selectOnly(itemTransaksi)
      ..addColumns([exp])
      ..where(itemTransaksi.transaksiId.equals(transaksiId));
    final row = await query.getSingle();
    return row.read(exp) ?? 0;
  }

  Future<List<ItemTransaksiRow>> itemUntukTransaksi(String transaksiId) =>
      (select(itemTransaksi)..where((t) => t.transaksiId.equals(transaksiId))).get();

  /// Bug nyata (ditemukan dari laporan crash Riwayat sungguhan): dulu pakai
  /// `getSingleOrNull()` TANPA limit - drift mengimplementasikannya via
  /// `.single` internal, jadi transaksi split payment (2+ baris
  /// `pembayaran`, lihat split_payment_flow_test.dart) bikin query ini
  /// THROW StateError("Bad state: Too many elements") - Riwayat & detail
  /// transaksi jadi error total utk SEMUA transaksi split payment. Fix:
  /// `limit(1)` + urutkan createdAt supaya selalu ambil baris pertama,
  /// tidak pernah throw. Pemanggil yang perlu tahu "ini campuran/bukan"
  /// pakai [jumlahPembayaranTransaksi] terpisah.
  Future<PembayaranRow?> pembayaranUtamaTransaksi(String transaksiId) =>
      (select(pembayaran)
            ..where((t) => t.transaksiId.equals(transaksiId))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<int> jumlahPembayaranTransaksi(String transaksiId) async {
    final exp = pembayaran.id.count();
    final query = selectOnly(pembayaran)
      ..addColumns([exp])
      ..where(pembayaran.transaksiId.equals(transaksiId));
    final row = await query.getSingle();
    return row.read(exp) ?? 0;
  }

  Future<List<TransaksiPajakRow>> pajakUntukTransaksi(String transaksiId) =>
      (select(transaksiPajak)..where((t) => t.transaksiId.equals(transaksiId))).get();

  /// Temuan#1 (rapikan F3) - FIX: method ini sebelumnya `getSingleOrNull()`
  /// (max 1 baris), padahal satu transaksi BISA punya 2 baris TransaksiPromo
  /// sekaligus (diskon member + promo kode, lihat checkout() di
  /// transaksi_repository.dart) - `getSingleOrNull()` THROW StateError
  /// kalau ada >1 baris, jadi SEBELUMNYA sync push/detailTransaksi utk
  /// transaksi semacam itu CRASH. Sekarang ambil SEMUA baris; pemanggil
  /// yang perlu "promo sungguhan saja" (bukan diskon member) filter
  /// `promoId != null` sendiri.
  Future<List<TransaksiPromoRow>> semuaPromoUntukTransaksi(String transaksiId) =>
      (select(transaksiPromo)..where((t) => t.transaksiId.equals(transaksiId))).get();

  /// Dipakai halaman Laporan - transaksi selesai (bukan draft/void) di
  /// rentang [awalMs, akhirMs).
  Future<List<TransaksiRow>> transaksiSelesaiRentang(
    String outletId,
    int awalMs,
    int akhirMs,
  ) =>
      (select(transaksi)
            ..where((t) =>
                t.outletId.equals(outletId) &
                t.deletedAt.isNull() &
                t.status.equalsValue(TransaksiStatus.selesai) &
                t.tanggal.isBiggerOrEqualValue(awalMs) &
                t.tanggal.isSmallerThanValue(akhirMs)))
          .get();

  Future<List<ItemTransaksiRow>> itemUntukTransaksiList(List<String> transaksiIds) {
    if (transaksiIds.isEmpty) return Future.value(const []);
    return (select(itemTransaksi)..where((t) => t.transaksiId.isIn(transaksiIds))).get();
  }

  Future<List<PembayaranRow>> pembayaranUntukTransaksiList(List<String> transaksiIds) {
    if (transaksiIds.isEmpty) return Future.value(const []);
    return (select(pembayaran)..where((t) => t.transaksiId.isIn(transaksiIds))).get();
  }

  /// Menyimpan transaksi beserta item, pembayaran, dan rincian pajaknya
  /// dalam satu transaksi database lokal - jika aplikasi crash di tengah
  /// jalan, tidak ada struk "separuh tersimpan" yang bisa dobel-kirim saat
  /// sync.
  Future<void> simpanTransaksiLengkap({
    required TransaksiCompanion transaksi_,
    required List<ItemTransaksiCompanion> items,
    required List<PembayaranCompanion> pembayaranList,
    List<TransaksiPajakCompanion> pajakList = const [],
    List<TransaksiPromoCompanion> promoList = const [],
  }) {
    return transaction(() async {
      await into(transaksi).insert(transaksi_);
      for (final item in items) {
        await into(itemTransaksi).insert(item);
      }
      for (final bayar in pembayaranList) {
        await into(pembayaran).insert(bayar);
      }
      for (final pajak in pajakList) {
        await into(transaksiPajak).insert(pajak);
      }
      for (final promo in promoList) {
        await into(transaksiPromo).insert(promo);
      }
    });
  }

  /// Menandai transaksi dibatalkan (void) - pembalikan stok dilakukan di
  /// StokDao.catatMutasi oleh pemanggil, dalam transaction() yang sama.
  Future<void> voidTransaksi({
    required String transaksiId,
    required String alasan,
    required String disetujuiOleh,
    required int now,
  }) {
    return (update(transaksi)..where((t) => t.id.equals(transaksiId))).write(
      TransaksiCompanion(
        status: const Value(TransaksiStatus.dibatalkan),
        alasanVoid: Value(alasan),
        voidDisetujuiOleh: Value(disetujuiOleh),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> tandaiSudahSync(List<String> transaksiIds, int waktuSyncMs) {
    return transaction(() async {
      for (final id in transaksiIds) {
        await (update(transaksi)..where((t) => t.id.equals(id))).write(
          TransaksiCompanion(disinkronPada: Value(waktuSyncMs)),
        );
      }
    });
  }

  /// Cicilan/pelunasan kasbon (tahap 3b-1) - insert baris Pembayaran baru +
  /// update sisaTagihan/statusBayar transaksi induknya, ATOMIK. `jenis`
  /// ditentukan DI SINI dari sisa SETELAH pembayaran ini (bukan dioper
  /// pemanggil) - 'pelunasan' kalau sisa jadi 0, 'cicilan' kalau belum,
  /// sama logika dgn backend app/services/pembayaran_service.py.
  Future<void> catatPembayaranKasbon({
    required PembayaranCompanion pembayaranTanpaJenis,
    required int now,
  }) {
    return transaction(() async {
      final transaksiId = pembayaranTanpaJenis.transaksiId.value;
      final row = await (select(transaksi)..where((t) => t.id.equals(transaksiId))).getSingle();
      final jumlah = pembayaranTanpaJenis.jumlah.value;
      final sisaBaru = (row.sisaTagihan - jumlah) < 0 ? 0 : row.sisaTagihan - jumlah;
      final jenis = sisaBaru == 0 ? PembayaranJenis.pelunasan : PembayaranJenis.cicilan;

      await into(pembayaran).insert(pembayaranTanpaJenis.copyWith(jenis: Value(jenis)));
      await (update(transaksi)..where((t) => t.id.equals(transaksiId))).write(
        TransaksiCompanion(
          sisaTagihan: Value(sisaBaru),
          statusBayar: Value(
            sisaBaru == 0 ? StatusBayarTransaksi.lunas : StatusBayarTransaksi.sebagian,
          ),
          updatedAt: Value(now),
        ),
      );
    });
  }

  /// Baris Pembayaran yang belum pernah di-push lewat /sync/push - dipakai
  /// utk cicilan/pelunasan yang dicatat BELAKANGAN (transaksi induknya bisa
  /// saja sudah tersync sebelumnya, jadi watermark-nya terpisah dari
  /// transaksiBelumSync() di atas - lihat komentar Pembayaran.disinkronPada).
  Future<List<PembayaranRow>> pembayaranBelumSync() =>
      (select(pembayaran)..where((t) => t.disinkronPada.isNull())).get();

  Future<void> tandaiPembayaranSudahSync(List<String> pembayaranIds, int waktuSyncMs) {
    return transaction(() async {
      for (final id in pembayaranIds) {
        await (update(pembayaran)..where((t) => t.id.equals(id))).write(
          PembayaranCompanion(disinkronPada: Value(waktuSyncMs)),
        );
      }
    });
  }

  /// Temuan#2 (rapikan F3.E) - catat niat pembatalan pesanan tersimpan
  /// SEBELUM draft-nya dihapus (snapshot isi/total/nomorStruk, krn draft
  /// aslinya akan hilang) - baris ini antrean "belum terkirim ke server"
  /// (disinkronPada null), pola sama dgn pembayaranBelumSync di atas.
  Future<void> catatPembatalanPesanan(PesananBatalCompanion baris) =>
      into(pesananBatal).insert(baris);

  Future<List<PesananBatalRow>> pembatalanPesananBelumSync() =>
      (select(pesananBatal)..where((t) => t.disinkronPada.isNull())).get();

  Future<void> tandaiPembatalanPesananSudahSync(List<String> ids, int waktuSyncMs) {
    return transaction(() async {
      for (final id in ids) {
        await (update(pesananBatal)..where((t) => t.id.equals(id))).write(
          PesananBatalCompanion(disinkronPada: Value(waktuSyncMs)),
        );
      }
    });
  }
}
