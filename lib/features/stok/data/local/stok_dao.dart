import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/utils/id_generator.dart';
import 'tables/mutasi_stok_table.dart';
import 'tables/stok_table.dart';

part 'stok_dao.g.dart';

/// Pasangan baris Stok + nama produknya - drift tidak meng-generate
/// data class untuk join manual, jadi dibungkus sendiri di sini.
class StokDenganProduk {
  const StokDenganProduk({required this.stok, required this.produk});

  final StokRow stok;
  final ProdukRow produk;
}

/// Sama seperti StokDenganProduk, tapi untuk baris mutasi_stok.
class MutasiDenganProduk {
  const MutasiDenganProduk({required this.mutasi, required this.produk});

  final MutasiStokRow mutasi;
  final ProdukRow produk;
}

@DriftAccessor(tables: [Stok, MutasiStok])
class StokDao extends DatabaseAccessor<AppDatabase> with _$StokDaoMixin {
  StokDao(super.db);

  Stream<List<StokRow>> watchStokOutlet(String outletId) =>
      (select(stok)..where((t) => t.outletId.equals(outletId) & t.deletedAt.isNull()))
          .watch();

  /// Sama seperti watchStokOutlet, tapi ikut join ke Produk supaya UI punya
  /// nama produk tanpa query terpisah per baris.
  Stream<List<StokDenganProduk>> watchStokOutletDenganProduk(String outletId) {
    final query = select(stok).join([
      innerJoin(produk, produk.id.equalsExp(stok.produkId)),
    ])
      ..where(stok.outletId.equals(outletId) & stok.deletedAt.isNull());

    return query.watch().map((rows) => rows
        .map((row) => StokDenganProduk(
              stok: row.readTable(stok),
              produk: row.readTable(produk),
            ))
        .toList());
  }

  /// Mutasi terbaru di outlet - dipakai kartu "Mutasi terakhir" di halaman
  /// Stok, bukan sumber audit lengkap (itu tetap seluruh tabel mutasi_stok).
  Stream<List<MutasiDenganProduk>> watchMutasiTerakhir(String outletId, {int limit = 10}) {
    final query = select(mutasiStok).join([
      innerJoin(produk, produk.id.equalsExp(mutasiStok.produkId)),
    ])
      ..where(mutasiStok.outletId.equals(outletId) & mutasiStok.deletedAt.isNull())
      ..orderBy([OrderingTerm.desc(mutasiStok.createdAt)])
      ..limit(limit);

    return query.watch().map((rows) => rows
        .map((row) => MutasiDenganProduk(
              mutasi: row.readTable(mutasiStok),
              produk: row.readTable(produk),
            ))
        .toList());
  }

  /// Riwayat mutasi satu produk di outlet ini (semua varian), terbaru lebih dulu. Dibatasi [limit]
  /// supaya daftar tetap ringan; sumber audit lengkap tetap tabel mutasi_stok.
  Stream<List<MutasiDenganProduk>> watchMutasiProduk(String outletId, String produkId, {int limit = 300}) {
    final query = select(mutasiStok).join([
      innerJoin(produk, produk.id.equalsExp(mutasiStok.produkId)),
    ])
      ..where(mutasiStok.outletId.equals(outletId) & mutasiStok.produkId.equals(produkId) & mutasiStok.deletedAt.isNull())
      ..orderBy([OrderingTerm.desc(mutasiStok.createdAt)])
      ..limit(limit);

    return query.watch().map((rows) => rows
        .map((row) => MutasiDenganProduk(
              mutasi: row.readTable(mutasiStok),
              produk: row.readTable(produk),
            ))
        .toList());
  }

  Future<StokRow?> cariStok({
    required String outletId,
    required String produkId,
    String? varianId,
  }) => (select(stok)
        ..where((t) =>
            t.outletId.equals(outletId) &
            t.produkId.equals(produkId) &
            (varianId == null ? t.varianId.isNull() : t.varianId.equals(varianId))))
      .getSingleOrNull();

  /// Ubah HANYA ambang "stok menipis" - TIDAK menulis baris mutasi_stok
  /// (beda dari [catatMutasi]: ini bukan pergerakan stok sungguhan, cuma
  /// ubah angka pengingat). Dipakai form produk mode EDIT - sebelum ini
  /// ada, batas minimum cuma bisa diisi sekali saat produk pertama kali
  /// dibuat dan tidak bisa diperbaiki lagi lewat Edit (bug nyata yang
  /// dilaporkan pengguna, lihat produk_form_page.dart).
  Future<void> aturBatasMinimum({
    required String outletId,
    required String produkId,
    String? varianId,
    required double batasMinimum,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final existing = await cariStok(outletId: outletId, produkId: produkId, varianId: varianId);
    if (existing == null) {
      await into(stok).insert(StokCompanion.insert(
        id: generateId(),
        outletId: outletId,
        produkId: produkId,
        varianId: Value(varianId),
        batasMinimum: Value(batasMinimum),
        createdAt: now,
        updatedAt: now,
      ));
    } else {
      await (update(stok)..where((t) => t.id.equals(existing.id))).write(
        StokCompanion(batasMinimum: Value(batasMinimum), updatedAt: Value(now)),
      );
    }
  }

  /// Satu-satunya jalan masuk untuk mengubah stok: menulis baris mutasi_stok
  /// lalu memperbarui saldo di tabel stok, dalam satu transaksi lokal supaya
  /// keduanya selalu konsisten dan aman jika sync dikirim ulang.
  ///
  /// Query-then-upsert manual di sini (bukan insertOnConflictUpdate memakai
  /// uniqueKeys tabel Stok) karena SQLite menganggap setiap NULL berbeda,
  /// jadi baris dengan varianId NULL tidak akan match constraint unique itu.
  ///
  /// Mengembalikan saldo+batasMinimum SETELAH mutasi - dipakai pemanggil
  /// (lihat TransaksiRepository.checkout) utk tahu apakah transaksi ini
  /// yang bikin stok produk jadi menipis, tanpa query terpisah lagi.
  Future<({double saldoSetelah, double batasMinimum})> catatMutasi({
    required String tokoId,
    required String outletId,
    required String produkId,
    String? varianId,
    required MutasiJenis jenis,
    required double qty,
    int hppSatuan = 0,
    String? refTipe,
    String? refId,
    String? catatan,
    String? dibuatOleh,
    // Bug nyata (laporan pengguna: "ingatkan jika sisa" diisi 10 pas
    // tambah produk, tapi tab Stok menipis tetap 0") - SEBELUMNYA method
    // ini tidak punya cara menerima batasMinimum sama sekali, jadi form
    // produk SELALU kehilangan nilai field itu walau controller-nya ada
    // di UI. null = jangan sentuh (pertahankan nilai lama, spt perilaku
    // sebelumnya) - dikirim eksplisit hanya saat stok awal produk baru.
    double? batasMinimum,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;

    return transaction(() async {
      final existing = await (select(stok)
            ..where((t) =>
                t.outletId.equals(outletId) &
                t.produkId.equals(produkId) &
                (varianId == null ? t.varianId.isNull() : t.varianId.equals(varianId))))
          .getSingleOrNull();

      final saldoSebelum = existing?.jumlah ?? 0;
      final saldoSetelah = saldoSebelum + qty;
      final batasMinimumBaru = batasMinimum ?? existing?.batasMinimum ?? 0;

      if (existing == null) {
        await into(stok).insert(StokCompanion.insert(
          id: generateId(),
          outletId: outletId,
          produkId: produkId,
          varianId: Value(varianId),
          jumlah: Value(saldoSetelah),
          batasMinimum: Value(batasMinimumBaru),
          createdAt: now,
          updatedAt: now,
        ));
      } else {
        await (update(stok)..where((t) => t.id.equals(existing.id))).write(
          StokCompanion(
            jumlah: Value(saldoSetelah),
            batasMinimum: Value(batasMinimumBaru),
            updatedAt: Value(now),
          ),
        );
      }

      await into(mutasiStok).insert(MutasiStokCompanion.insert(
        id: generateId(),
        tokoId: tokoId,
        outletId: outletId,
        produkId: produkId,
        varianId: Value(varianId),
        jenis: jenis,
        qty: qty,
        hppSatuan: Value(hppSatuan),
        saldoSetelah: Value(saldoSetelah),
        refTipe: Value(refTipe),
        refId: Value(refId),
        catatan: Value(catatan),
        dibuatOleh: Value(dibuatOleh),
        createdAt: now,
        updatedAt: now,
      ));

      return (saldoSetelah: saldoSetelah, batasMinimum: batasMinimumBaru);
    });
  }

  /// Dipakai pull-sync (SyncRepository) - timpa SALDO saja dari server,
  /// TANPA menulis baris mutasi_stok (beda dgn catatMutasi, yang memang
  /// untuk mutasi sungguhan hasil aksi lokal). Query-then-upsert manual
  /// dengan alasan yang sama seperti catatMutasi: SQLite menganggap setiap
  /// NULL berbeda jadi tidak bisa pakai insertOnConflictUpdate biasa utk
  /// baris dengan varianId NULL.
  Future<void> upsertSaldoDariSync({
    required String id,
    required String outletId,
    required String produkId,
    String? varianId,
    required double jumlah,
    required double batasMinimum,
    required int hppRataRata,
    required int updatedAt,
    int? deletedAt,
  }) async {
    final existing = await (select(stok)
          ..where((t) =>
              t.outletId.equals(outletId) &
              t.produkId.equals(produkId) &
              (varianId == null ? t.varianId.isNull() : t.varianId.equals(varianId))))
        .getSingleOrNull();

    final companion = StokCompanion(
      jumlah: Value(jumlah),
      batasMinimum: Value(batasMinimum),
      hppRataRata: Value(hppRataRata),
      updatedAt: Value(updatedAt),
      deletedAt: Value(deletedAt),
    );

    if (existing == null) {
      await into(stok).insert(StokCompanion.insert(
        id: id,
        outletId: outletId,
        produkId: produkId,
        varianId: Value(varianId),
        jumlah: Value(jumlah),
        batasMinimum: Value(batasMinimum),
        hppRataRata: Value(hppRataRata),
        createdAt: updatedAt,
        updatedAt: updatedAt,
        deletedAt: Value(deletedAt),
      ));
    } else {
      await (update(stok)..where((t) => t.id.equals(existing.id))).write(companion);
    }
  }
}
