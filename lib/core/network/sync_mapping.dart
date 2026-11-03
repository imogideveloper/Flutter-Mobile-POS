/// Konversi nilai mentah JSON dari backend (lihat `_ke_dict` di
/// backend/app/services/sync_service.py - semua kolom Decimal/UUID/
/// datetime dikirim sbg STRING, bool/int apa adanya) ke tipe kolom Drift
/// lokal. Dipakai SyncRepository saat pull - taruh semua aturan konversi
/// di satu tempat supaya tidak diulang per tabel.
library;

/// Kolom uang (hpp, harga_jual, dll - IntColumn rupiah di lokal) - backend
/// kirim string Decimal mis. "15000.00", dibulatkan ke int terdekat.
int uangDariBackend(String nilai) => double.parse(nilai).round();

int? uangDariBackendNullable(String? nilai) =>
    nilai == null ? null : uangDariBackend(nilai);

/// Kolom persen/qty (RealColumn di lokal - pajak.persen, promo.nilai,
/// stok.jumlah/batas_minimum) - backend kirim string Decimal, dipakai
/// sebagai double apa adanya (presisi dipertahankan, TIDAK dibulatkan).
double realDariBackend(String nilai) => double.parse(nilai);

double? realDariBackendNullable(String? nilai) =>
    nilai == null ? null : realDariBackend(nilai);

/// Timestamp ISO8601 dari backend -> epoch ms UTC (konvensi kolom
/// IntColumn createdAt/updatedAt/deletedAt di semua tabel lokal).
int epochMsDariBackend(String iso8601) => DateTime.parse(iso8601).toUtc().millisecondsSinceEpoch;

int? epochMsDariBackendNullable(String? iso8601) =>
    iso8601 == null ? null : epochMsDariBackend(iso8601);

/// produk.tipe: backend snake_case ('bahan_baku') <-> Dart enum
/// ('bahanBaku') - lihat produkTipePostgresValue di produk_table.dart
/// (arah sebaliknya, Dart->Postgres, dipakai saat push kalau nanti ada).
const _produkTipeDariPostgres = <String, String>{
  'barang': 'barang',
  'jasa': 'jasa',
  'bahan_baku': 'bahanBaku',
  'bundling': 'bundling',
};

String produkTipeDariBackend(String nilaiBackend) =>
    _produkTipeDariPostgres[nilaiBackend] ?? nilaiBackend;
