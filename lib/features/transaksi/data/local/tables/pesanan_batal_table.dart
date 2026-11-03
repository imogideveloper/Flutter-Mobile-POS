import 'package:drift/drift.dart';

/// Temuan#2 (rapikan F3.E) - antrean kecil pembatalan pesanan tersimpan
/// yang BELUM terkirim ke server, dgn watermark `disinkronPada` (pola
/// SAMA PERSIS dgn `pembayaran.disinkronPada` - lihat
/// SyncRepository._pembayaranStandalonePayload). Dibuat TERPISAH dari
/// tabel `transaksi` (BUKAN reuse TransaksiStatus.dibatalkan+alasanVoid)
/// krn alur void transaksi SELESAI yang sudah ada punya bug lama: void
/// TIDAK mereset `disinkronPada` transaksi yang sudah pernah tersync,
/// jadi tidak pernah ikut terpush lagi - menumpang di situ akan mewarisi
/// bug yang sama. `isiPesanan`/`total`/`nomorStruk` adalah SNAPSHOT (draft
/// aslinya sudah dihapus lewat hapusPesananTersimpan sebelum baris ini
/// sempat dipush) - dibutuhkan server utk audit_log (siapa/kapan/isi
/// pesanan/total/alasan).
@DataClassName('PesananBatalRow')
class PesananBatal extends Table {
  @override
  String get tableName => 'pesanan_batal_lokal';

  TextColumn get id => text()(); // = id pesanan tersimpan yang dibatalkan
  TextColumn get alasan => text()();
  TextColumn get disetujuiOleh => text().nullable()();
  // Tahap 5b (desain #4) - karyawan yang MEMINTA pembatalan (beda dari
  // disetujuiOleh = approver kalau butuh approval PIN).
  TextColumn get penggunaId => text().nullable()();
  TextColumn get isiPesanan => text()(); // JSON list {produkId,namaProduk,qty}
  IntColumn get total => integer()();
  TextColumn get nomorStruk => text()();
  IntColumn get dibatalkanPada => integer()();
  IntColumn get disinkronPada => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
