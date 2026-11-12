import 'package:intl/intl.dart';

/// Kategori pengeluaran (IMOGI no. 67), sama dengan kode di server. Untuk F&B: belanja bahan
/// masuk HPP; gas LPG dan kemasan adalah biaya operasional harian khas kafe.
const kategoriPengeluaran = <String, String>{
  'belanja_bahan': 'Belanja bahan (HPP)',
  'gas_lpg': 'Gas LPG',
  'kemasan': 'Kemasan',
  'gaji': 'Gaji',
  'sewa': 'Sewa',
  'listrik_air': 'Listrik & air',
  'pemasaran': 'Pemasaran',
  'perawatan': 'Perawatan',
  'lainnya': 'Lainnya',
};

String labelKategoriPengeluaran(String kode) => kategoriPengeluaran[kode] ?? kode;

enum RentangPengeluaran { hariIni, tujuhHari, bulanIni }

extension RentangPengeluaranX on RentangPengeluaran {
  String get label => switch (this) {
        RentangPengeluaran.hariIni => 'Hari ini',
        RentangPengeluaran.tujuhHari => '7 hari',
        RentangPengeluaran.bulanIni => 'Bulan ini',
      };

  /// Tanggal awal dan akhir (inklusif) untuk [sekarang].
  (DateTime dari, DateTime sampai) tanggal(DateTime sekarang) {
    final hari = DateTime(sekarang.year, sekarang.month, sekarang.day);
    return switch (this) {
      RentangPengeluaran.hariIni => (hari, hari),
      RentangPengeluaran.tujuhHari => (hari.subtract(const Duration(days: 6)), hari),
      RentangPengeluaran.bulanIni => (DateTime(hari.year, hari.month, 1), hari),
    };
  }
}

/// "2026-11-12", format tanggal yang dipakai server.
String tanggalApi(DateTime t) => DateFormat('yyyy-MM-dd').format(t);

class PengeluaranItem {
  const PengeluaranItem({
    required this.id,
    required this.tanggal,
    required this.kategori,
    required this.jumlah,
    this.catatan,
  });

  factory PengeluaranItem.dariJson(Map<String, dynamic> j) => PengeluaranItem(
        id: j['id'] as String,
        tanggal: j['tanggal'] as String,
        kategori: j['kategori'] as String,
        jumlah: (j['jumlah'] as num).round(),
        catatan: j['catatan'] as String?,
      );

  final String id;
  final String tanggal;
  final String kategori;
  final int jumlah;
  final String? catatan;
}

class DaftarPengeluaran {
  const DaftarPengeluaran({required this.total, required this.perKategori, required this.item});

  factory DaftarPengeluaran.dariJson(Map<String, dynamic> j) => DaftarPengeluaran(
        total: (j['total'] as num).round(),
        perKategori: {
          for (final k in (j['per_kategori'] as List? ?? const []))
            (k as Map<String, dynamic>)['kategori'] as String: (k['total'] as num).round(),
        },
        item: [
          for (final i in (j['item'] as List? ?? const []))
            PengeluaranItem.dariJson(i as Map<String, dynamic>),
        ],
      );

  final int total;
  final Map<String, int> perKategori;
  final List<PengeluaranItem> item;
}
