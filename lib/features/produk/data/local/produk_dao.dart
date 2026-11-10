import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/grup_tambahan.dart';
import 'tables/grup_modifier_table.dart';
import 'tables/kategori_table.dart';
import 'tables/modifier_table.dart';
import 'tables/produk_grup_modifier_table.dart';
import 'tables/produk_table.dart';
import 'tables/produk_varian_table.dart';

part 'produk_dao.g.dart';

@DriftAccessor(tables: [Produk, ProdukVarian, Kategori, GrupModifier, Modifier, ProdukGrupModifier])
class ProdukDao extends DatabaseAccessor<AppDatabase> with _$ProdukDaoMixin {
  ProdukDao(super.db);

  Stream<List<ProdukRow>> watchProdukAktif() =>
      (select(produk)..where((t) => t.aktif.equals(true) & t.deletedAt.isNull()))
          .watch();

  /// Termasuk produk nonaktif - dipakai filter chip "Nonaktif" di daftar
  /// produk (watchProdukAktif sengaja tidak dipakai di sana karena memang
  /// hanya mengembalikan yang aktif).
  Stream<List<ProdukRow>> watchProdukSemua() =>
      (select(produk)..where((t) => t.deletedAt.isNull())).watch();

  Future<ProdukRow?> produkById(String id) =>
      (select(produk)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<ProdukRow?> findByBarcode(String barcode) =>
      (select(produk)..where((t) => t.barcode.equals(barcode) & t.deletedAt.isNull()))
          .getSingleOrNull();

  Future<List<ProdukVarianRow>> varianUntukProduk(String produkId) =>
      (select(produkVarian)..where((t) => t.produkId.equals(produkId) & t.deletedAt.isNull()))
          .get();

  Future<void> upsertProduk(ProdukCompanion data) =>
      into(produk).insertOnConflictUpdate(data);

  /// Update sebagian (bukan insertOnConflictUpdate) - sengaja tidak
  /// menyentuh createdAt baris yang sudah ada.
  Future<void> updateProduk(String id, ProdukCompanion data) =>
      (update(produk)..where((t) => t.id.equals(id))).write(data);

  /// Hapus PERMANEN (bukan soft-delete via deletedAt) - khusus "produk
  /// hantu" (lihat catatan idBerubah di produk_form_page.dart::_simpan):
  /// baris lokal dari era sebelum online-direct yang ternyata tidak pernah
  /// ada di server, dibuang begitu "lahir ulang" sbg produk server baru
  /// dgn id berbeda, supaya tidak nyangkut jadi duplikat kedua.
  Future<void> hapusPermanen(String id) =>
      (delete(produk)..where((t) => t.id.equals(id))).go();

  /// Dipakai pull-sync (SyncRepository) DAN form kategori online-direct
  /// (lihat kategori_form_page.dart) - kategori ikut masuk accessor ini
  /// krn produk punya FK ke kategori.
  Future<void> upsertKategori(KategoriCompanion data) =>
      into(kategori).insertOnConflictUpdate(data);

  Stream<List<KategoriRow>> watchKategoriAktif(String tokoId) =>
      (select(kategori)
            ..where((t) => t.tokoId.equals(tokoId) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.urutan)]))
          .watch();

  /// Cache lokal setelah DELETE (soft delete) sukses di backend - pola
  /// sama dgn PajakDao.nonaktifkanLokal, bedanya kategori tidak punya
  /// kolom `aktif` (cuma deletedAt, sesuai skema resmi).
  /// Id produk (dari [produkIds]) yang kategorinya TIDAK masuk tiket dapur.
  /// Produk tanpa kategori selalu masuk tiket.
  Future<Set<String>> produkTanpaTiketDapur(Iterable<String> produkIds) async {
    final ids = produkIds.toSet();
    if (ids.isEmpty) return {};
    final rows = await (select(produk).join([
      innerJoin(kategori, kategori.id.equalsExp(produk.kategoriId)),
    ])
          ..where(produk.id.isIn(ids) & kategori.masukTiketDapur.equals(false)))
        .map((r) => r.read(produk.id)!)
        .get();
    return rows.toSet();
  }

  // ---- Varian/tambahan produk (IMOGI no. 42) ----

  Future<void> upsertGrupModifier(GrupModifierCompanion data) => into(grupModifier).insertOnConflictUpdate(data);

  Future<void> upsertModifier(ModifierCompanion data) => into(modifier).insertOnConflictUpdate(data);

  /// Mengganti SELURUH relasi produk-grup dengan [pasangan] (produkId, grupId):
  /// server selalu mengirim snapshot penuh, jadi relasi yang dilepas di server
  /// ikut hilang di HP.
  Future<void> gantiRelasiProdukGrup(List<(String, String)> pasangan) => transaction(() async {
        await delete(produkGrupModifier).go();
        final now = DateTime.now().millisecondsSinceEpoch;
        await batch((b) => b.insertAll(
              produkGrupModifier,
              [
                for (final (p, g) in pasangan)
                  ProdukGrupModifierCompanion.insert(produkId: p, grupModifierId: g, createdAt: now),
              ],
              mode: InsertMode.insertOrReplace,
            ));
      });

  /// Grup tambahan beserta opsi aktifnya untuk satu produk, berurutan.
  /// Grup tanpa opsi aktif tidak ditampilkan (tidak ada yang bisa dipilih).
  Future<List<GrupTambahan>> grupUntukProduk(String produkId) async {
    final grupRows = await (select(grupModifier).join([
      innerJoin(produkGrupModifier, produkGrupModifier.grupModifierId.equalsExp(grupModifier.id)),
    ])
          ..where(produkGrupModifier.produkId.equals(produkId) & grupModifier.deletedAt.isNull())
          ..orderBy([OrderingTerm.asc(grupModifier.nama)]))
        .map((r) => r.readTable(grupModifier))
        .get();
    if (grupRows.isEmpty) return const [];
    final opsiRows = await (select(modifier)
          ..where((t) => t.grupModifierId.isIn([for (final g in grupRows) g.id]) & t.aktif.equals(true) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.urutan), (t) => OrderingTerm.asc(t.nama)]))
        .get();
    return [
      for (final g in grupRows)
        if (opsiRows.any((o) => o.grupModifierId == g.id))
          GrupTambahan(
            id: g.id,
            nama: g.nama,
            minPilih: g.minPilih,
            maksPilih: g.maksPilih,
            opsi: [
              for (final o in opsiRows)
                if (o.grupModifierId == g.id) OpsiTambahan(id: o.id, nama: o.nama, harga: o.hargaTambahan),
            ],
          ),
    ];
  }

  /// Semua grup toko beserta SELURUH opsinya (termasuk nonaktif) untuk halaman
  /// kelola; ikut diperbarui saat grup/opsi/relasi berubah.
  Stream<List<GrupTambahan>> watchGrupKelola() => customSelect(
        'SELECT 1',
        readsFrom: {grupModifier, modifier, produkGrupModifier},
      ).watch().asyncMap((_) async {
        final grupRows = await (select(grupModifier)
              ..where((t) => t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.asc(t.nama)]))
            .get();
        if (grupRows.isEmpty) return <GrupTambahan>[];
        final opsiRows = await (select(modifier)
              ..where((t) => t.grupModifierId.isIn([for (final g in grupRows) g.id]) & t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.asc(t.urutan), (t) => OrderingTerm.asc(t.nama)]))
            .get();
        return [
          for (final g in grupRows)
            GrupTambahan(
              id: g.id,
              nama: g.nama,
              minPilih: g.minPilih,
              maksPilih: g.maksPilih,
              opsi: [
                for (final o in opsiRows)
                  if (o.grupModifierId == g.id)
                    OpsiTambahan(id: o.id, nama: o.nama, harga: o.hargaTambahan, aktif: o.aktif),
              ],
            ),
        ];
      });

  Future<Set<String>> produkIdUntukGrup(String grupId) async {
    final rows = await (select(produkGrupModifier)..where((t) => t.grupModifierId.equals(grupId))).get();
    return {for (final r in rows) r.produkId};
  }

  /// Cache lokal setelah PUT .../produk sukses di server.
  Future<void> setProdukUntukGrupLokal(String grupId, Set<String> produkIds) => transaction(() async {
        await (delete(produkGrupModifier)..where((t) => t.grupModifierId.equals(grupId))).go();
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final id in produkIds) {
          await into(produkGrupModifier).insertOnConflictUpdate(
            ProdukGrupModifierCompanion.insert(produkId: id, grupModifierId: grupId, createdAt: now),
          );
        }
      });

  Future<void> hapusGrupLokal(String id) => (update(grupModifier)..where((t) => t.id.equals(id)))
      .write(GrupModifierCompanion(deletedAt: Value(DateTime.now().millisecondsSinceEpoch)));

  Future<void> hapusModifierLokal(String id) => (update(modifier)..where((t) => t.id.equals(id)))
      .write(ModifierCompanion(deletedAt: Value(DateTime.now().millisecondsSinceEpoch)));

  Future<void> hapusKategoriLokal(String id) => (update(kategori)..where((t) => t.id.equals(id)))
      .write(KategoriCompanion(deletedAt: Value(DateTime.now().millisecondsSinceEpoch)));
}
