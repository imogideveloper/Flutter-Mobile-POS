import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/utils/id_generator.dart';
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
      final idItem = [
        for (final r in await (select(itemTransaksi)..where((t) => t.transaksiId.equals(transaksiId))).get()) r.id,
      ];
      if (idItem.isNotEmpty) {
        await (delete(itemTransaksiModifier)..where((t) => t.itemTransaksiId.isIn(idItem))).go();
      }
      await (delete(itemTransaksi)..where((t) => t.transaksiId.equals(transaksiId))).go();
      await (delete(transaksi)..where((t) => t.id.equals(transaksiId))).go();
    });
  }

  Stream<TransaksiRow> watchTransaksiById(String id) =>
      (select(transaksi)..where((t) => t.id.equals(id))).watchSingle();

  /// Transaksi yang belum terkirim ke server. Pesanan tersimpan (open bill)
  /// dan draft TIDAK ikut: itu belum jadi penjualan, belum punya baris
  /// Pembayaran, dan kalau ikut terkirim server menolak seluruh
  /// `/sync/push` dengan 422 (metode_bayar_id bukan UUID) sehingga
  /// transaksi selesai lain ikut tertahan.
  /// Jumlah transaksi yang belum tersinkron, MENGIKUTI basis data: berubah sendiri saat transaksi baru tercatat
  /// (offline) dan saat sinkron menandainya terkirim. Sebelumnya hitungan diambil sekali, sehingga layar tetap
  /// menulis `Semua transaksi tersinkron` padahal ada transaksi offline yang belum terkirim.
  Stream<int> watchJumlahBelumSync() => (selectOnly(transaksi)
        ..addColumns([transaksi.id])
        ..where(transaksi.disinkronPada.isNull() &
            transaksi.status.equalsValue(TransaksiStatus.tersimpan).not() &
            transaksi.status.equalsValue(TransaksiStatus.draft).not()))
      .watch()
      .map((baris) => baris.length);

  Future<List<TransaksiRow>> transaksiBelumSync() => (select(transaksi)
        ..where(
          (t) =>
              t.disinkronPada.isNull() &
              t.status.equalsValue(TransaksiStatus.tersimpan).not() &
              t.status.equalsValue(TransaksiStatus.draft).not(),
        ))
      .get();

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

  /// Tambahan (varian/topping) yang dipilih pada item-item ini.
  Future<List<ItemTransaksiModifierRow>> modifierUntukItemList(List<String> itemTransaksiIds) {
    if (itemTransaksiIds.isEmpty) return Future.value(const []);
    return (select(itemTransaksiModifier)
          ..where((t) => t.itemTransaksiId.isIn(itemTransaksiIds) & t.deletedAt.isNull()))
        .get();
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

  /// Nama kategori tiap produk (produk tanpa kategori tidak ada di hasil), dasar laporan tren per kategori.
  Future<Map<String, String>> namaKategoriPerProduk(Set<String> produkIds) async {
    if (produkIds.isEmpty) return const {};
    final db = attachedDatabase;
    final query = db.select(db.produk).join([
      innerJoin(db.kategori, db.kategori.id.equalsExp(db.produk.kategoriId)),
    ])
      ..where(db.produk.id.isIn(produkIds));
    final baris = await query.get();
    return {for (final r in baris) r.read(db.produk.id)!: r.read(db.kategori.nama)!};
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
    List<ItemTransaksiModifierCompanion> modifierList = const [],
  }) {
    return transaction(() async {
      await into(transaksi).insert(transaksi_);
      for (final item in items) {
        await into(itemTransaksi).insert(item);
      }
      for (final m in modifierList) {
        await into(itemTransaksiModifier).insert(m);
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

  /// Refund selalu diproses server (online). Setelah berhasil, status transaksi di HP ikut disamakan
  /// dengan status yang dikembalikan server ('refund' atau 'refund_sebagian'); nilai lain diabaikan.
  /// Penanda sync tidak disentuh: perubahan ini berasal dari server, bukan untuk dikirim balik.
  Future<void> terapkanStatusRefund({
    required String transaksiId,
    required String statusServer,
    required int now,
  }) async {
    final status = switch (statusServer) {
      'refund' => TransaksiStatus.refund,
      'refund_sebagian' => TransaksiStatus.refundSebagian,
      _ => null,
    };
    if (status == null) return;
    await (update(transaksi)..where((t) => t.id.equals(transaksiId))).write(
      TransaksiCompanion(status: Value(status), updatedAt: Value(now)),
    );
  }

  /// Waktu (epoch ms) transaksi tertua di outlet ini, null bila belum ada satu pun. Dipakai Laporan untuk tahu
  /// apakah data lama perlu diambil dari server.
  Future<int?> tanggalTransaksiPalingAwal(String outletId) async {
    final minTanggal = transaksi.tanggal.min();
    final q = selectOnly(transaksi)
      ..addColumns([minTanggal])
      ..where(transaksi.outletId.equals(outletId) & transaksi.deletedAt.isNull());
    return (await q.getSingle()).read(minTanggal);
  }

  /// Transaksi yang dihitung sebagai penjualan di laporan: selesai dan refund sebagian (sisanya masih
  /// penjualan). Refund penuh dan void tidak ikut.
  Future<List<TransaksiRow>> transaksiPenjualanRentang(String outletId, int awalMs, int akhirMs) =>
      (select(transaksi)
            ..where((t) =>
                t.outletId.equals(outletId) &
                t.deletedAt.isNull() &
                (t.status.equalsValue(TransaksiStatus.selesai) | t.status.equalsValue(TransaksiStatus.refundSebagian)) &
                t.tanggal.isBiggerOrEqualValue(awalMs) &
                t.tanggal.isSmallerThanValue(akhirMs)))
          .get();

  /// Total refund (Rupiah) per transaksi, dari refund yang dicatat di HP ini lewat [catatRefundLokal].
  Future<Map<String, int>> totalRefundPerTransaksi(Iterable<String> transaksiIds) async {
    final ids = transaksiIds.toList();
    if (ids.isEmpty) return {};
    final tabel = attachedDatabase.refund;
    final rows = await (select(tabel)..where((r) => r.transaksiId.isIn(ids) & r.deletedAt.isNull())).get();
    final hasil = <String, int>{};
    for (final r in rows) {
      hasil[r.transaksiId] = (hasil[r.transaksiId] ?? 0) + r.total;
    }
    return hasil;
  }

  /// Mencatat refund yang berhasil diproses server ke tabel lokal, supaya laporan di HP bisa mengurangi
  /// penjualan. Tidak melakukan apa-apa bila transaksinya tidak ada di HP ini.
  Future<void> catatRefundLokal({
    required String id,
    required String transaksiId,
    required String nomor,
    required String alasan,
    required int total,
    required bool kembalikanStok,
    required int now,
  }) async {
    final ada = await (select(transaksi)..where((t) => t.id.equals(transaksiId))).getSingleOrNull();
    if (ada == null) return;
    await into(attachedDatabase.refund).insertOnConflictUpdate(
      RefundCompanion.insert(
        id: id,
        transaksiId: transaksiId,
        nomor: nomor,
        alasan: alasan,
        total: total,
        kembalikanStok: Value(kembalikanStok),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Mencatat item yang direfund (menurut server) ke item lokal transaksi ini. Id item di server berbeda dari id di
  /// HP, jadi item dicocokkan lewat (nama produk, harga satuan); bila tidak ada yang cocok persis, lewat nama saja.
  /// Qty dibagi ke baris lokal yang sama berurutan sesuai sisa qty tiap baris. Perlu baris refund lokal dari
  /// [catatRefundLokal] lebih dulu; tanpa itu tidak melakukan apa-apa. Aman dipanggil ulang untuk refund yang sama.
  Future<void> catatItemRefundLokal({
    required String refundId,
    required String transaksiId,
    required List<({String namaProduk, int hargaSatuan, double qty, int jumlah})> items,
    required int now,
  }) async {
    final tabelRefund = attachedDatabase.refund;
    final tabelItemRefund = attachedDatabase.itemRefund;
    final refund = await (select(tabelRefund)..where((r) => r.id.equals(refundId))).getSingleOrNull();
    if (refund == null) return;

    await transaction(() async {
      final lokal = await itemUntukTransaksi(transaksiId);
      await (delete(tabelItemRefund)..where((r) => r.refundId.equals(refundId))).go();
      final sudahDirefund = <String, double>{};
      if (lokal.isNotEmpty) {
        final rows = await (select(tabelItemRefund)
              ..where((r) => r.itemTransaksiId.isIn([for (final i in lokal) i.id]) & r.deletedAt.isNull()))
            .get();
        for (final r in rows) {
          sudahDirefund[r.itemTransaksiId] = (sudahDirefund[r.itemTransaksiId] ?? 0) + r.qty;
        }
      }

      for (final masuk in items) {
        var kandidat = lokal.where((i) => i.namaProduk == masuk.namaProduk && i.hargaSatuan == masuk.hargaSatuan);
        if (kandidat.isEmpty) kandidat = lokal.where((i) => i.namaProduk == masuk.namaProduk);
        var sisaButuh = masuk.qty;
        for (final baris in kandidat) {
          if (sisaButuh <= 0) break;
          final tersedia = baris.qty - (sudahDirefund[baris.id] ?? 0);
          if (tersedia <= 0) continue;
          final ambil = sisaButuh < tersedia ? sisaButuh : tersedia;
          await into(tabelItemRefund).insert(
            ItemRefundCompanion.insert(
              id: generateId(),
              refundId: refundId,
              itemTransaksiId: baris.id,
              qty: ambil,
              jumlah: masuk.qty <= 0 ? 0 : (masuk.jumlah * ambil / masuk.qty).round(),
              createdAt: now,
              updatedAt: now,
            ),
          );
          sudahDirefund[baris.id] = (sudahDirefund[baris.id] ?? 0) + ambil;
          sisaButuh -= ambil;
        }
      }
    });
  }

  /// Total qty yang direfund per id item lokal, dan bagian yang barangnya dikembalikan ke stok.
  Future<Map<String, ({double qty, double qtyKembaliStok})>> refundPerItem(Iterable<String> itemIds) async {
    final ids = itemIds.toList();
    if (ids.isEmpty) return {};
    final ir = attachedDatabase.itemRefund;
    final r = attachedDatabase.refund;
    final query = select(ir).join([innerJoin(r, r.id.equalsExp(ir.refundId))])
      ..where(ir.itemTransaksiId.isIn(ids) & ir.deletedAt.isNull() & r.deletedAt.isNull());
    final hasil = <String, ({double qty, double qtyKembaliStok})>{};
    for (final baris in await query.get()) {
      final item = baris.readTable(ir);
      final refund = baris.readTable(r);
      final lama = hasil[item.itemTransaksiId] ?? (qty: 0.0, qtyKembaliStok: 0.0);
      hasil[item.itemTransaksiId] = (
        qty: lama.qty + item.qty,
        qtyKembaliStok: lama.qtyKembaliStok + (refund.kembalikanStok ? item.qty : 0.0),
      );
    }
    return hasil;
  }

  Future<void> tandaiSudahSync(List<String> transaksiIds, int waktuSyncMs) {
    return transaction(() async {
      for (final id in transaksiIds) {
        // Status pesanan ikut payload checkout (versi terbaru saat dikirim),
        // jadi pelacak sinkron statusnya ikut ditandai.
        await (update(transaksi)..where((t) => t.id.equals(id))).write(
          TransaksiCompanion(
            disinkronPada: Value(waktuSyncMs),
            statusPesananDisinkronPada: Value(waktuSyncMs),
          ),
        );
      }
    });
  }

  /// Ubah status pesanan (alur IMOGI: Baru, Diproses, Siap, Selesai) dan catat
  /// waktunya supaya perubahan ini dikirim ke server pada sync berikutnya.
  Future<void> ubahStatusPesanan(String transaksiId, StatusPesanan status, int now) {
    return (update(transaksi)..where((t) => t.id.equals(transaksiId))).write(
      TransaksiCompanion(
        statusPesanan: Value(status),
        statusPesananDiubahPada: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// Pesanan outlet sejak [sejakMs] yang punya status pesanan (diisi saat
  /// checkout bila fitur status_pesanan terbuka). Transaksi yang di-void atau
  /// masih berupa pesanan tersimpan tidak ikut. Terbaru di atas.
  Future<List<TransaksiRow>> pesananBerstatus({required String outletId, required int sejakMs}) {
    return (select(transaksi)
          ..where((t) =>
              t.outletId.equals(outletId) &
              t.deletedAt.isNull() &
              t.statusPesanan.isNotNull() &
              t.status.equalsValue(TransaksiStatus.dibatalkan).not() &
              t.status.equalsValue(TransaksiStatus.tersimpan).not() &
              t.status.equalsValue(TransaksiStatus.draft).not() &
              t.tanggal.isBiggerOrEqualValue(sejakMs))
          ..orderBy([(t) => OrderingTerm.desc(t.tanggal)]))
        .get();
  }

  /// Status yang berubah SETELAH transaksinya tersync (jadi tidak ikut payload
  /// checkout) dan belum terkirim. Transaksi yang belum tersync tidak dihitung
  /// di sini: status terbarunya ikut terkirim bersama transaksinya.
  Future<List<TransaksiRow>> statusPesananBelumSync() async {
    final rows = await (select(transaksi)
          ..where((t) =>
              t.disinkronPada.isNotNull() &
              t.statusPesananDiubahPada.isNotNull() &
              t.statusPesanan.isNotNull()))
        .get();
    return [
      for (final r in rows)
        // <= (bukan <): perubahan pada milidetik yang sama dengan penandaan sync ikut dikirim ulang (aman, idempoten).
        if (r.statusPesananDisinkronPada == null || r.statusPesananDisinkronPada! <= r.statusPesananDiubahPada!) r,
    ];
  }

  Future<void> tandaiStatusPesananSudahSync(List<String> transaksiIds, int waktuSyncMs) {
    return transaction(() async {
      for (final id in transaksiIds) {
        await (update(transaksi)..where((t) => t.id.equals(id))).write(
          TransaksiCompanion(statusPesananDisinkronPada: Value(waktuSyncMs)),
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
