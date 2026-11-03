import '../domain/mutasi_item.dart';
import '../domain/stok_item.dart';
import '../domain/stok_mapper.dart';
import 'local/stok_dao.dart';
import 'local/tables/mutasi_stok_table.dart' show MutasiJenis;

class StokRepository {
  StokRepository(this._dao);

  final StokDao _dao;

  Stream<List<StokItem>> watchStokOutlet(String outletId) => _dao
      .watchStokOutletDenganProduk(outletId)
      .map((rows) => rows.map((row) => row.toDomain()).toList());

  Stream<List<MutasiItem>> watchMutasiTerakhir(String outletId, {int limit = 10}) => _dao
      .watchMutasiTerakhir(outletId, limit: limit)
      .map((rows) => rows.map((row) => row.toDomain()).toList());

  Future<double> batasMinimumUntuk({
    required String outletId,
    required String produkId,
    String? varianId,
  }) async {
    final row = await _dao.cariStok(outletId: outletId, produkId: produkId, varianId: varianId);
    return row?.batasMinimum ?? 0;
  }

  Future<void> aturBatasMinimum({
    required String outletId,
    required String produkId,
    String? varianId,
    required double batasMinimum,
  }) {
    return _dao.aturBatasMinimum(
      outletId: outletId,
      produkId: produkId,
      varianId: varianId,
      batasMinimum: batasMinimum,
    );
  }

  /// Qty bertanda: positif menambah saldo (pembelian, stok awal, dst),
  /// negatif mengurangi (penjualan, transfer keluar, dst) - lihat
  /// StokDao.catatMutasi.
  Future<void> catatMutasi({
    required String tokoId,
    required String outletId,
    required String produkId,
    String? varianId,
    required MutasiJenis jenis,
    required double qty,
    String? catatan,
    String? dibuatOleh,
    double? batasMinimum,
  }) {
    return _dao.catatMutasi(
      tokoId: tokoId,
      outletId: outletId,
      produkId: produkId,
      varianId: varianId,
      jenis: jenis,
      qty: qty,
      catatan: catatan,
      dibuatOleh: dibuatOleh,
      batasMinimum: batasMinimum,
    );
  }
}
